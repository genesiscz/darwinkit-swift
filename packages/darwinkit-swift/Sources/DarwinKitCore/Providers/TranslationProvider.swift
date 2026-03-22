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
