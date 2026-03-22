import Foundation

// MARK: - Translation Result

public struct TranslationResult {
    public let text: String
    public let sourceLanguage: String
    public let targetLanguage: String

    public init(text: String, sourceLanguage: String, targetLanguage: String) {
        self.text = text
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
    }

    public func toDict() -> [String: Any] {
        [
            "text": text,
            "source": sourceLanguage,
            "target": targetLanguage,
        ]
    }
}

// MARK: - Language Info

public struct TranslationLanguageInfo {
    public let locale: String
    public let name: String

    public init(locale: String, name: String) {
        self.locale = locale
        self.name = name
    }

    public func toDict() -> [String: Any] {
        [
            "locale": locale,
            "name": name,
        ]
    }
}

// MARK: - Language Pair Status

public enum TranslationPairStatus: String {
    case installed
    case supported
    case unsupported
}

// MARK: - Provider Protocol

public protocol TranslationProvider {
    /// Translate a single text. Source can be nil for auto-detection.
    func translate(text: String, source: String?, target: String) throws -> TranslationResult

    /// Translate multiple texts. Source can be nil for auto-detection.
    func translateBatch(texts: [String], source: String?, target: String) throws -> [TranslationResult]

    /// List all supported languages.
    func supportedLanguages() throws -> [TranslationLanguageInfo]

    /// Check if a language pair is installed/supported/unsupported.
    func languagePairStatus(source: String, target: String) throws -> TranslationPairStatus

    /// Download/prepare translation models for a language pair.
    func prepare(source: String, target: String) throws
}

// MARK: - Apple Implementation

#if canImport(Translation)
import NaturalLanguage
import Translation

@available(macOS 15.0, *)
public final class AppleTranslationProvider: TranslationProvider {

    public init() {}

    public func translate(text: String, source: String?, target: String) throws -> TranslationResult {
        guard #available(macOS 26.0, *) else {
            throw JsonRpcError.osVersionTooOld(
                "Programmatic translation requires macOS 26.0+. " +
                "TranslationSession init is only available from macOS 26."
            )
        }
        return try translateImpl(text: text, source: source, target: target)
    }

    public func translateBatch(texts: [String], source: String?, target: String) throws -> [TranslationResult] {
        guard #available(macOS 26.0, *) else {
            throw JsonRpcError.osVersionTooOld(
                "Programmatic translation requires macOS 26.0+. " +
                "TranslationSession init is only available from macOS 26."
            )
        }
        return try translateBatchImpl(texts: texts, source: source, target: target)
    }

    public func supportedLanguages() throws -> [TranslationLanguageInfo] {
        var languages: [TranslationLanguageInfo] = []
        var queryError: Error?

        let semaphore = DispatchSemaphore(value: 0)

        Task {
            do {
                let availability = LanguageAvailability()
                let supported = await availability.supportedLanguages
                languages = supported.map { lang in
                    let locale = Locale(identifier: lang.minimalIdentifier)
                    let name = locale.localizedString(forIdentifier: lang.minimalIdentifier) ?? lang.minimalIdentifier
                    return TranslationLanguageInfo(
                        locale: lang.minimalIdentifier,
                        name: name
                    )
                }
            } catch {
                queryError = error
            }
            semaphore.signal()
        }

        semaphore.wait()

        if let error = queryError {
            throw JsonRpcError.internalError("Failed to query languages: \(error.localizedDescription)")
        }

        return languages.sorted { $0.locale < $1.locale }
    }

    public func languagePairStatus(source: String, target: String) throws -> TranslationPairStatus {
        let sourceLang = Locale.Language(identifier: source)
        let targetLang = Locale.Language(identifier: target)

        var status: TranslationPairStatus = .unsupported

        let semaphore = DispatchSemaphore(value: 0)

        Task {
            let availability = LanguageAvailability()
            let rawStatus = await availability.status(from: sourceLang, to: targetLang)
            switch rawStatus {
            case .installed:
                status = .installed
            case .supported:
                status = .supported
            case .unsupported:
                status = .unsupported
            @unknown default:
                status = .unsupported
            }
            semaphore.signal()
        }

        semaphore.wait()

        return status
    }

    public func prepare(source: String, target: String) throws {
        guard #available(macOS 26.0, *) else {
            throw JsonRpcError.osVersionTooOld(
                "Programmatic translation requires macOS 26.0+. " +
                "TranslationSession init is only available from macOS 26."
            )
        }
        try prepareImpl(source: source, target: target)
    }

    // MARK: - macOS 26+ Implementations

    @available(macOS 26.0, *)
    private func translateImpl(text: String, source: String?, target: String) throws -> TranslationResult {
        let resolvedSource = source ?? detectLanguage(text)
        let sourceLang = Locale.Language(identifier: resolvedSource)
        let targetLang = Locale.Language(identifier: target)

        var translatedText: String = ""
        var detectedSource: String = resolvedSource
        var translationError: Error?

        let semaphore = DispatchSemaphore(value: 0)

        Task {
            do {
                let session = TranslationSession(installedSource: sourceLang, target: targetLang)
                let response = try await session.translate(text)
                translatedText = response.targetText
                detectedSource = response.sourceLanguage.minimalIdentifier
            } catch {
                translationError = error
            }
            semaphore.signal()
        }

        semaphore.wait()

        if let error = translationError {
            throw JsonRpcError.internalError("Translation failed: \(error.localizedDescription)")
        }

        return TranslationResult(
            text: translatedText,
            sourceLanguage: detectedSource,
            targetLanguage: target
        )
    }

    @available(macOS 26.0, *)
    private func translateBatchImpl(texts: [String], source: String?, target: String) throws -> [TranslationResult] {
        let resolvedSource = source ?? detectLanguage(texts.first ?? "")
        let sourceLang = Locale.Language(identifier: resolvedSource)
        let targetLang = Locale.Language(identifier: target)

        var results: [TranslationResult] = []
        var translationError: Error?

        let semaphore = DispatchSemaphore(value: 0)

        Task {
            do {
                let session = TranslationSession(installedSource: sourceLang, target: targetLang)
                let requests = texts.enumerated().map { (index, text) in
                    TranslationSession.Request(sourceText: text, clientIdentifier: "\(index)")
                }
                let responses = try await session.translations(from: requests)

                // Build results ordered by clientIdentifier
                var responseMap: [String: TranslationSession.Response] = [:]
                for response in responses {
                    if let id = response.clientIdentifier {
                        responseMap[id] = response
                    }
                }

                for i in 0..<texts.count {
                    if let response = responseMap["\(i)"] {
                        let src = response.sourceLanguage.minimalIdentifier
                        results.append(TranslationResult(
                            text: response.targetText,
                            sourceLanguage: src,
                            targetLanguage: target
                        ))
                    }
                }
            } catch {
                translationError = error
            }
            semaphore.signal()
        }

        semaphore.wait()

        if let error = translationError {
            throw JsonRpcError.internalError("Batch translation failed: \(error.localizedDescription)")
        }

        return results
    }

    @available(macOS 26.0, *)
    private func prepareImpl(source: String, target: String) throws {
        let sourceLang = Locale.Language(identifier: source)
        let targetLang = Locale.Language(identifier: target)

        var prepareError: Error?

        let semaphore = DispatchSemaphore(value: 0)

        Task {
            do {
                let session = TranslationSession(installedSource: sourceLang, target: targetLang)
                try await session.prepareTranslation()
            } catch {
                prepareError = error
            }
            semaphore.signal()
        }

        semaphore.wait()

        if let error = prepareError {
            throw JsonRpcError.internalError("Failed to prepare translation models: \(error.localizedDescription)")
        }
    }

    // MARK: - Private Helpers

    /// Auto-detect language using NaturalLanguage framework
    private func detectLanguage(_ text: String) -> String {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage?.rawValue ?? "en"
    }
}

#else

/// Fallback for when Translation framework is not available (older Xcode / macOS)
public final class AppleTranslationProvider: TranslationProvider {
    public init() {}

    public func translate(text: String, source: String?, target: String) throws -> TranslationResult {
        throw JsonRpcError.osVersionTooOld("Translation requires macOS 15.0+")
    }

    public func translateBatch(texts: [String], source: String?, target: String) throws -> [TranslationResult] {
        throw JsonRpcError.osVersionTooOld("Translation requires macOS 15.0+")
    }

    public func supportedLanguages() throws -> [TranslationLanguageInfo] {
        throw JsonRpcError.osVersionTooOld("Translation requires macOS 15.0+")
    }

    public func languagePairStatus(source: String, target: String) throws -> TranslationPairStatus {
        throw JsonRpcError.osVersionTooOld("Translation requires macOS 15.0+")
    }

    public func prepare(source: String, target: String) throws {
        throw JsonRpcError.osVersionTooOld("Translation requires macOS 15.0+")
    }
}

#endif
