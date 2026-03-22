import Foundation
import Testing
@testable import DarwinKitCore

// MARK: - Mock Provider

struct MockSoundProvider: SoundProvider {
    var classifyResult = SoundClassifyResult(
        classifications: [
            SoundClassification(identifier: "speech", confidence: 0.92),
            SoundClassification(identifier: "music", confidence: 0.05),
            SoundClassification(identifier: "silence", confidence: 0.03),
        ]
    )
    var classifyAtResult = SoundClassifyResult(
        classifications: [
            SoundClassification(identifier: "laughter", confidence: 0.85),
            SoundClassification(identifier: "speech", confidence: 0.10),
        ],
        timeRange: SoundTimeRange(start: 2.0, duration: 1.5)
    )
    var categoriesResult: [String] = ["speech", "music", "laughter", "applause", "siren"]
    var available: Bool = true
    var shouldThrow: JsonRpcError? = nil

    func classify(path: String, topN: Int) throws -> SoundClassifyResult {
        if let err = shouldThrow { throw err }
        if path.contains("nonexistent") {
            throw JsonRpcError.invalidParams("File not found: \(path)")
        }
        let limited = Array(classifyResult.classifications.prefix(topN))
        return SoundClassifyResult(classifications: limited)
    }

    func classifyAt(path: String, start: Double, duration: Double, topN: Int) throws -> SoundClassifyResult {
        if let err = shouldThrow { throw err }
        if path.contains("nonexistent") {
            throw JsonRpcError.invalidParams("File not found: \(path)")
        }
        let limited = Array(classifyAtResult.classifications.prefix(topN))
        return SoundClassifyResult(
            classifications: limited,
            timeRange: SoundTimeRange(start: start, duration: duration)
        )
    }

    func categories() throws -> [String] {
        if let err = shouldThrow { throw err }
        return categoriesResult
    }

    func isAvailable() -> Bool {
        available
    }
}

// MARK: - Helper

private func makeRequest(method: String, params: [String: Any] = [:]) -> JsonRpcRequest {
    let codableParams = params.mapValues { AnyCodable($0) }
    return JsonRpcRequest(id: "test", method: method, params: codableParams)
}

// MARK: - Tests

@Suite("Sound Handler")
struct SoundHandlerTests {

    // MARK: - sound.classify

    @Test("classify returns classifications array")
    func classifySuccess() throws {
        let handler = SoundHandler(provider: MockSoundProvider())
        let request = makeRequest(method: "sound.classify", params: [
            "path": "/tmp/test.wav"
        ])
        let result = try handler.handle(request) as! [String: Any]
        let classifications = result["classifications"] as! [[String: Any]]

        #expect(classifications.count == 3)
        #expect(classifications[0]["identifier"] as? String == "speech")
        #expect(classifications[0]["confidence"] as? Double == 0.92)
    }

    @Test("classify respects top_n parameter")
    func classifyTopN() throws {
        let handler = SoundHandler(provider: MockSoundProvider())
        let request = makeRequest(method: "sound.classify", params: [
            "path": "/tmp/test.wav", "top_n": 1
        ])
        let result = try handler.handle(request) as! [String: Any]
        let classifications = result["classifications"] as! [[String: Any]]

        #expect(classifications.count == 1)
    }

    @Test("classify defaults top_n to 5")
    func classifyDefaultTopN() throws {
        let handler = SoundHandler(provider: MockSoundProvider())
        let request = makeRequest(method: "sound.classify", params: [
            "path": "/tmp/test.wav"
        ])
        // Should succeed with default top_n=5 (mock has 3, so all 3 returned)
        let result = try handler.handle(request) as! [String: Any]
        let classifications = result["classifications"] as! [[String: Any]]
        #expect(classifications.count == 3)
    }

    @Test("classify throws on missing path")
    func classifyMissingPath() {
        let handler = SoundHandler(provider: MockSoundProvider())
        let request = makeRequest(method: "sound.classify", params: [:])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    @Test("classify throws on file not found")
    func classifyFileNotFound() {
        let handler = SoundHandler(provider: MockSoundProvider())
        let request = makeRequest(method: "sound.classify", params: [
            "path": "/tmp/nonexistent.wav"
        ])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    // MARK: - sound.classify_at

    @Test("classify_at returns classifications with time_range")
    func classifyAtSuccess() throws {
        let handler = SoundHandler(provider: MockSoundProvider())
        let request = makeRequest(method: "sound.classify_at", params: [
            "path": "/tmp/test.wav", "start": 2.0, "duration": 1.5
        ])
        let result = try handler.handle(request) as! [String: Any]
        let classifications = result["classifications"] as! [[String: Any]]
        let timeRange = result["time_range"] as! [String: Any]

        #expect(classifications.count == 2)
        #expect(classifications[0]["identifier"] as? String == "laughter")
        #expect(timeRange["start"] as? Double == 2.0)
        #expect(timeRange["duration"] as? Double == 1.5)
    }

    @Test("classify_at respects top_n parameter")
    func classifyAtTopN() throws {
        let handler = SoundHandler(provider: MockSoundProvider())
        let request = makeRequest(method: "sound.classify_at", params: [
            "path": "/tmp/test.wav", "start": 0.0, "duration": 1.0, "top_n": 1
        ])
        let result = try handler.handle(request) as! [String: Any]
        let classifications = result["classifications"] as! [[String: Any]]

        #expect(classifications.count == 1)
    }

    @Test("classify_at throws on missing path")
    func classifyAtMissingPath() {
        let handler = SoundHandler(provider: MockSoundProvider())
        let request = makeRequest(method: "sound.classify_at", params: [
            "start": 0.0, "duration": 1.0
        ])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    @Test("classify_at throws on missing start")
    func classifyAtMissingStart() {
        let handler = SoundHandler(provider: MockSoundProvider())
        let request = makeRequest(method: "sound.classify_at", params: [
            "path": "/tmp/test.wav", "duration": 1.0
        ])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    @Test("classify_at throws on missing duration")
    func classifyAtMissingDuration() {
        let handler = SoundHandler(provider: MockSoundProvider())
        let request = makeRequest(method: "sound.classify_at", params: [
            "path": "/tmp/test.wav", "start": 0.0
        ])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    // MARK: - sound.categories

    @Test("categories returns list of category strings")
    func categoriesSuccess() throws {
        let handler = SoundHandler(provider: MockSoundProvider())
        let request = makeRequest(method: "sound.categories")
        let result = try handler.handle(request) as! [String: Any]
        let categories = result["categories"] as! [String]

        #expect(categories.count == 5)
        #expect(categories.contains("speech"))
        #expect(categories.contains("music"))
    }

    // MARK: - sound.available

    @Test("available returns true when framework is available")
    func availableTrue() throws {
        let handler = SoundHandler(provider: MockSoundProvider())
        let request = makeRequest(method: "sound.available")
        let result = try handler.handle(request) as! [String: Any]

        #expect(result["available"] as? Bool == true)
    }

    @Test("available returns false when framework is unavailable")
    func availableFalse() throws {
        var mock = MockSoundProvider()
        mock.available = false
        let handler = SoundHandler(provider: mock)
        let request = makeRequest(method: "sound.available")
        let result = try handler.handle(request) as! [String: Any]

        #expect(result["available"] as? Bool == false)
    }

    // MARK: - Method registration

    @Test("handler registers all 4 sound methods")
    func methodRegistration() {
        let handler = SoundHandler(provider: MockSoundProvider())
        let expected: Set<String> = [
            "sound.classify", "sound.classify_at",
            "sound.categories", "sound.available"
        ]

        #expect(Set(handler.methods) == expected)
    }

    @Test("handler reports capabilities for all methods")
    func capabilities() {
        let handler = SoundHandler(provider: MockSoundProvider())
        for method in handler.methods {
            let cap = handler.capability(for: method)
            #expect(cap.available == true)
        }
    }

    // MARK: - Provider error propagation

    @Test("provider errors propagate through handler")
    func providerError() {
        var mock = MockSoundProvider()
        mock.shouldThrow = .frameworkUnavailable("SoundAnalysis not available")
        let handler = SoundHandler(provider: mock)
        let request = makeRequest(method: "sound.classify", params: [
            "path": "/tmp/test.wav"
        ])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }
}
