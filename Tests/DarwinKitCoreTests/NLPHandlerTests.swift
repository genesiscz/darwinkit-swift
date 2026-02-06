import Foundation
import NaturalLanguage
import Testing
@testable import DarwinKitCore

// MARK: - Mock Provider

struct MockNLPProvider: NLPProvider {
    var embedResult: [Double] = [0.1, 0.2, 0.3]
    var distanceResult: Double = 0.5
    var neighborsResult: [(String, Double)] = [("neighbor1", 0.1), ("neighbor2", 0.2)]
    var tagResult: [[String: Any]] = [
        ["text": "Hello", "tags": ["lexicalClass": "Interjection"]],
        ["text": "world", "tags": ["lexicalClass": "Noun"]]
    ]
    var sentimentResult: Double = 0.8
    var languageResult: (String, Double) = ("en", 0.99)
    var shouldThrow: JsonRpcError? = nil

    func embed(text: String, language: NLLanguage, type: EmbedType) throws -> [Double] {
        if let err = shouldThrow { throw err }
        return embedResult
    }

    func distance(text1: String, text2: String, language: NLLanguage, type: EmbedType) throws -> Double {
        if let err = shouldThrow { throw err }
        return distanceResult
    }

    func neighbors(text: String, language: NLLanguage, type: EmbedType, count: Int) throws -> [(String, Double)] {
        if let err = shouldThrow { throw err }
        return Array(neighborsResult.prefix(count))
    }

    func tag(text: String, language: NLLanguage?, schemes: [NLTagScheme]) throws -> [[String: Any]] {
        if let err = shouldThrow { throw err }
        return tagResult
    }

    func sentiment(text: String) throws -> Double {
        if let err = shouldThrow { throw err }
        return sentimentResult
    }

    func detectLanguage(text: String) throws -> (String, Double) {
        if let err = shouldThrow { throw err }
        return languageResult
    }

    func supportedEmbeddingLanguages() -> [String] {
        ["en", "es", "fr"]
    }
}

// MARK: - Helper

private func makeRequest(method: String, params: [String: Any] = [:]) -> JsonRpcRequest {
    let codableParams = params.mapValues { AnyCodable($0) }
    return JsonRpcRequest(id: "test", method: method, params: codableParams)
}

// MARK: - Tests

@Suite("NLP Handler")
struct NLPHandlerTests {

    // MARK: - nlp.embed

    @Test("embed returns vector and dimension")
    func embedSuccess() throws {
        let handler = NLPHandler(provider: MockNLPProvider())
        let request = makeRequest(method: "nlp.embed", params: [
            "text": "hello", "language": "en", "type": "sentence"
        ])
        let result = try handler.handle(request) as! [String: Any]

        #expect(result["vector"] as? [Double] == [0.1, 0.2, 0.3])
        #expect(result["dimension"] as? Int == 3)
    }

    @Test("embed throws on missing text")
    func embedMissingText() {
        let handler = NLPHandler(provider: MockNLPProvider())
        let request = makeRequest(method: "nlp.embed", params: ["language": "en"])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    @Test("embed throws on missing language")
    func embedMissingLanguage() {
        let handler = NLPHandler(provider: MockNLPProvider())
        let request = makeRequest(method: "nlp.embed", params: ["text": "hello"])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    @Test("embed throws on invalid type")
    func embedInvalidType() {
        let handler = NLPHandler(provider: MockNLPProvider())
        let request = makeRequest(method: "nlp.embed", params: [
            "text": "hello", "language": "en", "type": "invalid"
        ])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    @Test("embed defaults type to sentence")
    func embedDefaultType() throws {
        let handler = NLPHandler(provider: MockNLPProvider())
        let request = makeRequest(method: "nlp.embed", params: [
            "text": "hello", "language": "en"
        ])
        // Should not throw — defaults to "sentence"
        let result = try handler.handle(request) as! [String: Any]
        #expect(result["dimension"] as? Int == 3)
    }

    // MARK: - nlp.distance

    @Test("distance returns cosine distance")
    func distanceSuccess() throws {
        let handler = NLPHandler(provider: MockNLPProvider())
        let request = makeRequest(method: "nlp.distance", params: [
            "text1": "cat", "text2": "dog", "language": "en"
        ])
        let result = try handler.handle(request) as! [String: Any]

        #expect(result["distance"] as? Double == 0.5)
        #expect(result["type"] as? String == "cosine")
    }

    @Test("distance throws on missing text1")
    func distanceMissingText1() {
        let handler = NLPHandler(provider: MockNLPProvider())
        let request = makeRequest(method: "nlp.distance", params: [
            "text2": "dog", "language": "en"
        ])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    // MARK: - nlp.neighbors

    @Test("neighbors returns array with distance")
    func neighborsSuccess() throws {
        let handler = NLPHandler(provider: MockNLPProvider())
        let request = makeRequest(method: "nlp.neighbors", params: [
            "text": "cat", "language": "en", "count": 2
        ])
        let result = try handler.handle(request) as! [String: Any]
        let neighbors = result["neighbors"] as! [[String: Any]]

        #expect(neighbors.count == 2)
        #expect(neighbors[0]["text"] as? String == "neighbor1")
        #expect(neighbors[0]["distance"] as? Double == 0.1)
    }

    @Test("neighbors defaults count to 5")
    func neighborsDefaultCount() throws {
        var mock = MockNLPProvider()
        mock.neighborsResult = (0..<10).map { ("word\($0)", Double($0) * 0.1) }
        let handler = NLPHandler(provider: mock)
        let request = makeRequest(method: "nlp.neighbors", params: [
            "text": "cat", "language": "en"
        ])
        let result = try handler.handle(request) as! [String: Any]
        let neighbors = result["neighbors"] as! [[String: Any]]

        #expect(neighbors.count == 5) // default count
    }

    // MARK: - nlp.tag

    @Test("tag returns tokens with tags")
    func tagSuccess() throws {
        let handler = NLPHandler(provider: MockNLPProvider())
        let request = makeRequest(method: "nlp.tag", params: ["text": "Hello world"])
        let result = try handler.handle(request) as! [String: Any]
        let tokens = result["tokens"] as! [[String: Any]]

        #expect(tokens.count == 2)
        #expect(tokens[0]["text"] as? String == "Hello")
    }

    @Test("tag throws on invalid scheme")
    func tagInvalidScheme() {
        let handler = NLPHandler(provider: MockNLPProvider())
        let request = makeRequest(method: "nlp.tag", params: [
            "text": "Hello", "schemes": ["nonexistent"]
        ])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    @Test("tag defaults to lexicalClass scheme")
    func tagDefaultScheme() throws {
        let handler = NLPHandler(provider: MockNLPProvider())
        let request = makeRequest(method: "nlp.tag", params: ["text": "Hello world"])
        // Should not throw — defaults to ["lexicalClass"]
        let result = try handler.handle(request) as! [String: Any]
        #expect(result["tokens"] != nil)
    }

    // MARK: - nlp.sentiment

    @Test("sentiment returns score and label")
    func sentimentPositive() throws {
        var mock = MockNLPProvider()
        mock.sentimentResult = 0.8
        let handler = NLPHandler(provider: mock)
        let request = makeRequest(method: "nlp.sentiment", params: ["text": "I love this"])
        let result = try handler.handle(request) as! [String: Any]

        #expect(result["score"] as? Double == 0.8)
        #expect(result["label"] as? String == "positive")
    }

    @Test("sentiment returns negative label")
    func sentimentNegative() throws {
        var mock = MockNLPProvider()
        mock.sentimentResult = -0.5
        let handler = NLPHandler(provider: mock)
        let request = makeRequest(method: "nlp.sentiment", params: ["text": "I hate this"])
        let result = try handler.handle(request) as! [String: Any]

        #expect(result["score"] as? Double == -0.5)
        #expect(result["label"] as? String == "negative")
    }

    @Test("sentiment returns neutral label")
    func sentimentNeutral() throws {
        var mock = MockNLPProvider()
        mock.sentimentResult = 0.05
        let handler = NLPHandler(provider: mock)
        let request = makeRequest(method: "nlp.sentiment", params: ["text": "It exists"])
        let result = try handler.handle(request) as! [String: Any]

        #expect(result["score"] as? Double == 0.05)
        #expect(result["label"] as? String == "neutral")
    }

    // MARK: - nlp.language

    @Test("language returns detected language and confidence")
    func languageSuccess() throws {
        let handler = NLPHandler(provider: MockNLPProvider())
        let request = makeRequest(method: "nlp.language", params: ["text": "Hello world"])
        let result = try handler.handle(request) as! [String: Any]

        #expect(result["language"] as? String == "en")
        #expect(result["confidence"] as? Double == 0.99)
    }

    // MARK: - Method registration

    @Test("handler registers all 6 NLP methods")
    func methodRegistration() {
        let handler = NLPHandler(provider: MockNLPProvider())
        let expected: Set<String> = [
            "nlp.embed", "nlp.distance", "nlp.neighbors",
            "nlp.tag", "nlp.sentiment", "nlp.language"
        ]
        #expect(Set(handler.methods) == expected)
    }

    @Test("handler reports capabilities for all methods")
    func capabilities() {
        let handler = NLPHandler(provider: MockNLPProvider())
        for method in handler.methods {
            let cap = handler.capability(for: method)
            #expect(cap.available == true)
        }
    }

    // MARK: - Unknown method dispatch

    @Test("handler throws on unknown method via router")
    func unknownMethod() {
        let router = MethodRouter()
        router.register(NLPHandler(provider: MockNLPProvider()))
        let request = makeRequest(method: "nlp.nonexistent")

        #expect(throws: JsonRpcError.self) {
            try router.dispatch(request)
        }
    }

    // MARK: - Provider error propagation

    @Test("provider errors propagate through handler")
    func providerError() {
        var mock = MockNLPProvider()
        mock.shouldThrow = .frameworkUnavailable("No embedding for xx")
        let handler = NLPHandler(provider: mock)
        let request = makeRequest(method: "nlp.embed", params: [
            "text": "hello", "language": "xx"
        ])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }
}
