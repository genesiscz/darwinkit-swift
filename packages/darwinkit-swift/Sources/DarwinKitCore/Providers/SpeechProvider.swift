import Foundation

// MARK: - Data Types

/// A single segment of transcribed speech with timing info.
public struct TranscriptionSegment {
    public let text: String
    public let startTime: Double  // seconds
    public let endTime: Double    // seconds
    public let isFinal: Bool

    public init(text: String, startTime: Double, endTime: Double, isFinal: Bool) {
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.isFinal = isFinal
    }

    public func toDict() -> [String: Any] {
        [
            "text": text,
            "start_time": startTime,
            "end_time": endTime,
            "is_final": isFinal,
        ]
    }
}

/// Full transcription result for an audio file.
public struct TranscriptionResult {
    public let text: String
    public let segments: [TranscriptionSegment]
    public let language: String
    public let duration: Double  // total audio duration in seconds

    public init(text: String, segments: [TranscriptionSegment], language: String, duration: Double) {
        self.text = text
        self.segments = segments
        self.language = language
        self.duration = duration
    }

    public func toDict() -> [String: Any] {
        [
            "text": text,
            "segments": segments.map { $0.toDict() },
            "language": language,
            "duration": duration,
        ]
    }
}

/// Language info for speech recognition.
public struct SpeechLanguageInfo {
    public let locale: String
    public let installed: Bool

    public init(locale: String, installed: Bool) {
        self.locale = locale
        self.installed = installed
    }

    public func toDict() -> [String: Any] {
        [
            "locale": locale,
            "installed": installed,
        ]
    }
}

/// Device capabilities for speech recognition.
public struct SpeechCapabilities {
    public let available: Bool
    public let reason: String?

    public init(available: Bool, reason: String? = nil) {
        self.available = available
        self.reason = reason
    }

    public func toDict() -> [String: Any] {
        var result: [String: Any] = ["available": available]
        if let reason = reason { result["reason"] = reason }
        return result
    }
}

// MARK: - Provider Protocol

public protocol SpeechProvider {
    /// Transcribe an audio file at the given path.
    func transcribe(path: String, language: String, includeTimestamps: Bool) throws -> TranscriptionResult

    /// List all supported locales for speech recognition.
    func supportedLanguages() throws -> [SpeechLanguageInfo]

    /// List only installed (downloaded) locales.
    func installedLanguages() throws -> [SpeechLanguageInfo]

    /// Download a language model for offline use.
    func installLanguage(locale: String) throws

    /// Remove a downloaded language model.
    func uninstallLanguage(locale: String) throws

    /// Check device capabilities for speech recognition.
    func capabilities() throws -> SpeechCapabilities
}

// MARK: - Apple Implementation

#if canImport(Speech)
import Speech

/// Factory that returns AppleSpeechProvider if Speech framework is available.
public func makeAppleSpeechProvider() -> SpeechProvider {
    return AppleSpeechProvider()
}

public final class AppleSpeechProvider: SpeechProvider {

    public init() {}

    deinit {}

    public func transcribe(path: String, language: String, includeTimestamps: Bool) throws -> TranscriptionResult {
        let url = URL(fileURLWithPath: path)

        guard FileManager.default.fileExists(atPath: path) else {
            throw JsonRpcError.invalidParams("File not found: \(path)")
        }

        let locale = Locale(identifier: language)

        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            throw JsonRpcError.frameworkUnavailable(
                "Speech recognition not available for locale: \(language)"
            )
        }

        guard recognizer.isAvailable else {
            throw JsonRpcError.frameworkUnavailable(
                "Speech recognizer is not currently available"
            )
        }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false

        let semaphore = DispatchSemaphore(value: 0)
        var transcribeResult: SFSpeechRecognitionResult?
        var transcribeError: Error?

        recognizer.recognitionTask(with: request) { result, error in
            if let error = error {
                transcribeError = error
                semaphore.signal()
                return
            }
            if let result = result, result.isFinal {
                transcribeResult = result
                semaphore.signal()
            }
        }

        let timeoutResult = semaphore.wait(timeout: .now() + 300.0)

        if timeoutResult == .timedOut {
            let timeoutError = NSError(
                domain: "com.darwinkit.speech",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Transcription timed out after 300 seconds"]
            )
            transcribeError = timeoutError
        }

        if let error = transcribeError {
            throw JsonRpcError.internalError("Transcription failed: \(error.localizedDescription)")
        }

        guard let sfResult = transcribeResult else {
            throw JsonRpcError.internalError("Transcription returned no result")
        }

        let bestTranscription = sfResult.bestTranscription
        let fullText = bestTranscription.formattedString

        var segments: [TranscriptionSegment] = []
        if includeTimestamps {
            for segment in bestTranscription.segments {
                segments.append(TranscriptionSegment(
                    text: segment.substring,
                    startTime: segment.timestamp,
                    endTime: segment.timestamp + segment.duration,
                    isFinal: true
                ))
            }
        }

        let duration = bestTranscription.segments.last.map {
            $0.timestamp + $0.duration
        } ?? 0

        return TranscriptionResult(
            text: fullText,
            segments: segments,
            language: language,
            duration: duration
        )
    }

    public func supportedLanguages() throws -> [SpeechLanguageInfo] {
        let supported = SFSpeechRecognizer.supportedLocales()
        return supported.map { locale in
            SpeechLanguageInfo(locale: locale.identifier, installed: true)
        }
    }

    public func installedLanguages() throws -> [SpeechLanguageInfo] {
        // On macOS, all supported locales are available (no separate download needed
        // in the classic Speech framework)
        let supported = SFSpeechRecognizer.supportedLocales()
        return supported.map { locale in
            SpeechLanguageInfo(locale: locale.identifier, installed: true)
        }
    }

    public func installLanguage(locale: String) throws {
        // SFSpeechRecognizer does not support downloading individual language models.
        // All supported locales are already available on the system.
        let supported = SFSpeechRecognizer.supportedLocales()
        let loc = Locale(identifier: locale)
        guard supported.contains(loc) else {
            throw JsonRpcError.invalidParams("Unsupported locale: \(locale)")
        }
        // No-op: language is already installed
    }

    public func uninstallLanguage(locale: String) throws {
        // SFSpeechRecognizer does not support uninstalling language models.
        throw JsonRpcError.invalidParams(
            "Language models cannot be uninstalled with the current Speech framework"
        )
    }

    public func capabilities() throws -> SpeechCapabilities {
        let status = SFSpeechRecognizer.authorizationStatus()
        switch status {
        case .authorized:
            return SpeechCapabilities(available: true)
        case .denied:
            return SpeechCapabilities(available: false, reason: "Speech recognition permission denied")
        case .restricted:
            return SpeechCapabilities(available: false, reason: "Speech recognition is restricted on this device")
        case .notDetermined:
            return SpeechCapabilities(available: false, reason: "Speech recognition permission not yet requested")
        @unknown default:
            return SpeechCapabilities(available: false, reason: "Unknown authorization status")
        }
    }
}

#else

/// Stub provider when Speech framework is not available.
/// All methods throw frameworkUnavailable.
public final class StubSpeechProvider: SpeechProvider {
    public init() {}

    deinit {}

    public func transcribe(path: String, language: String, includeTimestamps: Bool) throws -> TranscriptionResult {
        throw JsonRpcError.frameworkUnavailable("Speech framework is not available on this platform")
    }

    public func supportedLanguages() throws -> [SpeechLanguageInfo] {
        throw JsonRpcError.frameworkUnavailable("Speech framework is not available on this platform")
    }

    public func installedLanguages() throws -> [SpeechLanguageInfo] {
        throw JsonRpcError.frameworkUnavailable("Speech framework is not available on this platform")
    }

    public func installLanguage(locale: String) throws {
        throw JsonRpcError.frameworkUnavailable("Speech framework is not available on this platform")
    }

    public func uninstallLanguage(locale: String) throws {
        throw JsonRpcError.frameworkUnavailable("Speech framework is not available on this platform")
    }

    public func capabilities() throws -> SpeechCapabilities {
        return SpeechCapabilities(available: false, reason: "Speech framework is not available on this platform")
    }
}

/// Factory that returns a stub provider when Speech framework is unavailable.
public func makeAppleSpeechProvider() -> SpeechProvider {
    return StubSpeechProvider()
}

#endif