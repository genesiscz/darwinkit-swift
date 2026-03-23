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
