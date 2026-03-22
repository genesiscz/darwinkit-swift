import Foundation
import Testing
@testable import DarwinKitCore

// MARK: - Mock Provider

struct MockSpeechProvider: SpeechProvider {
    var transcriptionResult = TranscriptionResult(
        text: "Hello world. How are you?",
        segments: [
            TranscriptionSegment(text: "Hello world.", startTime: 0.0, endTime: 1.5, isFinal: true),
            TranscriptionSegment(text: "How are you?", startTime: 1.6, endTime: 3.0, isFinal: true),
        ],
        language: "en-US",
        duration: 3.0
    )
    var languagesResult: [SpeechLanguageInfo] = [
        SpeechLanguageInfo(locale: "en-US", installed: true),
        SpeechLanguageInfo(locale: "es-ES", installed: false),
        SpeechLanguageInfo(locale: "fr-FR", installed: true),
    ]
    var installedResult: [SpeechLanguageInfo] = [
        SpeechLanguageInfo(locale: "en-US", installed: true),
        SpeechLanguageInfo(locale: "fr-FR", installed: true),
    ]
    var capabilitiesResult = SpeechCapabilities(available: true)
    var shouldThrow: JsonRpcError? = nil

    func transcribe(path: String, language: String, includeTimestamps: Bool) throws -> TranscriptionResult {
        if let err = shouldThrow { throw err }
        if path.contains("nonexistent") {
            throw JsonRpcError.invalidParams("File not found: \(path)")
        }
        if includeTimestamps {
            return transcriptionResult
        }
        // Without timestamps, return segments without timing
        return TranscriptionResult(
            text: transcriptionResult.text,
            segments: [],
            language: transcriptionResult.language,
            duration: transcriptionResult.duration
        )
    }

    func supportedLanguages() throws -> [SpeechLanguageInfo] {
        if let err = shouldThrow { throw err }
        return languagesResult
    }

    func installedLanguages() throws -> [SpeechLanguageInfo] {
        if let err = shouldThrow { throw err }
        return installedResult
    }

    func installLanguage(locale: String) throws {
        if let err = shouldThrow { throw err }
    }

    func uninstallLanguage(locale: String) throws {
        if let err = shouldThrow { throw err }
    }

    func capabilities() throws -> SpeechCapabilities {
        if let err = shouldThrow { throw err }
        return capabilitiesResult
    }
}

// MARK: - Helper

private func makeRequest(method: String, params: [String: Any] = [:]) -> JsonRpcRequest {
    let codableParams = params.mapValues { AnyCodable($0) }
    return JsonRpcRequest(id: "test", method: method, params: codableParams)
}

// MARK: - Tests

@Suite("Speech Handler")
struct SpeechHandlerTests {

    // MARK: - speech.transcribe

    @Test("transcribe returns text and segments")
    func transcribeSuccess() throws {
        let handler = SpeechHandler(provider: MockSpeechProvider())
        let request = makeRequest(method: "speech.transcribe", params: [
            "path": "/tmp/audio.m4a", "language": "en-US"
        ])
        let result = try handler.handle(request) as! [String: Any]

        #expect(result["text"] as? String == "Hello world. How are you?")
        let segments = result["segments"] as! [[String: Any]]
        #expect(segments.count == 2)
        #expect(result["language"] as? String == "en-US")
        #expect(result["duration"] as? Double == 3.0)
    }

    @Test("transcribe segments contain timing info")
    func transcribeSegmentFields() throws {
        let handler = SpeechHandler(provider: MockSpeechProvider())
        let request = makeRequest(method: "speech.transcribe", params: [
            "path": "/tmp/audio.m4a", "language": "en-US"
        ])
        let result = try handler.handle(request) as! [String: Any]
        let segments = result["segments"] as! [[String: Any]]

        let first = segments[0]
        #expect(first["text"] as? String == "Hello world.")
        #expect(first["start_time"] as? Double == 0.0)
        #expect(first["end_time"] as? Double == 1.5)
        #expect(first["is_final"] as? Bool == true)
    }

    @Test("transcribe throws on missing path")
    func transcribeMissingPath() {
        let handler = SpeechHandler(provider: MockSpeechProvider())
        let request = makeRequest(method: "speech.transcribe", params: [
            "language": "en-US"
        ])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    @Test("transcribe defaults language to en-US")
    func transcribeDefaultLanguage() throws {
        let handler = SpeechHandler(provider: MockSpeechProvider())
        let request = makeRequest(method: "speech.transcribe", params: [
            "path": "/tmp/audio.m4a"
        ])
        let result = try handler.handle(request) as! [String: Any]
        #expect(result["text"] != nil)
    }

    @Test("transcribe defaults timestamps to true")
    func transcribeDefaultTimestamps() throws {
        let handler = SpeechHandler(provider: MockSpeechProvider())
        let request = makeRequest(method: "speech.transcribe", params: [
            "path": "/tmp/audio.m4a", "language": "en-US"
        ])
        let result = try handler.handle(request) as! [String: Any]
        let segments = result["segments"] as! [[String: Any]]
        #expect(segments.count == 2) // timestamps included by default
    }

    @Test("transcribe without timestamps returns empty segments")
    func transcribeNoTimestamps() throws {
        let handler = SpeechHandler(provider: MockSpeechProvider())
        let request = makeRequest(method: "speech.transcribe", params: [
            "path": "/tmp/audio.m4a", "language": "en-US", "timestamps": false
        ])
        let result = try handler.handle(request) as! [String: Any]
        let segments = result["segments"] as! [[String: Any]]
        #expect(segments.isEmpty)
    }

    @Test("transcribe throws on file not found")
    func transcribeFileNotFound() {
        let handler = SpeechHandler(provider: MockSpeechProvider())
        let request = makeRequest(method: "speech.transcribe", params: [
            "path": "/tmp/nonexistent.m4a", "language": "en-US"
        ])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    // MARK: - speech.languages

    @Test("languages returns all supported locales")
    func languagesSuccess() throws {
        let handler = SpeechHandler(provider: MockSpeechProvider())
        let request = makeRequest(method: "speech.languages")
        let result = try handler.handle(request) as! [String: Any]
        let languages = result["languages"] as! [[String: Any]]

        #expect(languages.count == 3)
        #expect(languages[0]["locale"] as? String == "en-US")
    }

    // MARK: - speech.installed_languages

    @Test("installed_languages returns only installed locales")
    func installedLanguagesSuccess() throws {
        let handler = SpeechHandler(provider: MockSpeechProvider())
        let request = makeRequest(method: "speech.installed_languages")
        let result = try handler.handle(request) as! [String: Any]
        let languages = result["languages"] as! [[String: Any]]

        #expect(languages.count == 2)
        #expect(languages[0]["locale"] as? String == "en-US")
        #expect(languages[1]["locale"] as? String == "fr-FR")
    }

    // MARK: - speech.install_language

    @Test("install_language succeeds")
    func installLanguageSuccess() throws {
        let handler = SpeechHandler(provider: MockSpeechProvider())
        let request = makeRequest(method: "speech.install_language", params: [
            "locale": "es-ES"
        ])
        let result = try handler.handle(request) as! [String: Any]
        #expect(result["ok"] as? Bool == true)
    }

    @Test("install_language throws on missing locale")
    func installLanguageMissingLocale() {
        let handler = SpeechHandler(provider: MockSpeechProvider())
        let request = makeRequest(method: "speech.install_language", params: [:])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    // MARK: - speech.uninstall_language

    @Test("uninstall_language succeeds")
    func uninstallLanguageSuccess() throws {
        let handler = SpeechHandler(provider: MockSpeechProvider())
        let request = makeRequest(method: "speech.uninstall_language", params: [
            "locale": "fr-FR"
        ])
        let result = try handler.handle(request) as! [String: Any]
        #expect(result["ok"] as? Bool == true)
    }

    @Test("uninstall_language throws on missing locale")
    func uninstallLanguageMissingLocale() {
        let handler = SpeechHandler(provider: MockSpeechProvider())
        let request = makeRequest(method: "speech.uninstall_language", params: [:])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    // MARK: - speech.capabilities

    @Test("capabilities returns availability info")
    func capabilitiesSuccess() throws {
        let handler = SpeechHandler(provider: MockSpeechProvider())
        let request = makeRequest(method: "speech.capabilities")
        let result = try handler.handle(request) as! [String: Any]

        #expect(result["available"] as? Bool == true)
    }

    @Test("capabilities returns reason when unavailable")
    func capabilitiesUnavailable() throws {
        var mock = MockSpeechProvider()
        mock.capabilitiesResult = SpeechCapabilities(available: false, reason: "Requires macOS 26+")
        let handler = SpeechHandler(provider: mock)
        let request = makeRequest(method: "speech.capabilities")
        let result = try handler.handle(request) as! [String: Any]

        #expect(result["available"] as? Bool == false)
        #expect(result["reason"] as? String == "Requires macOS 26+")
    }

    // MARK: - Method registration

    @Test("handler registers all 6 speech methods")
    func methodRegistration() {
        let handler = SpeechHandler(provider: MockSpeechProvider())
        let expected: Set<String> = [
            "speech.transcribe", "speech.languages", "speech.installed_languages",
            "speech.install_language", "speech.uninstall_language", "speech.capabilities"
        ]
        #expect(Set(handler.methods) == expected)
    }

    @Test("handler reports capabilities for all methods")
    func handlerCapabilities() {
        let handler = SpeechHandler(provider: MockSpeechProvider())
        for method in handler.methods {
            let cap = handler.capability(for: method)
            #expect(cap.available == true)
        }
    }

    // MARK: - Unknown method dispatch

    @Test("handler throws on unknown method via router")
    func unknownMethod() {
        let router = MethodRouter()
        router.register(SpeechHandler(provider: MockSpeechProvider()))
        let request = makeRequest(method: "speech.nonexistent")

        #expect(throws: JsonRpcError.self) {
            try router.dispatch(request)
        }
    }

    // MARK: - Provider error propagation

    @Test("provider errors propagate through handler")
    func providerError() {
        var mock = MockSpeechProvider()
        mock.shouldThrow = .frameworkUnavailable("SpeechAnalyzer not available")
        let handler = SpeechHandler(provider: mock)
        let request = makeRequest(method: "speech.transcribe", params: [
            "path": "/tmp/audio.m4a", "language": "en-US"
        ])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }
}
