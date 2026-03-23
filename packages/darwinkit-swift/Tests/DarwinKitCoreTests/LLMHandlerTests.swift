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
