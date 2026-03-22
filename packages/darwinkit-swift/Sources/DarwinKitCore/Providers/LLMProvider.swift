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
