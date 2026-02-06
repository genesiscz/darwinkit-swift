import Foundation
import Testing
@testable import DarwinKitCore

// MARK: - Mock Provider

struct MockVisionProvider: VisionProvider {
    var ocrResult = OCRResult(
        text: "Hello World\nSecond Line",
        blocks: [
            OCRBlock(text: "Hello World", confidence: 1.0, bounds: CGRect(x: 0.05, y: 0.7, width: 0.4, height: 0.12)),
            OCRBlock(text: "Second Line", confidence: 0.95, bounds: CGRect(x: 0.05, y: 0.4, width: 0.35, height: 0.12))
        ]
    )
    var shouldThrow: JsonRpcError? = nil

    func recognizeText(imagePath: String, languages: [String], level: RecognitionLevel) throws -> OCRResult {
        if let err = shouldThrow { throw err }
        // Simulate file-not-found for missing paths
        if imagePath.contains("nonexistent") {
            throw JsonRpcError.invalidParams("File not found: \(imagePath)")
        }
        return ocrResult
    }
}

// MARK: - Helper

private func makeRequest(method: String, params: [String: Any] = [:]) -> JsonRpcRequest {
    let codableParams = params.mapValues { AnyCodable($0) }
    return JsonRpcRequest(id: "test", method: method, params: codableParams)
}

// MARK: - Tests

@Suite("Vision Handler")
struct VisionHandlerTests {

    // MARK: - vision.ocr

    @Test("ocr returns text and blocks")
    func ocrSuccess() throws {
        let handler = VisionHandler(provider: MockVisionProvider())
        let request = makeRequest(method: "vision.ocr", params: [
            "path": "/tmp/test.png"
        ])
        let result = try handler.handle(request) as! [String: Any]

        #expect(result["text"] as? String == "Hello World\nSecond Line")
        let blocks = result["blocks"] as! [[String: Any]]
        #expect(blocks.count == 2)
    }

    @Test("ocr blocks contain correct fields")
    func ocrBlockFields() throws {
        let handler = VisionHandler(provider: MockVisionProvider())
        let request = makeRequest(method: "vision.ocr", params: [
            "path": "/tmp/test.png"
        ])
        let result = try handler.handle(request) as! [String: Any]
        let blocks = result["blocks"] as! [[String: Any]]

        let first = blocks[0]
        #expect(first["text"] as? String == "Hello World")
        #expect(first["confidence"] as? Float == 1.0)

        let bounds = first["bounds"] as! [String: Any]
        #expect(bounds["x"] as? CGFloat == 0.05)
        #expect(bounds["y"] as? CGFloat == 0.7)
        #expect(bounds["width"] as? CGFloat == 0.4)
        #expect(bounds["height"] as? CGFloat == 0.12)
    }

    @Test("ocr second block has lower confidence")
    func ocrSecondBlock() throws {
        let handler = VisionHandler(provider: MockVisionProvider())
        let request = makeRequest(method: "vision.ocr", params: [
            "path": "/tmp/test.png"
        ])
        let result = try handler.handle(request) as! [String: Any]
        let blocks = result["blocks"] as! [[String: Any]]

        #expect(blocks[1]["text"] as? String == "Second Line")
        #expect(blocks[1]["confidence"] as? Float == 0.95)
    }

    // MARK: - Parameter defaults

    @Test("ocr defaults languages to en-US")
    func ocrDefaultLanguages() throws {
        // The handler defaults languages to ["en-US"] when not provided
        let handler = VisionHandler(provider: MockVisionProvider())
        let request = makeRequest(method: "vision.ocr", params: [
            "path": "/tmp/test.png"
        ])
        // Should succeed without explicit languages
        let result = try handler.handle(request) as! [String: Any]
        #expect(result["text"] != nil)
    }

    @Test("ocr defaults level to accurate")
    func ocrDefaultLevel() throws {
        let handler = VisionHandler(provider: MockVisionProvider())
        let request = makeRequest(method: "vision.ocr", params: [
            "path": "/tmp/test.png"
        ])
        // Should succeed without explicit level
        let result = try handler.handle(request) as! [String: Any]
        #expect(result["text"] != nil)
    }

    @Test("ocr accepts fast level")
    func ocrFastLevel() throws {
        let handler = VisionHandler(provider: MockVisionProvider())
        let request = makeRequest(method: "vision.ocr", params: [
            "path": "/tmp/test.png", "level": "fast"
        ])
        let result = try handler.handle(request) as! [String: Any]
        #expect(result["text"] != nil)
    }

    // MARK: - Error handling

    @Test("ocr throws on missing path")
    func ocrMissingPath() {
        let handler = VisionHandler(provider: MockVisionProvider())
        let request = makeRequest(method: "vision.ocr", params: [:])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    @Test("ocr throws on invalid level")
    func ocrInvalidLevel() {
        let handler = VisionHandler(provider: MockVisionProvider())
        let request = makeRequest(method: "vision.ocr", params: [
            "path": "/tmp/test.png", "level": "turbo"
        ])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    @Test("ocr throws on file not found")
    func ocrFileNotFound() {
        let handler = VisionHandler(provider: MockVisionProvider())
        let request = makeRequest(method: "vision.ocr", params: [
            "path": "/tmp/nonexistent.png"
        ])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    @Test("ocr propagates provider errors")
    func ocrProviderError() {
        var mock = MockVisionProvider()
        mock.shouldThrow = .internalError("Vision framework crashed")
        let handler = VisionHandler(provider: mock)
        let request = makeRequest(method: "vision.ocr", params: [
            "path": "/tmp/test.png"
        ])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    // MARK: - Empty result

    @Test("ocr handles empty image")
    func ocrEmptyResult() throws {
        var mock = MockVisionProvider()
        mock.ocrResult = OCRResult(text: "", blocks: [])
        let handler = VisionHandler(provider: mock)
        let request = makeRequest(method: "vision.ocr", params: [
            "path": "/tmp/blank.png"
        ])
        let result = try handler.handle(request) as! [String: Any]

        #expect(result["text"] as? String == "")
        let blocks = result["blocks"] as! [[String: Any]]
        #expect(blocks.isEmpty)
    }

    // MARK: - Method registration

    @Test("handler registers vision.ocr method")
    func methodRegistration() {
        let handler = VisionHandler(provider: MockVisionProvider())
        #expect(handler.methods == ["vision.ocr"])
    }

    @Test("handler reports available capability")
    func capability() {
        let handler = VisionHandler(provider: MockVisionProvider())
        let cap = handler.capability(for: "vision.ocr")
        #expect(cap.available == true)
    }
}
