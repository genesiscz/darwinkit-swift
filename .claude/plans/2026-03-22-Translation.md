# Translation Framework Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add on-device text translation to DarwinKit via Apple's Translation framework (macOS 14.4+ / iOS 17.4+), exposing 5 JSON-RPC methods: `translate.text`, `translate.batch`, `translate.languages`, `translate.language_status`, and `translate.prepare`.

**Architecture:** New `translate.*` JSON-RPC namespace following the existing provider+handler pattern (like CoreML). `TranslationProvider` protocol with `AppleTranslationProvider` (real) and `MockTranslationProvider` (tests). `TranslationHandler` routes JSON-RPC to the provider. TypeScript SDK gets a `Translate` namespace class with full types and MethodMap entries.

**Tech Stack:** Swift 5.9 + Translation framework (macOS 14.4+) | TypeScript + @genesiscz/darwinkit SDK

---

## Reference Material

Before starting any task, read these files to understand patterns:

| What | File |
|------|------|
| Provider pattern | `packages/darwinkit-swift/Sources/DarwinKitCore/Providers/CoreMLProvider.swift` |
| Handler pattern | `packages/darwinkit-swift/Sources/DarwinKitCore/Handlers/CoreMLHandler.swift` |
| Registration | `packages/darwinkit-swift/Sources/DarwinKit/DarwinKit.swift` |
| Test pattern (mock) | `packages/darwinkit-swift/Tests/DarwinKitCoreTests/CoreMLHandlerTests.swift` |
| JSON-RPC protocol | `packages/darwinkit-swift/Sources/DarwinKitCore/Server/Protocol.swift` |
| MethodHandler protocol | `packages/darwinkit-swift/Sources/DarwinKitCore/Server/MethodRouter.swift` |
| TS types + MethodMap | `packages/darwinkit/src/types.ts` |
| TS namespace pattern | `packages/darwinkit/src/namespaces/coreml.ts` |
| TS client wiring | `packages/darwinkit/src/client.ts` |
| TS barrel export | `packages/darwinkit/src/index.ts` |

---

## Architecture Diagram

```
┌──────────────────────────────────────────────────────────┐
│ TypeScript SDK (packages/darwinkit)                       │
│                                                          │
│  Translate namespace class                               │
│    .text(params)          → "translate.text"             │
│    .batch(params)         → "translate.batch"            │
│    .languages()           → "translate.languages"        │
│    .languageStatus(params)→ "translate.language_status"  │
│    .prepare(params)       → "translate.prepare"          │
└──────────────────┬───────────────────────────────────────┘
                   │ JSON-RPC over stdin/stdout
┌──────────────────▼───────────────────────────────────────┐
│ DarwinKit Swift Binary                                    │
│                                                          │
│  TranslationHandler ──→ TranslationProvider protocol     │
│                          ├── AppleTranslationProvider     │
│                          │    ├── LanguageAvailability    │
│                          │    ├── TranslationSession      │
│                          │    └── Locale.Language          │
│                          └── MockTranslationProvider      │
└──────────────────────────────────────────────────────────┘
```

---

## Translation Framework: CLI Usage Notes

**Critical constraint:** Apple's `TranslationSession` is primarily designed for SwiftUI (`.translationTask` modifier). However, since macOS 14.4+ / iOS 17.4+, `TranslationSession` can be created programmatically:

```swift
let config = TranslationSession.Configuration(
    source: Locale.Language(identifier: "en"),
    target: Locale.Language(identifier: "es")
)
let session = TranslationSession(configuration: config)
```

The `TranslationSession` methods are `async`, so we need to bridge from the synchronous handler world using `DispatchSemaphore` + `Task { }` (same pattern used in `AppleCoreMLProvider.loadEmbeddingBundle`).

**`LanguageAvailability`** is straightforward and does not require SwiftUI.

**Availability:** The `Translation` framework module itself requires `macOS 14.4` (not 14.0). The `Package.swift` already has `.macOS(.v14)` as platform minimum, which is fine since we'll use `@available(macOS 14.4, *)` guards on the implementation and the handler will report availability accordingly.

---

## Threading Model

The DarwinKit server dispatches synchronously on a background thread. Translation framework methods are `async`. Bridge pattern:

```swift
let semaphore = DispatchSemaphore(value: 0)
var result: TranslationSession.Response?
var error: Error?

Task {
    do {
        result = try await session.translate(text)
    } catch {
        error = err
    }
    semaphore.signal()
}
semaphore.wait()
```

This is the same pattern used in `AppleCoreMLProvider` for `loadEmbeddingBundle` and `embedWithBundleImpl`.

---

## Error Handling

| Error Case | Swift Error | JSON-RPC Code |
|-----------|-------------|---------------|
| Translation framework unavailable (< macOS 14.4) | `.osVersionTooOld("Translation requires macOS 14.4+")` | -32003 |
| Empty text | `.invalidParams("text must not be empty")` | -32602 |
| Missing required param | `.invalidParams("Missing required param: ...")` | -32602 |
| Empty batch | `.invalidParams("texts must be a non-empty array of strings")` | -32602 |
| Unsupported language pair | `.invalidParams("Unsupported language pair: ...")` | -32602 |
| Translation failed | `.internalError("Translation failed: ...")` | -32603 |
| Model download failed | `.internalError("Failed to prepare translation models: ...")` | -32603 |

---

## JSON-RPC Method Specifications

### `translate.text`
```json
// Request params
{ "text": "Hello world", "source": "en", "target": "es" }
// source is optional (null = auto-detect)

// Response
{ "text": "Hola mundo", "source": "en", "target": "es" }
```

### `translate.batch`
```json
// Request params
{ "texts": ["Hello", "Goodbye"], "source": "en", "target": "es" }
// source is optional (null = auto-detect)

// Response
{ "translations": [
    { "text": "Hola", "source": "en", "target": "es" },
    { "text": "Adios", "source": "en", "target": "es" }
  ]
}
```

### `translate.languages`
```json
// Request params (none)
{}

// Response
{ "languages": [
    { "locale": "en", "name": "English" },
    { "locale": "es", "name": "Spanish" }
  ]
}
```

### `translate.language_status`
```json
// Request params
{ "source": "en", "target": "es" }

// Response
{ "status": "installed", "source": "en", "target": "es" }
// status: "installed" | "supported" | "unsupported"
```

### `translate.prepare`
```json
// Request params
{ "source": "en", "target": "es" }

// Response
{ "ok": true, "source": "en", "target": "es" }
```

---

## Task 1: Swift -- TranslationProvider Protocol + Types

**Files:**
- Create: `packages/darwinkit-swift/Sources/DarwinKitCore/Providers/TranslationProvider.swift`

**Step 1: Write the provider protocol and supporting types**

```swift
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
```

**Step 2: Verify it compiles**

Run:
```bash
cd packages/darwinkit-swift && swift build 2>&1 | head -20
```
Expected: BUILD SUCCEEDED (no references to TranslationProvider yet, but it should compile as part of the DarwinKitCore target)

**Step 3: Commit**

```bash
git add packages/darwinkit-swift/Sources/DarwinKitCore/Providers/TranslationProvider.swift
git commit -m "feat(translate): add TranslationProvider protocol and supporting types"
```

---

## Task 2: Swift -- MockTranslationProvider + TranslationHandler Tests

**Files:**
- Create: `packages/darwinkit-swift/Tests/DarwinKitCoreTests/TranslationHandlerTests.swift`

**Step 1: Write the mock provider and all handler tests**

```swift
import Foundation
import Testing
@testable import DarwinKitCore

// MARK: - Mock Provider

struct MockTranslationProvider: TranslationProvider {
    var translateResult = TranslationResult(text: "Hola mundo", sourceLanguage: "en", targetLanguage: "es")
    var batchResults = [
        TranslationResult(text: "Hola", sourceLanguage: "en", targetLanguage: "es"),
        TranslationResult(text: "Adios", sourceLanguage: "en", targetLanguage: "es"),
    ]
    var languages = [
        TranslationLanguageInfo(locale: "en", name: "English"),
        TranslationLanguageInfo(locale: "es", name: "Spanish"),
        TranslationLanguageInfo(locale: "fr", name: "French"),
    ]
    var pairStatus: TranslationPairStatus = .installed
    var shouldThrow: JsonRpcError? = nil

    func translate(text: String, source: String?, target: String) throws -> TranslationResult {
        if let err = shouldThrow { throw err }
        return translateResult
    }

    func translateBatch(texts: [String], source: String?, target: String) throws -> [TranslationResult] {
        if let err = shouldThrow { throw err }
        return Array(batchResults.prefix(texts.count))
    }

    func supportedLanguages() throws -> [TranslationLanguageInfo] {
        if let err = shouldThrow { throw err }
        return languages
    }

    func languagePairStatus(source: String, target: String) throws -> TranslationPairStatus {
        if let err = shouldThrow { throw err }
        return pairStatus
    }

    func prepare(source: String, target: String) throws {
        if let err = shouldThrow { throw err }
    }
}

// MARK: - Helper

private func makeRequest(method: String, params: [String: Any] = [:]) -> JsonRpcRequest {
    let codableParams = params.mapValues { AnyCodable($0) }
    return JsonRpcRequest(id: "test", method: method, params: codableParams)
}

// MARK: - Tests

@Suite("Translation Handler")
struct TranslationHandlerTests {

    // MARK: - translate.text

    @Test("text returns translated text with source and target")
    func translateTextSuccess() throws {
        let handler = TranslationHandler(provider: MockTranslationProvider())
        let request = makeRequest(method: "translate.text", params: [
            "text": "Hello world", "target": "es"
        ])
        let result = try handler.handle(request) as! [String: Any]

        #expect(result["text"] as? String == "Hola mundo")
        #expect(result["source"] as? String == "en")
        #expect(result["target"] as? String == "es")
    }

    @Test("text accepts explicit source language")
    func translateTextWithSource() throws {
        let handler = TranslationHandler(provider: MockTranslationProvider())
        let request = makeRequest(method: "translate.text", params: [
            "text": "Hello world", "source": "en", "target": "es"
        ])
        let result = try handler.handle(request) as! [String: Any]

        #expect(result["text"] as? String == "Hola mundo")
    }

    @Test("text throws on missing text")
    func translateTextMissingText() {
        let handler = TranslationHandler(provider: MockTranslationProvider())
        let request = makeRequest(method: "translate.text", params: ["target": "es"])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    @Test("text throws on missing target")
    func translateTextMissingTarget() {
        let handler = TranslationHandler(provider: MockTranslationProvider())
        let request = makeRequest(method: "translate.text", params: ["text": "Hello"])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    @Test("text throws on empty text")
    func translateTextEmptyText() {
        let handler = TranslationHandler(provider: MockTranslationProvider())
        let request = makeRequest(method: "translate.text", params: [
            "text": "", "target": "es"
        ])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    // MARK: - translate.batch

    @Test("batch returns array of translations")
    func translateBatchSuccess() throws {
        let handler = TranslationHandler(provider: MockTranslationProvider())
        let request = makeRequest(method: "translate.batch", params: [
            "texts": ["Hello", "Goodbye"], "target": "es"
        ])
        let result = try handler.handle(request) as! [String: Any]
        let translations = result["translations"] as! [[String: Any]]

        #expect(translations.count == 2)
        #expect(translations[0]["text"] as? String == "Hola")
        #expect(translations[1]["text"] as? String == "Adios")
    }

    @Test("batch throws on empty texts array")
    func translateBatchEmpty() {
        let handler = TranslationHandler(provider: MockTranslationProvider())
        let request = makeRequest(method: "translate.batch", params: [
            "texts": [] as [String], "target": "es"
        ])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    @Test("batch throws on missing texts")
    func translateBatchMissingTexts() {
        let handler = TranslationHandler(provider: MockTranslationProvider())
        let request = makeRequest(method: "translate.batch", params: ["target": "es"])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    @Test("batch throws on missing target")
    func translateBatchMissingTarget() {
        let handler = TranslationHandler(provider: MockTranslationProvider())
        let request = makeRequest(method: "translate.batch", params: [
            "texts": ["Hello"]
        ])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    // MARK: - translate.languages

    @Test("languages returns list of supported languages")
    func languagesSuccess() throws {
        let handler = TranslationHandler(provider: MockTranslationProvider())
        let request = makeRequest(method: "translate.languages")
        let result = try handler.handle(request) as! [String: Any]
        let languages = result["languages"] as! [[String: Any]]

        #expect(languages.count == 3)
        #expect(languages[0]["locale"] as? String == "en")
        #expect(languages[0]["name"] as? String == "English")
    }

    // MARK: - translate.language_status

    @Test("language_status returns status for language pair")
    func languageStatusSuccess() throws {
        let handler = TranslationHandler(provider: MockTranslationProvider())
        let request = makeRequest(method: "translate.language_status", params: [
            "source": "en", "target": "es"
        ])
        let result = try handler.handle(request) as! [String: Any]

        #expect(result["status"] as? String == "installed")
        #expect(result["source"] as? String == "en")
        #expect(result["target"] as? String == "es")
    }

    @Test("language_status throws on missing source")
    func languageStatusMissingSource() {
        let handler = TranslationHandler(provider: MockTranslationProvider())
        let request = makeRequest(method: "translate.language_status", params: ["target": "es"])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    @Test("language_status throws on missing target")
    func languageStatusMissingTarget() {
        let handler = TranslationHandler(provider: MockTranslationProvider())
        let request = makeRequest(method: "translate.language_status", params: ["source": "en"])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    // MARK: - translate.prepare

    @Test("prepare returns ok for valid pair")
    func prepareSuccess() throws {
        let handler = TranslationHandler(provider: MockTranslationProvider())
        let request = makeRequest(method: "translate.prepare", params: [
            "source": "en", "target": "es"
        ])
        let result = try handler.handle(request) as! [String: Any]

        #expect(result["ok"] as? Bool == true)
        #expect(result["source"] as? String == "en")
        #expect(result["target"] as? String == "es")
    }

    @Test("prepare throws on missing source")
    func prepareMissingSource() {
        let handler = TranslationHandler(provider: MockTranslationProvider())
        let request = makeRequest(method: "translate.prepare", params: ["target": "es"])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    @Test("prepare throws on missing target")
    func prepareMissingTarget() {
        let handler = TranslationHandler(provider: MockTranslationProvider())
        let request = makeRequest(method: "translate.prepare", params: ["source": "en"])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    // MARK: - Method registration

    @Test("handler registers all 5 translate methods")
    func methodRegistration() {
        let handler = TranslationHandler(provider: MockTranslationProvider())
        let expected: Set<String> = [
            "translate.text", "translate.batch", "translate.languages",
            "translate.language_status", "translate.prepare"
        ]

        #expect(Set(handler.methods) == expected)
    }

    @Test("handler reports capabilities for all methods")
    func capabilities() {
        let handler = TranslationHandler(provider: MockTranslationProvider())

        for method in handler.methods {
            let cap = handler.capability(for: method)
            #expect(cap.available == true)
        }
    }

    // MARK: - Provider error propagation

    @Test("provider errors propagate through handler")
    func providerError() {
        var mock = MockTranslationProvider()
        mock.shouldThrow = .frameworkUnavailable("Translation not available")
        let handler = TranslationHandler(provider: mock)
        let request = makeRequest(method: "translate.text", params: [
            "text": "Hello", "target": "es"
        ])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }
}
```

**Step 2: Run tests to verify they fail (TranslationHandler doesn't exist yet)**

Run:
```bash
cd packages/darwinkit-swift && swift test 2>&1 | tail -10
```
Expected: FAIL -- compilation error because `TranslationHandler` is not defined

**Step 3: Commit the test file (tests-first)**

```bash
git add packages/darwinkit-swift/Tests/DarwinKitCoreTests/TranslationHandlerTests.swift
git commit -m "test(translate): add TranslationHandler tests with MockTranslationProvider"
```

---

## Task 3: Swift -- TranslationHandler Implementation

**Files:**
- Create: `packages/darwinkit-swift/Sources/DarwinKitCore/Handlers/TranslationHandler.swift`

**Step 1: Write the handler**

```swift
import Foundation

/// Handles all translate.* methods: text, batch, languages, language_status, prepare.
public final class TranslationHandler: MethodHandler {
    private let provider: TranslationProvider

    public var methods: [String] {
        [
            "translate.text", "translate.batch", "translate.languages",
            "translate.language_status", "translate.prepare"
        ]
    }

    public init(provider: TranslationProvider) {
        self.provider = provider
    }

    public func handle(_ request: JsonRpcRequest) throws -> Any {
        switch request.method {
        case "translate.text":
            return try handleText(request)
        case "translate.batch":
            return try handleBatch(request)
        case "translate.languages":
            return try handleLanguages(request)
        case "translate.language_status":
            return try handleLanguageStatus(request)
        case "translate.prepare":
            return try handlePrepare(request)
        default:
            throw JsonRpcError.methodNotFound(request.method)
        }
    }

    public func capability(for method: String) -> MethodCapability {
        MethodCapability(available: true, note: "Requires macOS 14.4+")
    }

    // MARK: - Method Implementations

    private func handleText(_ request: JsonRpcRequest) throws -> Any {
        let text = try request.requireString("text")
        let target = try request.requireString("target")
        let source = request.string("source")

        guard !text.isEmpty else {
            throw JsonRpcError.invalidParams("text must not be empty")
        }

        let result = try provider.translate(text: text, source: source, target: target)
        return result.toDict()
    }

    private func handleBatch(_ request: JsonRpcRequest) throws -> Any {
        let target = try request.requireString("target")
        let source = request.string("source")

        guard let texts = request.stringArray("texts"), !texts.isEmpty else {
            throw JsonRpcError.invalidParams("texts must be a non-empty array of strings")
        }

        let results = try provider.translateBatch(texts: texts, source: source, target: target)
        return [
            "translations": results.map { $0.toDict() }
        ] as [String: Any]
    }

    private func handleLanguages(_ request: JsonRpcRequest) throws -> Any {
        let languages = try provider.supportedLanguages()
        return [
            "languages": languages.map { $0.toDict() }
        ] as [String: Any]
    }

    private func handleLanguageStatus(_ request: JsonRpcRequest) throws -> Any {
        let source = try request.requireString("source")
        let target = try request.requireString("target")

        let status = try provider.languagePairStatus(source: source, target: target)
        return [
            "status": status.rawValue,
            "source": source,
            "target": target,
        ] as [String: Any]
    }

    private func handlePrepare(_ request: JsonRpcRequest) throws -> Any {
        let source = try request.requireString("source")
        let target = try request.requireString("target")

        try provider.prepare(source: source, target: target)
        return [
            "ok": true,
            "source": source,
            "target": target,
        ] as [String: Any]
    }
}
```

**Step 2: Run tests to verify they pass**

Run:
```bash
cd packages/darwinkit-swift && swift test --filter TranslationHandlerTests 2>&1 | tail -20
```
Expected: All 17 tests PASS

**Step 3: Commit**

```bash
git add packages/darwinkit-swift/Sources/DarwinKitCore/Handlers/TranslationHandler.swift
git commit -m "feat(translate): implement TranslationHandler with all 5 methods"
```

---

## Task 4: Swift -- AppleTranslationProvider Implementation

**Files:**
- Modify: `packages/darwinkit-swift/Sources/DarwinKitCore/Providers/TranslationProvider.swift` (append implementation)

**Step 1: Add the Apple implementation below the protocol**

Append to the end of `TranslationProvider.swift`. The `import Translation` must be at the file level, and since the `Translation` module is only available on macOS 14.4+, we use conditional compilation:

```swift
// MARK: - Apple Implementation

#if canImport(Translation)
import Translation

@available(macOS 14.4, *)
public final class AppleTranslationProvider: TranslationProvider {

    public init() {}

    public func translate(text: String, source: String?, target: String) throws -> TranslationResult {
        let sourceLang = source.map { Locale.Language(identifier: $0) }
        let targetLang = Locale.Language(identifier: target)

        let config = TranslationSession.Configuration(
            source: sourceLang,
            target: targetLang
        )

        var translatedText: String = ""
        var detectedSource: String = source ?? ""
        var translationError: Error?

        let semaphore = DispatchSemaphore(value: 0)

        Task {
            do {
                let session = TranslationSession(configuration: config)
                let response = try await session.translate(text)
                translatedText = response.targetText
                if let responseLang = response.sourceLanguage {
                    detectedSource = responseLang.minimalIdentifier
                }
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

    public func translateBatch(texts: [String], source: String?, target: String) throws -> [TranslationResult] {
        let sourceLang = source.map { Locale.Language(identifier: $0) }
        let targetLang = Locale.Language(identifier: target)

        let config = TranslationSession.Configuration(
            source: sourceLang,
            target: targetLang
        )

        var results: [TranslationResult] = []
        var translationError: Error?

        let semaphore = DispatchSemaphore(value: 0)

        Task {
            do {
                let session = TranslationSession(configuration: config)
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
                        let detectedSource = response.sourceLanguage?.minimalIdentifier ?? source ?? ""
                        results.append(TranslationResult(
                            text: response.targetText,
                            sourceLanguage: detectedSource,
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
        var queryError: Error?

        let semaphore = DispatchSemaphore(value: 0)

        Task {
            do {
                let availability = LanguageAvailability()
                let rawStatus = try await availability.status(from: sourceLang, to: targetLang)
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
            } catch {
                queryError = error
            }
            semaphore.signal()
        }

        semaphore.wait()

        if let error = queryError {
            throw JsonRpcError.internalError("Failed to check language status: \(error.localizedDescription)")
        }

        return status
    }

    public func prepare(source: String, target: String) throws {
        let sourceLang = Locale.Language(identifier: source)
        let targetLang = Locale.Language(identifier: target)

        let config = TranslationSession.Configuration(
            source: sourceLang,
            target: targetLang
        )

        var prepareError: Error?

        let semaphore = DispatchSemaphore(value: 0)

        Task {
            do {
                let session = TranslationSession(configuration: config)
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
}

#else

/// Fallback for when Translation framework is not available (older Xcode / macOS)
public final class AppleTranslationProvider: TranslationProvider {
    public init() {}

    public func translate(text: String, source: String?, target: String) throws -> TranslationResult {
        throw JsonRpcError.osVersionTooOld("Translation requires macOS 14.4+ and Xcode 15.3+")
    }

    public func translateBatch(texts: [String], source: String?, target: String) throws -> [TranslationResult] {
        throw JsonRpcError.osVersionTooOld("Translation requires macOS 14.4+ and Xcode 15.3+")
    }

    public func supportedLanguages() throws -> [TranslationLanguageInfo] {
        throw JsonRpcError.osVersionTooOld("Translation requires macOS 14.4+ and Xcode 15.3+")
    }

    public func languagePairStatus(source: String, target: String) throws -> TranslationPairStatus {
        throw JsonRpcError.osVersionTooOld("Translation requires macOS 14.4+ and Xcode 15.3+")
    }

    public func prepare(source: String, target: String) throws {
        throw JsonRpcError.osVersionTooOld("Translation requires macOS 14.4+ and Xcode 15.3+")
    }
}

#endif
```

**Step 2: Verify it compiles**

Run:
```bash
cd packages/darwinkit-swift && swift build 2>&1 | tail -20
```
Expected: BUILD SUCCEEDED

If the build fails because `Translation` module isn't found, the `#if !canImport(Translation)` fallback will be used automatically. This is safe.

**Step 3: Run all tests to make sure nothing broke**

Run:
```bash
cd packages/darwinkit-swift && swift test 2>&1 | tail -20
```
Expected: All tests pass (the handler tests use MockTranslationProvider, not Apple's)

**Step 4: Commit**

```bash
git add packages/darwinkit-swift/Sources/DarwinKitCore/Providers/TranslationProvider.swift
git commit -m "feat(translate): implement AppleTranslationProvider with Translation framework"
```

---

## Task 5: Swift -- Register TranslationHandler in DarwinKit.swift

**Files:**
- Modify: `packages/darwinkit-swift/Sources/DarwinKit/DarwinKit.swift`

**Step 1: Add TranslationHandler registration to both `buildServerWithRouter()` and `buildRouter()`**

In `buildServerWithRouter()`, add after the `router.register(AuthHandler())` line:

```swift
    router.register(TranslationHandler(provider: AppleTranslationProvider()))
```

In `buildRouter()`, add after the `router.register(AuthHandler())` line:

```swift
    router.register(TranslationHandler(provider: AppleTranslationProvider()))
```

The full modified functions should be:

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
    router.register(TranslationHandler(provider: AppleTranslationProvider()))

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
    router.register(TranslationHandler(provider: AppleTranslationProvider()))
    return router
}
```

**Step 2: Verify it builds**

Run:
```bash
cd packages/darwinkit-swift && swift build 2>&1 | tail -10
```
Expected: BUILD SUCCEEDED

**Step 3: Run all tests**

Run:
```bash
cd packages/darwinkit-swift && swift test 2>&1 | tail -20
```
Expected: All tests pass

**Step 4: Commit**

```bash
git add packages/darwinkit-swift/Sources/DarwinKit/DarwinKit.swift
git commit -m "feat(translate): register TranslationHandler in server startup"
```

---

## Task 6: TypeScript SDK -- Translation Types + MethodMap Entries

**Files:**
- Modify: `packages/darwinkit/src/types.ts`

**Step 1: Add Translation types before the MethodMap section**

Add this block right before the `// MethodMap` comment (`// ---------------------------------------------------------------------------` line ~277):

```typescript
// ---------------------------------------------------------------------------
// Translation
// ---------------------------------------------------------------------------

export interface TranslateTextParams {
  text: string
  source?: string // omit for auto-detect
  target: string
}
export interface TranslateTextResult {
  text: string
  source: string
  target: string
}

export interface TranslateBatchParams {
  texts: string[]
  source?: string // omit for auto-detect
  target: string
}
export interface TranslateBatchResult {
  translations: TranslateTextResult[]
}

export interface TranslateLanguagesResult {
  languages: TranslateLanguageInfo[]
}
export interface TranslateLanguageInfo {
  locale: string
  name: string
}

export interface TranslateLanguageStatusParams {
  source: string
  target: string
}
export type TranslateLanguageStatus = "installed" | "supported" | "unsupported"
export interface TranslateLanguageStatusResult {
  status: TranslateLanguageStatus
  source: string
  target: string
}

export interface TranslatePrepareParams {
  source: string
  target: string
}
export interface TranslatePrepareResult {
  ok: true
  source: string
  target: string
}
```

**Step 2: Add MethodMap entries**

Add these entries inside the `MethodMap` interface, after the `coreml.embed_contextual_batch` entry (around line 365):

```typescript
  "translate.text": {
    params: TranslateTextParams
    result: TranslateTextResult
  }
  "translate.batch": {
    params: TranslateBatchParams
    result: TranslateBatchResult
  }
  "translate.languages": {
    params: Record<string, never>
    result: TranslateLanguagesResult
  }
  "translate.language_status": {
    params: TranslateLanguageStatusParams
    result: TranslateLanguageStatusResult
  }
  "translate.prepare": {
    params: TranslatePrepareParams
    result: TranslatePrepareResult
  }
```

**Step 3: Verify TypeScript compiles**

Run:
```bash
bunx tsgo --noEmit 2>&1 | head -20
```
Expected: No errors

**Step 4: Commit**

```bash
git add packages/darwinkit/src/types.ts
git commit -m "feat(translate): add Translation types and MethodMap entries to TS SDK"
```

---

## Task 7: TypeScript SDK -- Translate Namespace Class

**Files:**
- Create: `packages/darwinkit/src/namespaces/translate.ts`

**Step 1: Write the namespace class**

```typescript
import type { DarwinKitClient } from "../client.js"
import type {
  MethodMap,
  MethodName,
  PreparedCall,
  TranslateTextParams,
  TranslateTextResult,
  TranslateBatchParams,
  TranslateBatchResult,
  TranslateLanguagesResult,
  TranslateLanguageStatusParams,
  TranslateLanguageStatusResult,
  TranslatePrepareParams,
  TranslatePrepareResult,
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

export class Translate {
  readonly text: {
    (
      params: TranslateTextParams,
      options?: { timeout?: number },
    ): Promise<TranslateTextResult>
    prepare(params: TranslateTextParams): PreparedCall<"translate.text">
  }
  readonly batch: {
    (
      params: TranslateBatchParams,
      options?: { timeout?: number },
    ): Promise<TranslateBatchResult>
    prepare(params: TranslateBatchParams): PreparedCall<"translate.batch">
  }
  readonly languageStatus: {
    (
      params: TranslateLanguageStatusParams,
      options?: { timeout?: number },
    ): Promise<TranslateLanguageStatusResult>
    prepare(
      params: TranslateLanguageStatusParams,
    ): PreparedCall<"translate.language_status">
  }
  readonly preparePair: {
    (
      params: TranslatePrepareParams,
      options?: { timeout?: number },
    ): Promise<TranslatePrepareResult>
    prepare(
      params: TranslatePrepareParams,
    ): PreparedCall<"translate.prepare">
  }

  private client: DarwinKitClient

  constructor(client: DarwinKitClient) {
    this.client = client
    this.text = method(client, "translate.text") as Translate["text"]
    this.batch = method(client, "translate.batch") as Translate["batch"]
    this.languageStatus = method(
      client,
      "translate.language_status",
    ) as Translate["languageStatus"]
    this.preparePair = method(
      client,
      "translate.prepare",
    ) as Translate["preparePair"]
  }

  /** List all supported translation languages (no params needed) */
  languages(options?: { timeout?: number }): Promise<TranslateLanguagesResult> {
    return this.client.call(
      "translate.languages",
      {} as Record<string, never>,
      options,
    )
  }
}
```

Note: the `prepare` property is named `preparePair` to avoid collision with the `prepare` method that exists on each callable (the `.prepare()` method for creating `PreparedCall`s). This is a naming compromise to avoid confusion.

**Step 2: Verify TypeScript compiles**

Run:
```bash
cd /Users/Martin/Tresors/Projects/darwinkit-swift && bunx tsgo --noEmit 2>&1 | head -20
```
Expected: No errors

**Step 3: Commit**

```bash
git add packages/darwinkit/src/namespaces/translate.ts
git commit -m "feat(translate): add Translate namespace class to TS SDK"
```

---

## Task 8: TypeScript SDK -- Wire Translate Into Client + Exports

**Files:**
- Modify: `packages/darwinkit/src/client.ts`
- Modify: `packages/darwinkit/src/index.ts`

**Step 1: Add Translate to client.ts**

In the imports section (around line 17), add:
```typescript
import { Translate } from "./namespaces/translate.js"
```

In the `DarwinKit` class property declarations (around line 89), add:
```typescript
  readonly translate: Translate
```

In the constructor (around line 131), add:
```typescript
    this.translate = new Translate(this)
```

**Step 2: Add Translate to index.ts**

Add the namespace export (around line 14):
```typescript
export { Translate } from "./namespaces/translate.js"
```

Add the type exports inside the existing `export type { ... }` block:
```typescript
  // Translation
  TranslateTextParams,
  TranslateTextResult,
  TranslateBatchParams,
  TranslateBatchResult,
  TranslateLanguagesResult,
  TranslateLanguageInfo,
  TranslateLanguageStatusParams,
  TranslateLanguageStatus,
  TranslateLanguageStatusResult,
  TranslatePrepareParams,
  TranslatePrepareResult,
```

**Step 3: Verify TypeScript compiles**

Run:
```bash
cd /Users/Martin/Tresors/Projects/darwinkit-swift && bunx tsgo --noEmit 2>&1 | head -20
```
Expected: No errors

**Step 4: Commit**

```bash
git add packages/darwinkit/src/client.ts packages/darwinkit/src/index.ts
git commit -m "feat(translate): wire Translate namespace into DarwinKit client and exports"
```

---

## Task 9: Build + Verify Everything

**Step 1: Run Swift tests**

Run:
```bash
cd packages/darwinkit-swift && swift test 2>&1 | tail -20
```
Expected: All tests pass, including all 17 TranslationHandler tests

**Step 2: Build TypeScript SDK**

Run:
```bash
cd packages/darwinkit && bun run build 2>&1
```
Expected: Build succeeds with no errors

**Step 3: Verify the dist output includes Translate**

Run:
```bash
grep -l "Translate" packages/darwinkit/dist/*
```
Expected: Should show up in the dist files

**Step 4: Final commit if any build artifacts changed**

```bash
git add packages/darwinkit/dist/
git commit -m "build(translate): rebuild TS SDK dist with Translation namespace"
```

---

## Summary of All Files

### New files (Swift):
1. `packages/darwinkit-swift/Sources/DarwinKitCore/Providers/TranslationProvider.swift` -- protocol, types, Apple implementation
2. `packages/darwinkit-swift/Sources/DarwinKitCore/Handlers/TranslationHandler.swift` -- JSON-RPC handler
3. `packages/darwinkit-swift/Tests/DarwinKitCoreTests/TranslationHandlerTests.swift` -- 17 tests with mock

### Modified files (Swift):
4. `packages/darwinkit-swift/Sources/DarwinKit/DarwinKit.swift` -- register handler

### New files (TypeScript):
5. `packages/darwinkit/src/namespaces/translate.ts` -- Translate class

### Modified files (TypeScript):
6. `packages/darwinkit/src/types.ts` -- Translation types + MethodMap entries
7. `packages/darwinkit/src/client.ts` -- add `translate` property
8. `packages/darwinkit/src/index.ts` -- export Translate class + types

---

## API Usage Examples (for documentation/README)

### TypeScript

```typescript
import { DarwinKit } from "@genesiscz/darwinkit"

const dk = new DarwinKit()
await dk.connect()

// Translate text (auto-detect source)
const result = await dk.translate.text({
  text: "Hello, how are you?",
  target: "es",
})
console.log(result.text) // "Hola, como estas?"
console.log(result.source) // "en" (auto-detected)

// Translate with explicit source
const result2 = await dk.translate.text({
  text: "Bonjour",
  source: "fr",
  target: "en",
})

// Batch translation
const batch = await dk.translate.batch({
  texts: ["Good morning", "Good night", "Thank you"],
  target: "de",
})
batch.translations.forEach((t) => console.log(t.text))

// List supported languages
const { languages } = await dk.translate.languages()
languages.forEach((l) => console.log(`${l.locale}: ${l.name}`))

// Check if a pair is ready
const status = await dk.translate.languageStatus({
  source: "en",
  target: "ja",
})
if (status.status !== "installed") {
  // Download models first
  await dk.translate.preparePair({ source: "en", target: "ja" })
}

dk.close()
```

### CLI (Query mode)

```bash
# Translate text
darwinkit query '{"jsonrpc":"2.0","id":"1","method":"translate.text","params":{"text":"Hello world","target":"es"}}'

# List languages
darwinkit query '{"jsonrpc":"2.0","id":"1","method":"translate.languages","params":{}}'
```
