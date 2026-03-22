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
