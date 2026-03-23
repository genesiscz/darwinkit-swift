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

/// Factory: returns AppleLLMProvider on macOS 26+, StubLLMProvider otherwise.
public func makeDefaultLLMProvider() -> LLMProvider {
    if #available(macOS 26, *) {
        return AppleLLMProvider()
    } else {
        return StubLLMProvider()
    }
}
#else
// When SDK lacks FoundationModels, AppleLLMProvider is a stub.
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

/// Factory: returns AppleLLMProvider (stub) when SDK has no FoundationModels.
public func makeDefaultLLMProvider() -> LLMProvider {
    return AppleLLMProvider()
}
#endif

// MARK: - Stub Provider (runtime fallback when SDK available but OS version too old)

/// Stub provider that always reports unavailable. Used at runtime on older macOS
/// when the SDK has FoundationModels but the OS does not meet the minimum version.
public final class StubLLMProvider: LLMProvider {
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
