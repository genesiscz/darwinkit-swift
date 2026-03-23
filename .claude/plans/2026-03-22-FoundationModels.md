# Foundation Models (`llm.*`) Implementation Plan

> **GitHub Issue:** https://github.com/genesiscz/darwinkit-swift/issues/6


> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add on-device LLM support via Apple's FoundationModels framework (macOS 26+), exposed as 7 JSON-RPC methods under the `llm.*` namespace.

**Architecture:** Provider protocol (`LLMProvider`) with mock + real (`AppleLLMProvider`) implementations. `LLMHandler` routes `llm.*` requests to the provider. The handler holds a `NotificationSink` reference for streaming chunks as JSON-RPC notifications. Sessions are tracked in-memory by ID inside the provider. The TS SDK gets an `LLM` namespace class and full type definitions.

**Tech Stack:** Swift 5.9, FoundationModels framework (macOS 26+), Swift Testing, TypeScript (Bun)

---

## File Map

| Layer | File | Action |
|-------|------|--------|
| Swift Provider | `packages/darwinkit-swift/Sources/DarwinKitCore/Providers/LLMProvider.swift` | Create |
| Swift Handler | `packages/darwinkit-swift/Sources/DarwinKitCore/Handlers/LLMHandler.swift` | Create |
| Swift Entry | `packages/darwinkit-swift/Sources/DarwinKit/DarwinKit.swift` | Modify (register handler) |
| Swift Tests | `packages/darwinkit-swift/Tests/DarwinKitCoreTests/LLMHandlerTests.swift` | Create |
| TS Types | `packages/darwinkit/src/types.ts` | Modify (add LLM types + MethodMap entries) |
| TS Namespace | `packages/darwinkit/src/namespaces/llm.ts` | Create |
| TS Client | `packages/darwinkit/src/client.ts` | Modify (add `llm` namespace) |
| TS Index | `packages/darwinkit/src/index.ts` | Modify (export LLM) |
| TS Events | `packages/darwinkit/src/events.ts` | Modify (add llmChunk event) |

All file paths below are relative to the repo root: `/Users/Martin/Tresors/Projects/darwinkit-swift`

---

## Task 1: LLMProvider Protocol + MockLLMProvider

**Files:**
- Create: `packages/darwinkit-swift/Sources/DarwinKitCore/Providers/LLMProvider.swift`

### Step 1: Create the LLMProvider protocol and supporting types

This file defines the contract between handler and provider, plus all the value types exchanged. The `MockLLMProvider` is used by tests in Task 2.

```swift
import Foundation

// MARK: - Types

public struct LLMGenerateParams {
    public let prompt: String
    public let systemInstructions: String?
    public let temperature: Double?
    public let maxTokens: Int?

    public init(prompt: String, systemInstructions: String? = nil, temperature: Double? = nil, maxTokens: Int? = nil) {
        self.prompt = prompt
        self.systemInstructions = systemInstructions
        self.temperature = temperature
        self.maxTokens = maxTokens
    }
}

public struct LLMGenerateResult {
    public let text: String

    public init(text: String) {
        self.text = text
    }

    public func toDict() -> [String: Any] {
        ["text": text]
    }
}

public struct LLMGenerateStructuredParams {
    public let prompt: String
    public let schema: [String: Any]
    public let systemInstructions: String?
    public let temperature: Double?
    public let maxTokens: Int?

    public init(prompt: String, schema: [String: Any], systemInstructions: String? = nil, temperature: Double? = nil, maxTokens: Int? = nil) {
        self.prompt = prompt
        self.schema = schema
        self.systemInstructions = systemInstructions
        self.temperature = temperature
        self.maxTokens = maxTokens
    }
}

public struct LLMGenerateStructuredResult {
    public let json: [String: Any]

    public init(json: [String: Any]) {
        self.json = json
    }

    public func toDict() -> [String: Any] {
        ["json": json]
    }
}

public struct LLMStreamParams {
    public let prompt: String
    public let systemInstructions: String?
    public let temperature: Double?
    public let maxTokens: Int?

    public init(prompt: String, systemInstructions: String? = nil, temperature: Double? = nil, maxTokens: Int? = nil) {
        self.prompt = prompt
        self.systemInstructions = systemInstructions
        self.temperature = temperature
        self.maxTokens = maxTokens
    }
}

public struct LLMSessionCreateParams {
    public let sessionId: String
    public let instructions: String?

    public init(sessionId: String, instructions: String? = nil) {
        self.sessionId = sessionId
        self.instructions = instructions
    }
}

public struct LLMSessionRespondParams {
    public let sessionId: String
    public let prompt: String
    public let temperature: Double?
    public let maxTokens: Int?

    public init(sessionId: String, prompt: String, temperature: Double? = nil, maxTokens: Int? = nil) {
        self.sessionId = sessionId
        self.prompt = prompt
        self.temperature = temperature
        self.maxTokens = maxTokens
    }
}

public enum LLMAvailabilityStatus: String {
    case available
    case unavailable
}

public struct LLMAvailabilityResult {
    public let status: LLMAvailabilityStatus
    public let reason: String?

    public init(status: LLMAvailabilityStatus, reason: String? = nil) {
        self.status = status
        self.reason = reason
    }

    public func toDict() -> [String: Any] {
        var dict: [String: Any] = ["available": status == .available]
        if let reason = reason {
            dict["reason"] = reason
        }
        return dict
    }
}

// MARK: - Provider Protocol

/// Abstraction over on-device LLM (Foundation Models on macOS 26+).
/// All methods are synchronous from the caller's perspective (bridged internally).
public protocol LLMProvider {
    /// Generate text from a prompt (single-shot, no session).
    func generate(params: LLMGenerateParams) throws -> LLMGenerateResult

    /// Generate structured JSON output from a prompt + JSON schema.
    func generateStructured(params: LLMGenerateStructuredParams) throws -> LLMGenerateStructuredResult

    /// Stream text generation. Calls `onChunk` for each partial token, returns full text when done.
    func stream(params: LLMStreamParams, onChunk: @escaping (String) -> Void) throws -> LLMGenerateResult

    /// Create a named session for multi-turn conversation.
    func sessionCreate(params: LLMSessionCreateParams) throws

    /// Send a message to an existing session. Returns the model's response.
    func sessionRespond(params: LLMSessionRespondParams) throws -> LLMGenerateResult

    /// Close and free a session.
    func sessionClose(sessionId: String) throws

    /// Check if the on-device model is available.
    func available() -> LLMAvailabilityResult
}

// MARK: - Mock Implementation (for tests)

public final class MockLLMProvider: LLMProvider {
    public var generateResult: LLMGenerateResult = LLMGenerateResult(text: "Hello from mock LLM")
    public var structuredResult: LLMGenerateStructuredResult = LLMGenerateStructuredResult(json: ["name": "Test", "score": 42])
    public var streamChunks: [String] = ["Hello", " from", " mock"]
    public var availabilityResult: LLMAvailabilityResult = LLMAvailabilityResult(status: .available)
    public var shouldThrow: JsonRpcError? = nil
    public private(set) var activeSessions: Set<String> = []

    public init() {}

    public func generate(params: LLMGenerateParams) throws -> LLMGenerateResult {
        if let err = shouldThrow { throw err }
        return generateResult
    }

    public func generateStructured(params: LLMGenerateStructuredParams) throws -> LLMGenerateStructuredResult {
        if let err = shouldThrow { throw err }
        return structuredResult
    }

    public func stream(params: LLMStreamParams, onChunk: @escaping (String) -> Void) throws -> LLMGenerateResult {
        if let err = shouldThrow { throw err }
        for chunk in streamChunks {
            onChunk(chunk)
        }
        return LLMGenerateResult(text: streamChunks.joined())
    }

    public func sessionCreate(params: LLMSessionCreateParams) throws {
        if let err = shouldThrow { throw err }
        guard !activeSessions.contains(params.sessionId) else {
            throw JsonRpcError.invalidParams("Session already exists: \(params.sessionId)")
        }
        activeSessions.insert(params.sessionId)
    }

    public func sessionRespond(params: LLMSessionRespondParams) throws -> LLMGenerateResult {
        if let err = shouldThrow { throw err }
        guard activeSessions.contains(params.sessionId) else {
            throw JsonRpcError.invalidParams("No session with id: \(params.sessionId)")
        }
        return generateResult
    }

    public func sessionClose(sessionId: String) throws {
        if let err = shouldThrow { throw err }
        guard activeSessions.remove(sessionId) != nil else {
            throw JsonRpcError.invalidParams("No session with id: \(sessionId)")
        }
    }

    public func available() -> LLMAvailabilityResult {
        return availabilityResult
    }
}
```

### Step 2: Verify it compiles

Run:
```bash
cd /Users/Martin/Tresors/Projects/darwinkit-swift/packages/darwinkit-swift && swift build 2>&1 | tail -5
```
Expected: BUILD SUCCEEDED (the file is purely types + mock, no external deps)

### Step 3: Commit

```bash
git add packages/darwinkit-swift/Sources/DarwinKitCore/Providers/LLMProvider.swift
git commit -m "feat(llm): add LLMProvider protocol and MockLLMProvider"
```

---

## Task 2: LLMHandler Tests (Red Phase)

**Files:**
- Create: `packages/darwinkit-swift/Tests/DarwinKitCoreTests/LLMHandlerTests.swift`

### Step 1: Write all handler tests

These tests follow the exact same pattern as `NLPHandlerTests.swift` and `CoreMLHandlerTests.swift`. The handler under test does not exist yet -- these will fail to compile.

```swift
import Foundation
import Testing
@testable import DarwinKitCore

// MARK: - Helper

private func makeRequest(method: String, params: [String: Any] = [:]) -> JsonRpcRequest {
    let codableParams = params.mapValues { AnyCodable($0) }
    return JsonRpcRequest(id: "test", method: method, params: codableParams)
}

// MARK: - Mock NotificationSink

private final class MockNotificationSink: NotificationSink {
    var notifications: [(method: String, params: Any)] = []

    func sendNotification(method: String, params: Any) {
        notifications.append((method: method, params: params))
    }
}

// MARK: - Tests

@Suite("LLM Handler")
struct LLMHandlerTests {

    // MARK: - llm.available

    @Test("available returns available status")
    func availableSuccess() throws {
        let handler = LLMHandler(provider: MockLLMProvider())
        let request = makeRequest(method: "llm.available")
        let result = try handler.handle(request) as! [String: Any]

        #expect(result["available"] as? Bool == true)
    }

    @Test("available returns unavailable with reason")
    func availableUnavailable() throws {
        let mock = MockLLMProvider()
        mock.availabilityResult = LLMAvailabilityResult(status: .unavailable, reason: "Model not downloaded")
        let handler = LLMHandler(provider: mock)
        let request = makeRequest(method: "llm.available")
        let result = try handler.handle(request) as! [String: Any]

        #expect(result["available"] as? Bool == false)
        #expect(result["reason"] as? String == "Model not downloaded")
    }

    // MARK: - llm.generate

    @Test("generate returns text")
    func generateSuccess() throws {
        let handler = LLMHandler(provider: MockLLMProvider())
        let request = makeRequest(method: "llm.generate", params: [
            "prompt": "Tell me a joke"
        ])
        let result = try handler.handle(request) as! [String: Any]

        #expect(result["text"] as? String == "Hello from mock LLM")
    }

    @Test("generate throws on missing prompt")
    func generateMissingPrompt() {
        let handler = LLMHandler(provider: MockLLMProvider())
        let request = makeRequest(method: "llm.generate", params: [:])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    @Test("generate accepts optional temperature and max_tokens")
    func generateWithOptions() throws {
        let handler = LLMHandler(provider: MockLLMProvider())
        let request = makeRequest(method: "llm.generate", params: [
            "prompt": "Hello",
            "temperature": 0.7,
            "max_tokens": 100,
            "system_instructions": "You are a helpful assistant"
        ])
        // Should not throw - options are passed through
        let result = try handler.handle(request) as! [String: Any]
        #expect(result["text"] as? String == "Hello from mock LLM")
    }

    // MARK: - llm.generate_structured

    @Test("generate_structured returns json")
    func generateStructuredSuccess() throws {
        let handler = LLMHandler(provider: MockLLMProvider())
        let request = makeRequest(method: "llm.generate_structured", params: [
            "prompt": "Extract name and score",
            "schema": ["type": "object", "properties": ["name": ["type": "string"]]] as [String: Any]
        ])
        let result = try handler.handle(request) as! [String: Any]
        let json = result["json"] as! [String: Any]

        #expect(json["name"] as? String == "Test")
    }

    @Test("generate_structured throws on missing prompt")
    func generateStructuredMissingPrompt() {
        let handler = LLMHandler(provider: MockLLMProvider())
        let request = makeRequest(method: "llm.generate_structured", params: [
            "schema": ["type": "object"] as [String: Any]
        ])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    @Test("generate_structured throws on missing schema")
    func generateStructuredMissingSchema() {
        let handler = LLMHandler(provider: MockLLMProvider())
        let request = makeRequest(method: "llm.generate_structured", params: [
            "prompt": "Extract data"
        ])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    // MARK: - llm.stream

    @Test("stream sends chunk notifications and returns final text")
    func streamSuccess() throws {
        let sink = MockNotificationSink()
        let handler = LLMHandler(provider: MockLLMProvider(), notificationSink: sink)
        let request = makeRequest(method: "llm.stream", params: [
            "prompt": "Tell me a story"
        ])
        let result = try handler.handle(request) as! [String: Any]

        // Final result has full text
        #expect(result["text"] as? String == "Hello from mock")

        // Should have sent 3 chunk notifications
        #expect(sink.notifications.count == 3)

        // Each notification should be method "llm.chunk" with the chunk text and request id
        for notification in sink.notifications {
            #expect(notification.method == "llm.chunk")
            let params = notification.params as! [String: Any]
            #expect(params["request_id"] as? String == "test")
        }

        // First chunk should be "Hello"
        let firstParams = sink.notifications[0].params as! [String: Any]
        #expect(firstParams["chunk"] as? String == "Hello")
    }

    @Test("stream throws on missing prompt")
    func streamMissingPrompt() {
        let handler = LLMHandler(provider: MockLLMProvider())
        let request = makeRequest(method: "llm.stream", params: [:])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    // MARK: - llm.session_create

    @Test("session_create returns ok")
    func sessionCreateSuccess() throws {
        let handler = LLMHandler(provider: MockLLMProvider())
        let request = makeRequest(method: "llm.session_create", params: [
            "session_id": "chat-1"
        ])
        let result = try handler.handle(request) as! [String: Any]

        #expect(result["ok"] as? Bool == true)
    }

    @Test("session_create throws on missing session_id")
    func sessionCreateMissingId() {
        let handler = LLMHandler(provider: MockLLMProvider())
        let request = makeRequest(method: "llm.session_create", params: [:])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    @Test("session_create throws on duplicate session_id")
    func sessionCreateDuplicate() throws {
        let mock = MockLLMProvider()
        let handler = LLMHandler(provider: mock)

        // Create first session
        let request1 = makeRequest(method: "llm.session_create", params: ["session_id": "chat-1"])
        _ = try handler.handle(request1)

        // Create duplicate
        let request2 = makeRequest(method: "llm.session_create", params: ["session_id": "chat-1"])
        #expect(throws: JsonRpcError.self) {
            try handler.handle(request2)
        }
    }

    @Test("session_create accepts optional instructions")
    func sessionCreateWithInstructions() throws {
        let handler = LLMHandler(provider: MockLLMProvider())
        let request = makeRequest(method: "llm.session_create", params: [
            "session_id": "chat-1",
            "instructions": "You are a pirate"
        ])
        let result = try handler.handle(request) as! [String: Any]
        #expect(result["ok"] as? Bool == true)
    }

    // MARK: - llm.session_respond

    @Test("session_respond returns text")
    func sessionRespondSuccess() throws {
        let mock = MockLLMProvider()
        let handler = LLMHandler(provider: mock)

        // Create session first
        let createReq = makeRequest(method: "llm.session_create", params: ["session_id": "chat-1"])
        _ = try handler.handle(createReq)

        // Respond
        let request = makeRequest(method: "llm.session_respond", params: [
            "session_id": "chat-1",
            "prompt": "Hello"
        ])
        let result = try handler.handle(request) as! [String: Any]

        #expect(result["text"] as? String == "Hello from mock LLM")
    }

    @Test("session_respond throws on missing session_id")
    func sessionRespondMissingId() {
        let handler = LLMHandler(provider: MockLLMProvider())
        let request = makeRequest(method: "llm.session_respond", params: [
            "prompt": "Hello"
        ])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    @Test("session_respond throws on missing prompt")
    func sessionRespondMissingPrompt() {
        let handler = LLMHandler(provider: MockLLMProvider())
        let request = makeRequest(method: "llm.session_respond", params: [
            "session_id": "chat-1"
        ])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    @Test("session_respond throws on unknown session")
    func sessionRespondUnknownSession() {
        let handler = LLMHandler(provider: MockLLMProvider())
        let request = makeRequest(method: "llm.session_respond", params: [
            "session_id": "nonexistent",
            "prompt": "Hello"
        ])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    // MARK: - llm.session_close

    @Test("session_close returns ok")
    func sessionCloseSuccess() throws {
        let mock = MockLLMProvider()
        let handler = LLMHandler(provider: mock)

        // Create then close
        let createReq = makeRequest(method: "llm.session_create", params: ["session_id": "chat-1"])
        _ = try handler.handle(createReq)

        let request = makeRequest(method: "llm.session_close", params: ["session_id": "chat-1"])
        let result = try handler.handle(request) as! [String: Any]

        #expect(result["ok"] as? Bool == true)
    }

    @Test("session_close throws on missing session_id")
    func sessionCloseMissingId() {
        let handler = LLMHandler(provider: MockLLMProvider())
        let request = makeRequest(method: "llm.session_close", params: [:])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    @Test("session_close throws on unknown session")
    func sessionCloseUnknown() {
        let handler = LLMHandler(provider: MockLLMProvider())
        let request = makeRequest(method: "llm.session_close", params: ["session_id": "nonexistent"])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    // MARK: - Method registration

    @Test("handler registers all 7 LLM methods")
    func methodRegistration() {
        let handler = LLMHandler(provider: MockLLMProvider())
        let expected: Set<String> = [
            "llm.generate", "llm.generate_structured", "llm.stream",
            "llm.session_create", "llm.session_respond", "llm.session_close",
            "llm.available"
        ]
        #expect(Set(handler.methods) == expected)
    }

    @Test("handler reports capabilities for all methods")
    func capabilities() {
        let handler = LLMHandler(provider: MockLLMProvider())
        for method in handler.methods {
            let cap = handler.capability(for: method)
            #expect(cap.available == true)
        }
    }

    // MARK: - Unknown method

    @Test("handler throws on unknown method via router")
    func unknownMethod() {
        let router = MethodRouter()
        router.register(LLMHandler(provider: MockLLMProvider()))
        let request = makeRequest(method: "llm.nonexistent")

        #expect(throws: JsonRpcError.self) {
            try router.dispatch(request)
        }
    }

    // MARK: - Provider error propagation

    @Test("provider errors propagate through handler")
    func providerError() {
        let mock = MockLLMProvider()
        mock.shouldThrow = .frameworkUnavailable("FoundationModels not available")
        let handler = LLMHandler(provider: mock)
        let request = makeRequest(method: "llm.generate", params: [
            "prompt": "Hello"
        ])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }
}
```

### Step 2: Run tests to verify they fail (compile error expected)

Run:
```bash
cd /Users/Martin/Tresors/Projects/darwinkit-swift/packages/darwinkit-swift && swift test 2>&1 | tail -10
```
Expected: FAIL -- `LLMHandler` is not defined yet. This confirms our tests are correctly referencing the not-yet-created handler.

### Step 3: Commit the failing tests

```bash
git add packages/darwinkit-swift/Tests/DarwinKitCoreTests/LLMHandlerTests.swift
git commit -m "test(llm): add LLMHandler tests (red phase - handler not yet implemented)"
```

---

## Task 3: LLMHandler Implementation (Green Phase)

**Files:**
- Create: `packages/darwinkit-swift/Sources/DarwinKitCore/Handlers/LLMHandler.swift`

### Step 1: Implement the handler

This follows the exact same pattern as `NLPHandler` and `CoreMLHandler`. Key difference: the `stream` method needs a `NotificationSink` to push chunk notifications. This mirrors how `CloudHandler` uses `NotificationSink` for iCloud file change events.

```swift
import Foundation

/// Handles all llm.* methods: generate, generate_structured, stream, session management, availability.
public final class LLMHandler: MethodHandler {
    private let provider: LLMProvider
    private weak var notificationSink: NotificationSink?

    public var methods: [String] {
        [
            "llm.generate", "llm.generate_structured", "llm.stream",
            "llm.session_create", "llm.session_respond", "llm.session_close",
            "llm.available"
        ]
    }

    public init(provider: LLMProvider, notificationSink: NotificationSink? = nil) {
        self.provider = provider
        self.notificationSink = notificationSink
    }

    public func handle(_ request: JsonRpcRequest) throws -> Any {
        switch request.method {
        case "llm.generate":
            return try handleGenerate(request)
        case "llm.generate_structured":
            return try handleGenerateStructured(request)
        case "llm.stream":
            return try handleStream(request)
        case "llm.session_create":
            return try handleSessionCreate(request)
        case "llm.session_respond":
            return try handleSessionRespond(request)
        case "llm.session_close":
            return try handleSessionClose(request)
        case "llm.available":
            return try handleAvailable(request)
        default:
            throw JsonRpcError.methodNotFound(request.method)
        }
    }

    public func capability(for method: String) -> MethodCapability {
        let availability = provider.available()
        let available = availability.status == .available
        let note = available ? "Requires macOS 26+ with Apple Intelligence" : availability.reason
        return MethodCapability(available: available, note: note)
    }

    // MARK: - Method Implementations

    private func handleGenerate(_ request: JsonRpcRequest) throws -> Any {
        let prompt = try request.requireString("prompt")
        let systemInstructions = request.string("system_instructions")
        let temperature = request.double("temperature")
        let maxTokens = request.int("max_tokens")

        let params = LLMGenerateParams(
            prompt: prompt,
            systemInstructions: systemInstructions,
            temperature: temperature,
            maxTokens: maxTokens
        )

        let result = try provider.generate(params: params)
        return result.toDict()
    }

    private func handleGenerateStructured(_ request: JsonRpcRequest) throws -> Any {
        let prompt = try request.requireString("prompt")

        guard let schemaValue = request.params?["schema"]?.dictValue else {
            throw JsonRpcError.invalidParams("Missing required param: schema")
        }

        let systemInstructions = request.string("system_instructions")
        let temperature = request.double("temperature")
        let maxTokens = request.int("max_tokens")

        let params = LLMGenerateStructuredParams(
            prompt: prompt,
            schema: schemaValue,
            systemInstructions: systemInstructions,
            temperature: temperature,
            maxTokens: maxTokens
        )

        let result = try provider.generateStructured(params: params)
        return result.toDict()
    }

    private func handleStream(_ request: JsonRpcRequest) throws -> Any {
        let prompt = try request.requireString("prompt")
        let systemInstructions = request.string("system_instructions")
        let temperature = request.double("temperature")
        let maxTokens = request.int("max_tokens")

        let params = LLMStreamParams(
            prompt: prompt,
            systemInstructions: systemInstructions,
            temperature: temperature,
            maxTokens: maxTokens
        )

        let requestId = request.id ?? "unknown"

        let result = try provider.stream(params: params) { [weak self] chunk in
            self?.notificationSink?.sendNotification(
                method: "llm.chunk",
                params: [
                    "request_id": requestId,
                    "chunk": chunk
                ]
            )
        }

        return result.toDict()
    }

    private func handleSessionCreate(_ request: JsonRpcRequest) throws -> Any {
        let sessionId = try request.requireString("session_id")
        let instructions = request.string("instructions")

        let params = LLMSessionCreateParams(
            sessionId: sessionId,
            instructions: instructions
        )

        try provider.sessionCreate(params: params)
        return ["ok": true] as [String: Any]
    }

    private func handleSessionRespond(_ request: JsonRpcRequest) throws -> Any {
        let sessionId = try request.requireString("session_id")
        let prompt = try request.requireString("prompt")
        let temperature = request.double("temperature")
        let maxTokens = request.int("max_tokens")

        let params = LLMSessionRespondParams(
            sessionId: sessionId,
            prompt: prompt,
            temperature: temperature,
            maxTokens: maxTokens
        )

        let result = try provider.sessionRespond(params: params)
        return result.toDict()
    }

    private func handleSessionClose(_ request: JsonRpcRequest) throws -> Any {
        let sessionId = try request.requireString("session_id")
        try provider.sessionClose(sessionId: sessionId)
        return ["ok": true] as [String: Any]
    }

    private func handleAvailable(_ request: JsonRpcRequest) throws -> Any {
        let result = provider.available()
        return result.toDict()
    }
}
```

### Step 2: Run tests to verify they pass

Run:
```bash
cd /Users/Martin/Tresors/Projects/darwinkit-swift/packages/darwinkit-swift && swift test --filter LLMHandlerTests 2>&1 | tail -20
```
Expected: All 20 tests PASS

### Step 3: Commit

```bash
git add packages/darwinkit-swift/Sources/DarwinKitCore/Handlers/LLMHandler.swift
git commit -m "feat(llm): implement LLMHandler routing all 7 llm.* methods"
```

---

## Task 4: Register LLMHandler in DarwinKit Entry Point

**Files:**
- Modify: `packages/darwinkit-swift/Sources/DarwinKit/DarwinKit.swift`

### Step 1: Add LLMHandler registration to both `buildServerWithRouter()` and `buildRouter()`

In `buildServerWithRouter()`, add after the `router.register(AuthHandler())` line:

```swift
    router.register(LLMHandler(provider: AppleLLMProvider(), notificationSink: server))
```

In `buildRouter()`, add after the `router.register(AuthHandler())` line:

```swift
    router.register(LLMHandler(provider: AppleLLMProvider()))
```

**Important:** `AppleLLMProvider` does not exist yet. It will be created in Task 5. For now, to keep the project building between commits, we temporarily use `MockLLMProvider()` instead. We will swap it to `AppleLLMProvider()` in Task 5.

In `buildServerWithRouter()`, after `router.register(AuthHandler())`:
```swift
    router.register(LLMHandler(provider: MockLLMProvider(), notificationSink: server))
```

In `buildRouter()`, after `router.register(AuthHandler())`:
```swift
    router.register(LLMHandler(provider: MockLLMProvider()))
```

### Step 2: Verify it compiles

Run:
```bash
cd /Users/Martin/Tresors/Projects/darwinkit-swift/packages/darwinkit-swift && swift build 2>&1 | tail -5
```
Expected: BUILD SUCCEEDED

### Step 3: Run all tests to check no regressions

Run:
```bash
cd /Users/Martin/Tresors/Projects/darwinkit-swift/packages/darwinkit-swift && swift test 2>&1 | tail -20
```
Expected: All tests pass

### Step 4: Commit

```bash
git add packages/darwinkit-swift/Sources/DarwinKit/DarwinKit.swift
git commit -m "feat(llm): register LLMHandler in server startup (mock provider for now)"
```

---

## Task 5: AppleLLMProvider (Real Implementation)

**Files:**
- Modify: `packages/darwinkit-swift/Sources/DarwinKitCore/Providers/LLMProvider.swift` (add AppleLLMProvider)
- Modify: `packages/darwinkit-swift/Sources/DarwinKit/DarwinKit.swift` (swap mock for real)

### Step 1: Add AppleLLMProvider to the bottom of LLMProvider.swift

This is the real implementation using `FoundationModels`. It is gated behind `#if canImport(FoundationModels)` and `@available(macOS 26, *)` so it compiles on older SDKs without the framework.

Append this to the bottom of `packages/darwinkit-swift/Sources/DarwinKitCore/Providers/LLMProvider.swift`:

```swift
// MARK: - Apple Implementation (macOS 26+)

#if canImport(FoundationModels)
import FoundationModels

@available(macOS 26, *)
public final class AppleLLMProvider: LLMProvider {
    private var sessions: [String: LanguageModelSession] = [:]

    public init() {}

    public func generate(params: LLMGenerateParams) throws -> LLMGenerateResult {
        let session = makeSession(instructions: params.systemInstructions)
        let options = makeOptions(temperature: params.temperature, maxTokens: params.maxTokens)

        let semaphore = DispatchSemaphore(value: 0)
        var resultText: String = ""
        var resultError: Error?

        Task {
            do {
                let response = try await session.respond(to: params.prompt, options: options)
                resultText = response.content
            } catch {
                resultError = error
            }
            semaphore.signal()
        }

        semaphore.wait()

        if let error = resultError {
            throw JsonRpcError.internalError("LLM generation failed: \(error.localizedDescription)")
        }

        return LLMGenerateResult(text: resultText)
    }

    public func generateStructured(params: LLMGenerateStructuredParams) throws -> LLMGenerateStructuredResult {
        // FoundationModels structured output requires @Generable types at compile time.
        // For dynamic JSON schemas, we generate text with a JSON instruction and parse it.
        let schemaJSON: String
        if let data = try? JSONSerialization.data(withJSONObject: params.schema, options: [.sortedKeys]),
           let str = String(data: data, encoding: .utf8) {
            schemaJSON = str
        } else {
            schemaJSON = "{}"
        }

        let augmentedPrompt = """
        \(params.prompt)

        Respond ONLY with valid JSON matching this schema:
        \(schemaJSON)
        """

        let session = makeSession(instructions: params.systemInstructions)
        let options = makeOptions(temperature: params.temperature, maxTokens: params.maxTokens)

        let semaphore = DispatchSemaphore(value: 0)
        var resultText: String = ""
        var resultError: Error?

        Task {
            do {
                let response = try await session.respond(to: augmentedPrompt, options: options)
                resultText = response.content
            } catch {
                resultError = error
            }
            semaphore.signal()
        }

        semaphore.wait()

        if let error = resultError {
            throw JsonRpcError.internalError("LLM structured generation failed: \(error.localizedDescription)")
        }

        // Parse the JSON from the response
        // Strip markdown code fences if present
        var jsonText = resultText.trimmingCharacters(in: .whitespacesAndNewlines)
        if jsonText.hasPrefix("```json") {
            jsonText = String(jsonText.dropFirst(7))
        } else if jsonText.hasPrefix("```") {
            jsonText = String(jsonText.dropFirst(3))
        }
        if jsonText.hasSuffix("```") {
            jsonText = String(jsonText.dropLast(3))
        }
        jsonText = jsonText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = jsonText.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw JsonRpcError.internalError("LLM response was not valid JSON: \(resultText)")
        }

        return LLMGenerateStructuredResult(json: json)
    }

    public func stream(params: LLMStreamParams, onChunk: @escaping (String) -> Void) throws -> LLMGenerateResult {
        let session = makeSession(instructions: params.systemInstructions)
        let options = makeOptions(temperature: params.temperature, maxTokens: params.maxTokens)

        let semaphore = DispatchSemaphore(value: 0)
        var fullText: String = ""
        var resultError: Error?

        Task {
            do {
                let stream = session.streamResponse(to: params.prompt, options: options)
                for try await partial in stream {
                    // Each partial contains the accumulated text so far
                    let newContent = String(partial.content.dropFirst(fullText.count))
                    if !newContent.isEmpty {
                        onChunk(newContent)
                    }
                    fullText = partial.content
                }
            } catch {
                resultError = error
            }
            semaphore.signal()
        }

        semaphore.wait()

        if let error = resultError {
            throw JsonRpcError.internalError("LLM stream failed: \(error.localizedDescription)")
        }

        return LLMGenerateResult(text: fullText)
    }

    public func sessionCreate(params: LLMSessionCreateParams) throws {
        guard sessions[params.sessionId] == nil else {
            throw JsonRpcError.invalidParams("Session already exists: \(params.sessionId)")
        }

        let session = makeSession(instructions: params.instructions)
        sessions[params.sessionId] = session
    }

    public func sessionRespond(params: LLMSessionRespondParams) throws -> LLMGenerateResult {
        guard let session = sessions[params.sessionId] else {
            throw JsonRpcError.invalidParams("No session with id: \(params.sessionId)")
        }

        let options = makeOptions(temperature: params.temperature, maxTokens: params.maxTokens)

        let semaphore = DispatchSemaphore(value: 0)
        var resultText: String = ""
        var resultError: Error?

        Task {
            do {
                let response = try await session.respond(to: params.prompt, options: options)
                resultText = response.content
            } catch {
                resultError = error
            }
            semaphore.signal()
        }

        semaphore.wait()

        if let error = resultError {
            throw JsonRpcError.internalError("LLM session respond failed: \(error.localizedDescription)")
        }

        return LLMGenerateResult(text: resultText)
    }

    public func sessionClose(sessionId: String) throws {
        guard sessions.removeValue(forKey: sessionId) != nil else {
            throw JsonRpcError.invalidParams("No session with id: \(sessionId)")
        }
    }

    public func available() -> LLMAvailabilityResult {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            return LLMAvailabilityResult(status: .available)
        case .unavailable(let reason):
            let reasonStr: String
            switch reason {
            case .deviceNotEligible:
                reasonStr = "Device not eligible for Apple Intelligence"
            case .appleIntelligenceNotEnabled:
                reasonStr = "Apple Intelligence is not enabled in System Settings"
            case .modelNotReady:
                reasonStr = "Model is not ready (may be downloading)"
            @unknown default:
                reasonStr = "Unavailable: \(reason)"
            }
            return LLMAvailabilityResult(status: .unavailable, reason: reasonStr)
        }
    }

    // MARK: - Private

    private func makeSession(instructions: String?) -> LanguageModelSession {
        if let instructions = instructions {
            return LanguageModelSession(instructions: instructions)
        }
        return LanguageModelSession()
    }

    private func makeOptions(temperature: Double?, maxTokens: Int?) -> GenerationOptions {
        var options = GenerationOptions()
        if let temp = temperature {
            options.temperature = temp
        }
        if let max = maxTokens {
            options.maximumResponseTokens = max
        }
        return options
    }
}
#else
// Fallback for SDKs without FoundationModels
public final class AppleLLMProvider: LLMProvider {
    public init() {}

    public func generate(params: LLMGenerateParams) throws -> LLMGenerateResult {
        throw JsonRpcError.osVersionTooOld("FoundationModels requires macOS 26+ (Tahoe)")
    }

    public func generateStructured(params: LLMGenerateStructuredParams) throws -> LLMGenerateStructuredResult {
        throw JsonRpcError.osVersionTooOld("FoundationModels requires macOS 26+ (Tahoe)")
    }

    public func stream(params: LLMStreamParams, onChunk: @escaping (String) -> Void) throws -> LLMGenerateResult {
        throw JsonRpcError.osVersionTooOld("FoundationModels requires macOS 26+ (Tahoe)")
    }

    public func sessionCreate(params: LLMSessionCreateParams) throws {
        throw JsonRpcError.osVersionTooOld("FoundationModels requires macOS 26+ (Tahoe)")
    }

    public func sessionRespond(params: LLMSessionRespondParams) throws -> LLMGenerateResult {
        throw JsonRpcError.osVersionTooOld("FoundationModels requires macOS 26+ (Tahoe)")
    }

    public func sessionClose(sessionId: String) throws {
        throw JsonRpcError.osVersionTooOld("FoundationModels requires macOS 26+ (Tahoe)")
    }

    public func available() -> LLMAvailabilityResult {
        return LLMAvailabilityResult(status: .unavailable, reason: "FoundationModels requires macOS 26+ (Tahoe)")
    }
}
#endif
```

### Step 2: Update DarwinKit.swift to use AppleLLMProvider

In `buildServerWithRouter()`, change:
```swift
    router.register(LLMHandler(provider: MockLLMProvider(), notificationSink: server))
```
to:
```swift
    router.register(LLMHandler(provider: AppleLLMProvider(), notificationSink: server))
```

In `buildRouter()`, change:
```swift
    router.register(LLMHandler(provider: MockLLMProvider()))
```
to:
```swift
    router.register(LLMHandler(provider: AppleLLMProvider()))
```

### Step 3: Verify it compiles

Run:
```bash
cd /Users/Martin/Tresors/Projects/darwinkit-swift/packages/darwinkit-swift && swift build 2>&1 | tail -5
```
Expected: BUILD SUCCEEDED. On SDKs without FoundationModels, the `#else` fallback compiles. On macOS 26+ SDK, the real implementation compiles.

### Step 4: Run all tests

Run:
```bash
cd /Users/Martin/Tresors/Projects/darwinkit-swift/packages/darwinkit-swift && swift test 2>&1 | tail -20
```
Expected: All tests pass (tests use `MockLLMProvider`, not the real one)

### Step 5: Commit

```bash
git add packages/darwinkit-swift/Sources/DarwinKitCore/Providers/LLMProvider.swift
git add packages/darwinkit-swift/Sources/DarwinKit/DarwinKit.swift
git commit -m "feat(llm): add AppleLLMProvider using FoundationModels (macOS 26+)"
```

---

## Task 6: TypeScript SDK Types

**Files:**
- Modify: `packages/darwinkit/src/types.ts`

### Step 1: Add LLM type definitions

Add the following block before the `// MethodMap` section (after the CoreML section, before the `// ---------------------------------------------------------------------------` / `// MethodMap` separator):

```typescript
// ---------------------------------------------------------------------------
// LLM (Foundation Models)
// ---------------------------------------------------------------------------

export interface LLMGenerateParams {
  prompt: string
  system_instructions?: string
  temperature?: number
  max_tokens?: number
}
export interface LLMGenerateResult {
  text: string
}

export interface LLMGenerateStructuredParams {
  prompt: string
  schema: Record<string, unknown>
  system_instructions?: string
  temperature?: number
  max_tokens?: number
}
export interface LLMGenerateStructuredResult {
  json: Record<string, unknown>
}

export interface LLMStreamParams {
  prompt: string
  system_instructions?: string
  temperature?: number
  max_tokens?: number
}

export interface LLMSessionCreateParams {
  session_id: string
  instructions?: string
}

export interface LLMSessionRespondParams {
  session_id: string
  prompt: string
  temperature?: number
  max_tokens?: number
}

export interface LLMSessionCloseParams {
  session_id: string
}

export interface LLMAvailableResult {
  available: boolean
  reason?: string
}

export interface LLMOkResult {
  ok: true
}

export interface LLMChunkNotification {
  request_id: string
  chunk: string
}
```

### Step 2: Add MethodMap entries

Inside the `MethodMap` interface, add after the `coreml.embed_contextual_batch` entry:

```typescript
  "llm.generate": {
    params: LLMGenerateParams
    result: LLMGenerateResult
  }
  "llm.generate_structured": {
    params: LLMGenerateStructuredParams
    result: LLMGenerateStructuredResult
  }
  "llm.stream": {
    params: LLMStreamParams
    result: LLMGenerateResult
  }
  "llm.session_create": {
    params: LLMSessionCreateParams
    result: LLMOkResult
  }
  "llm.session_respond": {
    params: LLMSessionRespondParams
    result: LLMGenerateResult
  }
  "llm.session_close": {
    params: LLMSessionCloseParams
    result: LLMOkResult
  }
  "llm.available": {
    params: Record<string, never>
    result: LLMAvailableResult
  }
```

### Step 3: Verify types compile

Run:
```bash
cd /Users/Martin/Tresors/Projects/darwinkit-swift/packages/darwinkit && bunx --bun tsc --noEmit 2>&1
```
Expected: No errors

### Step 4: Commit

```bash
git add packages/darwinkit/src/types.ts
git commit -m "feat(llm): add LLM type definitions and MethodMap entries to TS SDK"
```

---

## Task 7: TypeScript SDK Namespace

**Files:**
- Create: `packages/darwinkit/src/namespaces/llm.ts`

### Step 1: Create the LLM namespace class

This follows the exact pattern of `coreml.ts` and `nlp.ts`. The streaming method returns a promise for the final result, and exposes an `onChunk` listener mechanism for streaming tokens.

```typescript
import type { DarwinKitClient } from "../client.js"
import type {
  MethodMap,
  MethodName,
  PreparedCall,
  LLMGenerateParams,
  LLMGenerateResult,
  LLMGenerateStructuredParams,
  LLMGenerateStructuredResult,
  LLMStreamParams,
  LLMSessionCreateParams,
  LLMSessionRespondParams,
  LLMSessionCloseParams,
  LLMAvailableResult,
  LLMOkResult,
  LLMChunkNotification,
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

export class LLM {
  readonly generate: {
    (
      params: LLMGenerateParams,
      options?: { timeout?: number },
    ): Promise<LLMGenerateResult>
    prepare(params: LLMGenerateParams): PreparedCall<"llm.generate">
  }
  readonly generateStructured: {
    (
      params: LLMGenerateStructuredParams,
      options?: { timeout?: number },
    ): Promise<LLMGenerateStructuredResult>
    prepare(
      params: LLMGenerateStructuredParams,
    ): PreparedCall<"llm.generate_structured">
  }
  readonly sessionCreate: {
    (
      params: LLMSessionCreateParams,
      options?: { timeout?: number },
    ): Promise<LLMOkResult>
    prepare(
      params: LLMSessionCreateParams,
    ): PreparedCall<"llm.session_create">
  }
  readonly sessionRespond: {
    (
      params: LLMSessionRespondParams,
      options?: { timeout?: number },
    ): Promise<LLMGenerateResult>
    prepare(
      params: LLMSessionRespondParams,
    ): PreparedCall<"llm.session_respond">
  }
  readonly sessionClose: {
    (
      params: LLMSessionCloseParams,
      options?: { timeout?: number },
    ): Promise<LLMOkResult>
    prepare(
      params: LLMSessionCloseParams,
    ): PreparedCall<"llm.session_close">
  }

  private client: DarwinKitClient
  private chunkListeners: Array<(notification: LLMChunkNotification) => void> =
    []

  constructor(client: DarwinKitClient) {
    this.client = client
    this.generate = method(client, "llm.generate") as LLM["generate"]
    this.generateStructured = method(
      client,
      "llm.generate_structured",
    ) as LLM["generateStructured"]
    this.sessionCreate = method(
      client,
      "llm.session_create",
    ) as LLM["sessionCreate"]
    this.sessionRespond = method(
      client,
      "llm.session_respond",
    ) as LLM["sessionRespond"]
    this.sessionClose = method(
      client,
      "llm.session_close",
    ) as LLM["sessionClose"]
  }

  /** Check if Apple Intelligence / Foundation Models is available */
  available(options?: { timeout?: number }): Promise<LLMAvailableResult> {
    return this.client.call(
      "llm.available",
      {} as Record<string, never>,
      options,
    )
  }

  /**
   * Stream text generation. Returns the final complete result.
   * Use `onChunk()` to receive streaming tokens as they arrive.
   */
  stream(
    params: LLMStreamParams,
    options?: { timeout?: number },
  ): Promise<LLMGenerateResult> {
    return this.client.call("llm.stream", params, options)
  }

  /**
   * Register a listener for streaming chunk notifications.
   * Returns an unsubscribe function.
   */
  onChunk(
    handler: (notification: LLMChunkNotification) => void,
  ): () => void {
    this.chunkListeners.push(handler)
    return () => {
      const idx = this.chunkListeners.indexOf(handler)
      if (idx !== -1) this.chunkListeners.splice(idx, 1)
    }
  }

  /** @internal Called by DarwinKit client when llm.chunk notification arrives */
  _notifyChunk(notification: LLMChunkNotification): void {
    for (const handler of this.chunkListeners) {
      handler(notification)
    }
  }
}
```

### Step 2: Verify it compiles

Run:
```bash
cd /Users/Martin/Tresors/Projects/darwinkit-swift/packages/darwinkit && bunx --bun tsc --noEmit 2>&1
```
Expected: No errors

### Step 3: Commit

```bash
git add packages/darwinkit/src/namespaces/llm.ts
git commit -m "feat(llm): add LLM namespace class to TS SDK"
```

---

## Task 8: Wire LLM Namespace into TS Client + Events + Index

**Files:**
- Modify: `packages/darwinkit/src/client.ts`
- Modify: `packages/darwinkit/src/events.ts`
- Modify: `packages/darwinkit/src/index.ts`

### Step 1: Update events.ts

Add `llmChunk` event type. In the `DarwinKitEvent` union, add:

```typescript
  | { type: "llmChunk"; request_id: string; chunk: string }
```

In the `EventMap` interface, add:

```typescript
  llmChunk: { request_id: string; chunk: string }
```

The full `events.ts` should become:

```typescript
export type DarwinKitEvent =
  | { type: "ready"; version: string; capabilities: string[] }
  | { type: "filesChanged"; paths: string[] }
  | { type: "llmChunk"; request_id: string; chunk: string }
  | { type: "reconnect"; attempt: number }
  | { type: "disconnect"; code: number | null }
  | { type: "error"; error: Error }

export interface EventMap {
  ready: { version: string; capabilities: string[] }
  filesChanged: { paths: string[] }
  llmChunk: { request_id: string; chunk: string }
  reconnect: { attempt: number }
  disconnect: { code: number | null }
  error: { error: Error }
}

export type EventType = keyof EventMap
```

### Step 2: Update client.ts

Add the LLM import at the top, alongside the other namespace imports:

```typescript
import { LLM } from "./namespaces/llm.js"
```

Add the `llm` property in the `DarwinKit` class declaration (after `readonly coreml: CoreML`):

```typescript
  readonly llm: LLM
```

In the constructor, after `this.coreml = new CoreML(this)`:

```typescript
    this.llm = new LLM(this)
```

In the `handleLine` method, add notification handling for `llm.chunk` after the `icloud.files_changed` block:

```typescript
    // LLM streaming chunk notification
    if (msg.method === "llm.chunk") {
      const params = msg.params as { request_id: string; chunk: string }
      this.emit({ type: "llmChunk", request_id: params.request_id, chunk: params.chunk })
      this.llm._notifyChunk(params)
      return
    }
```

### Step 3: Update index.ts

Add the LLM export in the namespace exports section (after the CoreML line):

```typescript
export { LLM } from "./namespaces/llm.js"
```

Add LLM types to the type exports (after the CoreML types block):

```typescript
  // LLM
  LLMGenerateParams,
  LLMGenerateResult,
  LLMGenerateStructuredParams,
  LLMGenerateStructuredResult,
  LLMStreamParams,
  LLMSessionCreateParams,
  LLMSessionRespondParams,
  LLMSessionCloseParams,
  LLMAvailableResult,
  LLMOkResult,
  LLMChunkNotification,
```

### Step 4: Verify everything compiles

Run:
```bash
cd /Users/Martin/Tresors/Projects/darwinkit-swift/packages/darwinkit && bunx --bun tsc --noEmit 2>&1
```
Expected: No errors

### Step 5: Commit

```bash
git add packages/darwinkit/src/client.ts
git add packages/darwinkit/src/events.ts
git add packages/darwinkit/src/index.ts
git commit -m "feat(llm): wire LLM namespace into TS SDK client, events, and exports"
```

---

## Task 9: Full Test Suite Verification

### Step 1: Run all Swift tests

Run:
```bash
cd /Users/Martin/Tresors/Projects/darwinkit-swift/packages/darwinkit-swift && swift test 2>&1 | tail -30
```
Expected: All tests pass including the new LLMHandlerTests

### Step 2: Run TypeScript type check

Run:
```bash
cd /Users/Martin/Tresors/Projects/darwinkit-swift/packages/darwinkit && bunx --bun tsc --noEmit 2>&1
```
Expected: No type errors

### Step 3: Verify Swift build

Run:
```bash
cd /Users/Martin/Tresors/Projects/darwinkit-swift/packages/darwinkit-swift && swift build 2>&1 | tail -5
```
Expected: BUILD SUCCEEDED

---

## Summary of JSON-RPC Methods

| Method | Params | Result | Notes |
|--------|--------|--------|-------|
| `llm.available` | none | `{ available, reason? }` | Check Apple Intelligence availability |
| `llm.generate` | `{ prompt, system_instructions?, temperature?, max_tokens? }` | `{ text }` | Single-shot text generation |
| `llm.generate_structured` | `{ prompt, schema, system_instructions?, temperature?, max_tokens? }` | `{ json }` | Generate JSON matching schema |
| `llm.stream` | `{ prompt, system_instructions?, temperature?, max_tokens? }` | `{ text }` | Stream via `llm.chunk` notifications, final result returned |
| `llm.session_create` | `{ session_id, instructions? }` | `{ ok }` | Create named multi-turn session |
| `llm.session_respond` | `{ session_id, prompt, temperature?, max_tokens? }` | `{ text }` | Send message to existing session |
| `llm.session_close` | `{ session_id }` | `{ ok }` | Close and free session |

## Streaming Protocol

When `llm.stream` is called, the server sends JSON-RPC notifications during generation:

```json
{"jsonrpc":"2.0","method":"llm.chunk","params":{"request_id":"42","chunk":"Hello"}}
{"jsonrpc":"2.0","method":"llm.chunk","params":{"request_id":"42","chunk":" world"}}
```

Then the final JSON-RPC response is sent as usual:

```json
{"jsonrpc":"2.0","id":"42","result":{"text":"Hello world"}}
```

TS SDK usage:

```typescript
const dk = new DarwinKit()
await dk.connect()

// Register chunk listener before calling stream
const unsub = dk.llm.onChunk(({ request_id, chunk }) => {
  process.stdout.write(chunk)
})

const result = await dk.llm.stream({ prompt: "Tell me a story" })
unsub()
console.log("\nFinal:", result.text)
```
