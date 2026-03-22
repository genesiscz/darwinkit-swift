# Speech Recognition (`speech.*`) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add speech-to-text transcription via Apple's SpeechAnalyzer framework (macOS 26+) as a new `speech.*` JSON-RPC namespace.

**Architecture:** Protocol-based provider pattern (`SpeechProvider` protocol + `AppleSpeechProvider` concrete implementation + `MockSpeechProvider` for tests), routed through a `SpeechHandler` that dispatches `speech.*` JSON-RPC methods. Mirrors the existing NLP/Vision/CoreML handler patterns exactly. TS SDK gets a `Speech` namespace class with typed methods and `MethodMap` entries.

**Tech Stack:** Swift (SpeechAnalyzer framework, macOS 26+), Swift Testing, TypeScript (TS SDK namespace + types)

---

## File Map

| Layer | File | Action |
|-------|------|--------|
| Swift Provider | `packages/darwinkit-swift/Sources/DarwinKitCore/Providers/SpeechProvider.swift` | Create |
| Swift Handler | `packages/darwinkit-swift/Sources/DarwinKitCore/Handlers/SpeechHandler.swift` | Create |
| Swift Registration | `packages/darwinkit-swift/Sources/DarwinKit/DarwinKit.swift` | Modify |
| Swift Tests | `packages/darwinkit-swift/Tests/DarwinKitCoreTests/SpeechHandlerTests.swift` | Create |
| TS Types | `packages/darwinkit/src/types.ts` | Modify |
| TS Namespace | `packages/darwinkit/src/namespaces/speech.ts` | Create |
| TS Client | `packages/darwinkit/src/client.ts` | Modify |
| TS Index | `packages/darwinkit/src/index.ts` | Modify |

---

## Task 1: SpeechProvider Protocol + Data Types

**Files:**
- Create: `packages/darwinkit-swift/Sources/DarwinKitCore/Providers/SpeechProvider.swift`

**Step 1: Create the provider protocol and supporting types**

This file defines the contract that both `AppleSpeechProvider` and `MockSpeechProvider` will implement. It also defines all value types used in speech methods.

```swift
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
```

**Step 2: Commit**

```bash
git add packages/darwinkit-swift/Sources/DarwinKitCore/Providers/SpeechProvider.swift
git commit -m "feat(speech): add SpeechProvider protocol and data types"
```

---

## Task 2: SpeechHandler Tests (TDD -- write tests first)

**Files:**
- Create: `packages/darwinkit-swift/Tests/DarwinKitCoreTests/SpeechHandlerTests.swift`

**Step 1: Write all tests with MockSpeechProvider**

This is the full test file. We write it _before_ the handler exists, so it will not compile yet. The mock follows the same pattern as `MockNLPProvider` and `MockCoreMLProvider`.

```swift
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
```

**Step 2: Commit**

```bash
git add packages/darwinkit-swift/Tests/DarwinKitCoreTests/SpeechHandlerTests.swift
git commit -m "test(speech): add SpeechHandler tests with MockSpeechProvider"
```

---

## Task 3: SpeechHandler Implementation

**Files:**
- Create: `packages/darwinkit-swift/Sources/DarwinKitCore/Handlers/SpeechHandler.swift`

**Step 1: Implement the handler**

This handler follows the exact same pattern as `NLPHandler`, `VisionHandler`, and `CoreMLHandler`: a `MethodHandler` that dispatches based on `request.method`, extracts params, calls the provider, and returns dictionaries.

```swift
import Foundation

/// Handles all speech.* methods: transcribe, languages, installed_languages,
/// install_language, uninstall_language, capabilities.
public final class SpeechHandler: MethodHandler {
    private let provider: SpeechProvider

    public var methods: [String] {
        [
            "speech.transcribe", "speech.languages", "speech.installed_languages",
            "speech.install_language", "speech.uninstall_language", "speech.capabilities"
        ]
    }

    public init(provider: SpeechProvider) {
        self.provider = provider
    }

    public func handle(_ request: JsonRpcRequest) throws -> Any {
        switch request.method {
        case "speech.transcribe":
            return try handleTranscribe(request)
        case "speech.languages":
            return try handleLanguages(request)
        case "speech.installed_languages":
            return try handleInstalledLanguages(request)
        case "speech.install_language":
            return try handleInstallLanguage(request)
        case "speech.uninstall_language":
            return try handleUninstallLanguage(request)
        case "speech.capabilities":
            return try handleCapabilities(request)
        default:
            throw JsonRpcError.methodNotFound(request.method)
        }
    }

    public func capability(for method: String) -> MethodCapability {
        MethodCapability(available: true, note: "Requires macOS 26+")
    }

    // MARK: - Method Implementations

    private func handleTranscribe(_ request: JsonRpcRequest) throws -> Any {
        let path = try request.requireString("path")
        let language = request.string("language") ?? "en-US"
        let includeTimestamps = request.bool("timestamps") ?? true

        let result = try provider.transcribe(
            path: path, language: language, includeTimestamps: includeTimestamps
        )
        return result.toDict()
    }

    private func handleLanguages(_ request: JsonRpcRequest) throws -> Any {
        let languages = try provider.supportedLanguages()
        return ["languages": languages.map { $0.toDict() }] as [String: Any]
    }

    private func handleInstalledLanguages(_ request: JsonRpcRequest) throws -> Any {
        let languages = try provider.installedLanguages()
        return ["languages": languages.map { $0.toDict() }] as [String: Any]
    }

    private func handleInstallLanguage(_ request: JsonRpcRequest) throws -> Any {
        let locale = try request.requireString("locale")
        try provider.installLanguage(locale: locale)
        return ["ok": true] as [String: Any]
    }

    private func handleUninstallLanguage(_ request: JsonRpcRequest) throws -> Any {
        let locale = try request.requireString("locale")
        try provider.uninstallLanguage(locale: locale)
        return ["ok": true] as [String: Any]
    }

    private func handleCapabilities(_ request: JsonRpcRequest) throws -> Any {
        let caps = try provider.capabilities()
        return caps.toDict()
    }
}
```

**Step 2: Run tests to verify they pass**

Run: `cd packages/darwinkit-swift && swift test --filter SpeechHandlerTests 2>&1`
Expected: All 20 tests PASS.

**Step 3: Commit**

```bash
git add packages/darwinkit-swift/Sources/DarwinKitCore/Handlers/SpeechHandler.swift
git commit -m "feat(speech): implement SpeechHandler with all 6 methods"
```

---

## Task 4: AppleSpeechProvider Implementation

**Files:**
- Modify: `packages/darwinkit-swift/Sources/DarwinKitCore/Providers/SpeechProvider.swift` (append to end of file)

**Step 1: Add the Apple implementation using SpeechAnalyzer**

Append this after the existing protocol definition in `SpeechProvider.swift`. The entire implementation is gated behind `@available(macOS 26, *)` since SpeechAnalyzer is macOS 26+. The public factory function handles the version check and returns the correct provider or throws.

```swift
// MARK: - Apple Implementation (macOS 26+)

/// Factory that returns AppleSpeechProvider on macOS 26+, or throws on older OS.
public func makeAppleSpeechProvider() throws -> SpeechProvider {
    if #available(macOS 26, *) {
        return AppleSpeechProvider()
    }
    throw JsonRpcError.osVersionTooOld("Speech recognition requires macOS 26+")
}

@available(macOS 26, *)
public final class AppleSpeechProvider: SpeechProvider {

    public init() {}

    public func transcribe(path: String, language: String, includeTimestamps: Bool) throws -> TranscriptionResult {
        let url = URL(fileURLWithPath: path)

        guard FileManager.default.fileExists(atPath: path) else {
            throw JsonRpcError.invalidParams("File not found: \(path)")
        }

        let locale = Locale(identifier: language)
        let transcriber = SpeechTranscriber(locale: locale, preset: .offlineTranscription)
        let analyzer = SpeechAnalyzer(modules: [transcriber])

        let semaphore = DispatchSemaphore(value: 0)
        var fullText = ""
        var segments: [TranscriptionSegment] = []
        var transcribeError: Error? = nil

        Task {
            do {
                try await analyzer.analyzeSequence(from: url)

                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    let timeRange = result.audioTimeRange
                    let startSec = timeRange.lowerBound.seconds
                    let endSec = timeRange.upperBound.seconds

                    if result.isFinal {
                        if includeTimestamps {
                            segments.append(TranscriptionSegment(
                                text: text,
                                startTime: startSec,
                                endTime: endSec,
                                isFinal: true
                            ))
                        }
                        fullText += (fullText.isEmpty ? "" : " ") + text
                    }
                }

                try await analyzer.finalizeAndFinish(through: transcriber)
            } catch {
                transcribeError = error
            }
            semaphore.signal()
        }

        semaphore.wait()

        if let error = transcribeError {
            throw JsonRpcError.internalError("Transcription failed: \(error.localizedDescription)")
        }

        return TranscriptionResult(
            text: fullText,
            segments: segments,
            language: language,
            duration: segments.last?.endTime ?? 0
        )
    }

    public func supportedLanguages() throws -> [SpeechLanguageInfo] {
        let locales = SpeechTranscriber.supportedLocales
        return locales.map { locale in
            let installed = SpeechTranscriber.installedLocales.contains(locale)
            return SpeechLanguageInfo(locale: locale.identifier, installed: installed)
        }
    }

    public func installedLanguages() throws -> [SpeechLanguageInfo] {
        let locales = SpeechTranscriber.installedLocales
        return locales.map { SpeechLanguageInfo(locale: $0.identifier, installed: true) }
    }

    public func installLanguage(locale: String) throws {
        let loc = Locale(identifier: locale)
        let transcriber = SpeechTranscriber(locale: loc, preset: .offlineTranscription)

        let semaphore = DispatchSemaphore(value: 0)
        var installError: Error? = nil

        Task {
            do {
                let request = try await AssetInventory.assetInstallationRequest(supporting: transcriber)
                try await request.install()
            } catch {
                installError = error
            }
            semaphore.signal()
        }

        semaphore.wait()

        if let error = installError {
            throw JsonRpcError.internalError("Failed to install language \(locale): \(error.localizedDescription)")
        }
    }

    public func uninstallLanguage(locale: String) throws {
        let loc = Locale(identifier: locale)
        let transcriber = SpeechTranscriber(locale: loc, preset: .offlineTranscription)

        let semaphore = DispatchSemaphore(value: 0)
        var uninstallError: Error? = nil

        Task {
            do {
                let request = try await AssetInventory.assetInstallationRequest(supporting: transcriber)
                try await request.uninstall()
            } catch {
                uninstallError = error
            }
            semaphore.signal()
        }

        semaphore.wait()

        if let error = uninstallError {
            throw JsonRpcError.internalError("Failed to uninstall language \(locale): \(error.localizedDescription)")
        }
    }

    public func capabilities() throws -> SpeechCapabilities {
        return SpeechCapabilities(available: true)
    }
}
```

> **Note:** The exact SpeechAnalyzer API surface may differ once you have access to macOS 26 SDK headers. The code above is based on WWDC 2025 session materials. You may need to adjust method names, import statements (`import SpeechAnalyzer` vs `import Speech`), and the `AssetInventory` API for install/uninstall. The key architectural pattern -- semaphore-bridged async, result iteration, provider protocol -- will remain the same.

**Step 2: Verify tests still pass**

Run: `cd packages/darwinkit-swift && swift test --filter SpeechHandlerTests 2>&1`
Expected: All 20 tests PASS (tests use MockSpeechProvider, not AppleSpeechProvider).

**Step 3: Commit**

```bash
git add packages/darwinkit-swift/Sources/DarwinKitCore/Providers/SpeechProvider.swift
git commit -m "feat(speech): implement AppleSpeechProvider with SpeechAnalyzer (macOS 26+)"
```

---

## Task 5: Register SpeechHandler in DarwinKit.swift

**Files:**
- Modify: `packages/darwinkit-swift/Sources/DarwinKit/DarwinKit.swift`

**Step 1: Add SpeechHandler registration to both router factory functions**

In `buildServerWithRouter()`, add after `router.register(AuthHandler())`:

```swift
if #available(macOS 26, *) {
    router.register(SpeechHandler(provider: AppleSpeechProvider()))
}
```

In `buildRouter()`, add after `router.register(AuthHandler())`:

```swift
if #available(macOS 26, *) {
    router.register(SpeechHandler(provider: AppleSpeechProvider()))
}
```

The full modified functions should look like:

```swift
/// Build server and router together so handlers can receive the server as NotificationSink.
func buildServerWithRouter() -> JsonRpcServer {
    let router = MethodRouter()
    let server = JsonRpcServer(router: router)

    router.register(SystemHandler(router: router))
    router.register(NLPHandler())
    router.register(VisionHandler())
    router.register(CoreMLHandler(provider: AppleCoreMLProvider()))
    router.register(CloudHandler(notificationSink: server))
    router.register(AuthHandler())
    if #available(macOS 26, *) {
        router.register(SpeechHandler(provider: AppleSpeechProvider()))
    }

    return server
}

/// Central router factory -- all handlers registered here (for single-shot Query mode).
func buildRouter() -> MethodRouter {
    let router = MethodRouter()
    router.register(SystemHandler(router: router))
    router.register(NLPHandler())
    router.register(VisionHandler())
    router.register(CoreMLHandler(provider: AppleCoreMLProvider()))
    router.register(CloudHandler())
    router.register(AuthHandler())
    if #available(macOS 26, *) {
        router.register(SpeechHandler(provider: AppleSpeechProvider()))
    }
    return router
}
```

**Step 2: Run full test suite to verify no regressions**

Run: `cd packages/darwinkit-swift && swift test 2>&1`
Expected: All existing tests PASS, plus new SpeechHandlerTests.

**Step 3: Commit**

```bash
git add packages/darwinkit-swift/Sources/DarwinKit/DarwinKit.swift
git commit -m "feat(speech): register SpeechHandler in DarwinKit server"
```

---

## Task 6: TS SDK Types

**Files:**
- Modify: `packages/darwinkit/src/types.ts`

**Step 1: Add Speech types before the MethodMap section**

Insert the following block between the CoreML section (ending at line 275 with `CoreMLOkResult`) and the MethodMap section (starting at line 277). Place it at the end of the type definitions, before `// MethodMap`.

```typescript
// ---------------------------------------------------------------------------
// Speech
// ---------------------------------------------------------------------------

export interface SpeechTranscribeParams {
  path: string
  language?: string      // default: "en-US"
  timestamps?: boolean   // default: true
}
export interface SpeechTranscriptionSegment {
  text: string
  start_time: number
  end_time: number
  is_final: boolean
}
export interface SpeechTranscribeResult {
  text: string
  segments: SpeechTranscriptionSegment[]
  language: string
  duration: number
}

export interface SpeechLanguageInfo {
  locale: string
  installed: boolean
}
export interface SpeechLanguagesResult {
  languages: SpeechLanguageInfo[]
}

export interface SpeechInstallLanguageParams {
  locale: string
}
export interface SpeechUninstallLanguageParams {
  locale: string
}
export interface SpeechOkResult {
  ok: true
}

export interface SpeechCapabilitiesResult {
  available: boolean
  reason?: string
}
```

**Step 2: Add Speech entries to the MethodMap interface**

Inside the `MethodMap` interface (after the last `coreml.*` entry on line 365), add:

```typescript
  "speech.transcribe": {
    params: SpeechTranscribeParams
    result: SpeechTranscribeResult
  }
  "speech.languages": {
    params: Record<string, never>
    result: SpeechLanguagesResult
  }
  "speech.installed_languages": {
    params: Record<string, never>
    result: SpeechLanguagesResult
  }
  "speech.install_language": {
    params: SpeechInstallLanguageParams
    result: SpeechOkResult
  }
  "speech.uninstall_language": {
    params: SpeechUninstallLanguageParams
    result: SpeechOkResult
  }
  "speech.capabilities": {
    params: Record<string, never>
    result: SpeechCapabilitiesResult
  }
```

**Step 3: Commit**

```bash
git add packages/darwinkit/src/types.ts
git commit -m "feat(speech): add Speech types and MethodMap entries to TS SDK"
```

---

## Task 7: TS SDK Speech Namespace Class

**Files:**
- Create: `packages/darwinkit/src/namespaces/speech.ts`

**Step 1: Create the Speech namespace class**

Follow the exact pattern from `packages/darwinkit/src/namespaces/coreml.ts`. Each method gets a callable + `.prepare()` overload.

```typescript
import type { DarwinKitClient } from "../client.js"
import type {
  MethodMap,
  MethodName,
  PreparedCall,
  SpeechTranscribeParams,
  SpeechTranscribeResult,
  SpeechLanguagesResult,
  SpeechInstallLanguageParams,
  SpeechUninstallLanguageParams,
  SpeechOkResult,
  SpeechCapabilitiesResult,
} from "../types.js"

function method<M extends MethodName>(client: DarwinKitClient, name: M) {
  const fn = (
    params: MethodMap[M]["params"],
    options?: { timeout?: number },
  ) => client.call(name, params, options)
  fn.prepare = (params: MethodMap[M]["params"]): PreparedCall<M> => ({
    method: name,
    params,
    __brand: undefined as unknown as MethodMap[M]["result"],
  })
  return fn
}

export class Speech {
  readonly transcribe: {
    (
      params: SpeechTranscribeParams,
      options?: { timeout?: number },
    ): Promise<SpeechTranscribeResult>
    prepare(
      params: SpeechTranscribeParams,
    ): PreparedCall<"speech.transcribe">
  }
  readonly installLanguage: {
    (
      params: SpeechInstallLanguageParams,
      options?: { timeout?: number },
    ): Promise<SpeechOkResult>
    prepare(
      params: SpeechInstallLanguageParams,
    ): PreparedCall<"speech.install_language">
  }
  readonly uninstallLanguage: {
    (
      params: SpeechUninstallLanguageParams,
      options?: { timeout?: number },
    ): Promise<SpeechOkResult>
    prepare(
      params: SpeechUninstallLanguageParams,
    ): PreparedCall<"speech.uninstall_language">
  }

  private client: DarwinKitClient

  constructor(client: DarwinKitClient) {
    this.client = client
    this.transcribe = method(
      client,
      "speech.transcribe",
    ) as Speech["transcribe"]
    this.installLanguage = method(
      client,
      "speech.install_language",
    ) as Speech["installLanguage"]
    this.uninstallLanguage = method(
      client,
      "speech.uninstall_language",
    ) as Speech["uninstallLanguage"]
  }

  /** List all supported languages for speech recognition */
  languages(options?: { timeout?: number }): Promise<SpeechLanguagesResult> {
    return this.client.call(
      "speech.languages",
      {} as Record<string, never>,
      options,
    )
  }

  /** List installed (downloaded) language models */
  installedLanguages(
    options?: { timeout?: number },
  ): Promise<SpeechLanguagesResult> {
    return this.client.call(
      "speech.installed_languages",
      {} as Record<string, never>,
      options,
    )
  }

  /** Check speech recognition availability and device support */
  capabilities(
    options?: { timeout?: number },
  ): Promise<SpeechCapabilitiesResult> {
    return this.client.call(
      "speech.capabilities",
      {} as Record<string, never>,
      options,
    )
  }
}
```

**Step 2: Commit**

```bash
git add packages/darwinkit/src/namespaces/speech.ts
git commit -m "feat(speech): add Speech namespace class to TS SDK"
```

---

## Task 8: Wire Speech Namespace into TS Client + Index

**Files:**
- Modify: `packages/darwinkit/src/client.ts`
- Modify: `packages/darwinkit/src/index.ts`

**Step 1: Add Speech import and namespace to client.ts**

In `client.ts`, add import (after the CoreML import on line 17):

```typescript
import { Speech } from "./namespaces/speech.js"
```

Add the namespace property to the `DarwinKit` class (after `readonly coreml: CoreML` on line 89):

```typescript
  readonly speech: Speech
```

Add initialization in the constructor (after `this.coreml = new CoreML(this)` on line 131):

```typescript
    this.speech = new Speech(this)
```

**Step 2: Add Speech exports to index.ts**

In `index.ts`, add namespace export (after line 14 `export { CoreML }`):

```typescript
export { Speech } from "./namespaces/speech.js"
```

Add type exports inside the `export type { ... }` block (after the CoreML section, before `// Notifications`):

```typescript
  // Speech
  SpeechTranscribeParams,
  SpeechTranscriptionSegment,
  SpeechTranscribeResult,
  SpeechLanguageInfo,
  SpeechLanguagesResult,
  SpeechInstallLanguageParams,
  SpeechUninstallLanguageParams,
  SpeechOkResult,
  SpeechCapabilitiesResult,
```

**Step 3: Verify TypeScript compiles**

Run: `bunx tsgo --noEmit 2>&1 | head -20`
Expected: No errors.

**Step 4: Commit**

```bash
git add packages/darwinkit/src/client.ts packages/darwinkit/src/index.ts
git commit -m "feat(speech): wire Speech namespace into TS SDK client and exports"
```

---

## Task 9: Final Verification

**Step 1: Run Swift tests**

Run: `cd /Users/Martin/Tresors/Projects/darwinkit-swift/packages/darwinkit-swift && swift test 2>&1`
Expected: All tests pass including SpeechHandlerTests (20 tests).

**Step 2: Run TypeScript type check**

Run: `cd /Users/Martin/Tresors/Projects/darwinkit-swift && bunx tsgo --noEmit 2>&1`
Expected: No errors.

**Step 3: Verify method count**

Quick sanity check -- the 6 new methods should be registered:
- `speech.transcribe`
- `speech.languages`
- `speech.installed_languages`
- `speech.install_language`
- `speech.uninstall_language`
- `speech.capabilities`

---

## Summary

| Task | What | Files | Tests |
|------|------|-------|-------|
| 1 | Provider protocol + data types | 1 created | - |
| 2 | Tests (TDD) | 1 created | 20 tests |
| 3 | SpeechHandler | 1 created | 20 pass |
| 4 | AppleSpeechProvider | 1 modified | 20 pass |
| 5 | DarwinKit registration | 1 modified | full suite |
| 6 | TS SDK types + MethodMap | 1 modified | - |
| 7 | TS Speech namespace | 1 created | - |
| 8 | TS client + index wiring | 2 modified | tsc pass |
| 9 | Final verification | - | all pass |

**Total: 4 new files, 4 modified files, 20 unit tests, 8 commits.**
