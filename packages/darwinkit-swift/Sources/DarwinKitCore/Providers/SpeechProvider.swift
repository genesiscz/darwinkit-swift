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
import AVFoundation
import CoreMedia

/// Factory that returns AppleSpeechProvider if Speech framework is available.
public func makeAppleSpeechProvider() -> SpeechProvider {
    return AppleSpeechProvider()
}

public final class AppleSpeechProvider: SpeechProvider {

    public init() {}

    deinit {}

    // MARK: - Transcribe

    public func transcribe(path: String, language: String, includeTimestamps: Bool) throws -> TranscriptionResult {
        guard FileManager.default.fileExists(atPath: path) else {
            throw JsonRpcError.invalidParams("File not found: \(path)")
        }

        if #available(macOS 26, *) {
            return try transcribeWithSpeechAnalyzer(path: path, language: language, includeTimestamps: includeTimestamps)
        } else {
            return try transcribeWithSFSpeechRecognizer(path: path, language: language, includeTimestamps: includeTimestamps)
        }
    }

    // MARK: - SpeechAnalyzer (macOS 26+)

    @available(macOS 26, *)
    private func transcribeWithSpeechAnalyzer(path: String, language: String, includeTimestamps: Bool) throws -> TranscriptionResult {
        let fileURL = URL(fileURLWithPath: path)
        let locale = Locale(identifier: language)

        // Use timeIndexedTranscriptionWithAlternatives for timestamps, plain transcription otherwise
        let preset: SpeechTranscriber.Preset = includeTimestamps
            ? .timeIndexedTranscriptionWithAlternatives
            : .transcription
        let transcriber = SpeechTranscriber(locale: locale, preset: preset)

        let semaphore = DispatchSemaphore(value: 0)
        var segments: [TranscriptionSegment] = []
        var fullText = ""
        var maxEndTime: Double = 0
        var taskError: Error?

        Task {
            do {
                let audioFile = try AVAudioFile(forReading: fileURL)
                let analyzer = try await SpeechAnalyzer(
                    inputAudioFile: audioFile,
                    modules: [transcriber],
                    finishAfterFile: true
                )

                // Collect results from the transcriber's async sequence
                for try await result in transcriber.results {
                    let text = String(result.text.characters)

                    if result.isFinal {
                        if !fullText.isEmpty { fullText += " " }
                        fullText += text

                        if includeTimestamps {
                            let startSeconds = CMTimeGetSeconds(result.range.start)
                            let durationSeconds = CMTimeGetSeconds(result.range.duration)
                            let endSeconds = startSeconds + durationSeconds

                            segments.append(TranscriptionSegment(
                                text: text,
                                startTime: startSeconds,
                                endTime: endSeconds,
                                isFinal: true
                            ))

                            if endSeconds > maxEndTime {
                                maxEndTime = endSeconds
                            }
                        }
                    }
                }

                // Use audio file duration if we didn't get timestamps
                if maxEndTime == 0 {
                    let fileDuration = Double(audioFile.length) / audioFile.fileFormat.sampleRate
                    maxEndTime = fileDuration
                }

                // Suppress unused variable warning
                _ = analyzer
            } catch {
                taskError = error
            }
            semaphore.signal()
        }

        let timeoutResult = semaphore.wait(timeout: .now() + 300.0)
        if timeoutResult == .timedOut {
            throw JsonRpcError.internalError("Transcription timed out after 300 seconds")
        }
        if let error = taskError {
            throw JsonRpcError.internalError("SpeechAnalyzer failed: \(error.localizedDescription)")
        }

        return TranscriptionResult(
            text: fullText,
            segments: segments,
            language: language,
            duration: maxEndTime
        )
    }

    // MARK: - SFSpeechRecognizer Fallback (macOS < 26)

    private func transcribeWithSFSpeechRecognizer(path: String, language: String, includeTimestamps: Bool) throws -> TranscriptionResult {
        let url = URL(fileURLWithPath: path)
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

    // MARK: - Supported Languages

    public func supportedLanguages() throws -> [SpeechLanguageInfo] {
        if #available(macOS 26, *) {
            return try supportedLanguagesMacOS26()
        } else {
            let supported = SFSpeechRecognizer.supportedLocales()
            return supported.map { locale in
                SpeechLanguageInfo(locale: locale.identifier, installed: true)
            }
        }
    }

    @available(macOS 26, *)
    private func supportedLanguagesMacOS26() throws -> [SpeechLanguageInfo] {
        let semaphore = DispatchSemaphore(value: 0)
        var result: [SpeechLanguageInfo] = []

        Task {
            let supported = await SpeechTranscriber.supportedLocales
            let installed = await SpeechTranscriber.installedLocales
            let installedSet = Set(installed.map { $0.identifier })
            result = supported.map { locale in
                SpeechLanguageInfo(
                    locale: locale.identifier,
                    installed: installedSet.contains(locale.identifier)
                )
            }
            semaphore.signal()
        }

        semaphore.wait()
        return result
    }

    // MARK: - Installed Languages

    public func installedLanguages() throws -> [SpeechLanguageInfo] {
        if #available(macOS 26, *) {
            return try installedLanguagesMacOS26()
        } else {
            // On older macOS, all supported locales are available (no separate download)
            let supported = SFSpeechRecognizer.supportedLocales()
            return supported.map { locale in
                SpeechLanguageInfo(locale: locale.identifier, installed: true)
            }
        }
    }

    @available(macOS 26, *)
    private func installedLanguagesMacOS26() throws -> [SpeechLanguageInfo] {
        let semaphore = DispatchSemaphore(value: 0)
        var result: [SpeechLanguageInfo] = []

        Task {
            let installed = await SpeechTranscriber.installedLocales
            result = installed.map { locale in
                SpeechLanguageInfo(locale: locale.identifier, installed: true)
            }
            semaphore.signal()
        }

        semaphore.wait()
        return result
    }

    // MARK: - Install Language

    public func installLanguage(locale: String) throws {
        if #available(macOS 26, *) {
            try installLanguageWithAssetInventory(locale: locale)
        } else {
            // SFSpeechRecognizer does not support downloading individual language models.
            let supported = SFSpeechRecognizer.supportedLocales()
            let loc = Locale(identifier: locale)
            guard supported.contains(loc) else {
                throw JsonRpcError.invalidParams("Unsupported locale: \(locale)")
            }
            // No-op: language is already installed
        }
    }

    @available(macOS 26, *)
    private func installLanguageWithAssetInventory(locale: String) throws {
        let loc = Locale(identifier: locale)
        let transcriber = SpeechTranscriber(locale: loc, preset: .transcription)

        let semaphore = DispatchSemaphore(value: 0)
        var taskError: Error?

        Task {
            do {
                // Check if already installed
                let status = await AssetInventory.status(forModules: [transcriber])
                if status == .installed {
                    semaphore.signal()
                    return
                }

                guard status != .unsupported else {
                    taskError = JsonRpcError.invalidParams("Unsupported locale: \(locale)")
                    semaphore.signal()
                    return
                }

                // Request installation
                if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                    try await request.downloadAndInstall()
                }
            } catch {
                taskError = error
            }
            semaphore.signal()
        }

        let timeoutResult = semaphore.wait(timeout: .now() + 600.0)
        if timeoutResult == .timedOut {
            throw JsonRpcError.internalError("Language model download timed out after 600 seconds")
        }
        if let error = taskError {
            if let rpcError = error as? JsonRpcError {
                throw rpcError
            }
            throw JsonRpcError.internalError("Failed to install language model: \(error.localizedDescription)")
        }
    }

    // MARK: - Uninstall Language

    public func uninstallLanguage(locale: String) throws {
        if #available(macOS 26, *) {
            try uninstallLanguageWithAssetInventory(locale: locale)
        } else {
            throw JsonRpcError.invalidParams(
                "Language models cannot be uninstalled with the current Speech framework"
            )
        }
    }

    @available(macOS 26, *)
    private func uninstallLanguageWithAssetInventory(locale: String) throws {
        let loc = Locale(identifier: locale)

        let semaphore = DispatchSemaphore(value: 0)
        var released = false

        Task {
            // Release a reserved locale to allow the system to reclaim assets
            released = await AssetInventory.release(reservedLocale: loc)
            semaphore.signal()
        }

        let timeoutResult = semaphore.wait(timeout: .now() + 60.0)
        if timeoutResult == .timedOut {
            throw JsonRpcError.internalError("Language model deallocation timed out")
        }
        if !released {
            throw JsonRpcError.invalidParams(
                "Locale \(locale) is not reserved or cannot be released"
            )
        }
    }

    // MARK: - Capabilities

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
