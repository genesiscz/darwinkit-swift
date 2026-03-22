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
    var classifyResult = ClassifyResult(classifications: [
        ClassificationItem(identifier: "cat", confidence: 0.95),
        ClassificationItem(identifier: "animal", confidence: 0.88),
        ClassificationItem(identifier: "pet", confidence: 0.72)
    ])
    var featurePrintResult = FeaturePrintResult(
        vector: [0.1, 0.2, 0.3, 0.4, 0.5],
        dimensions: 5
    )
    var similarityResult = SimilarityResult(distance: 12.5)
    var detectFacesResult = DetectFacesResult(faces: [
        FaceObservation(
            bounds: FaceBounds(x: 0.2, y: 0.3, width: 0.3, height: 0.4),
            confidence: 0.99,
            landmarks: nil
        )
    ])
    var detectFacesWithLandmarksResult = DetectFacesResult(faces: [
        FaceObservation(
            bounds: FaceBounds(x: 0.2, y: 0.3, width: 0.3, height: 0.4),
            confidence: 0.99,
            landmarks: FaceLandmarks(
                leftEye: FaceLandmarkPoints(points: [[0.3, 0.6], [0.35, 0.6]]),
                rightEye: FaceLandmarkPoints(points: [[0.5, 0.6], [0.55, 0.6]]),
                nose: FaceLandmarkPoints(points: [[0.4, 0.5]]),
                mouth: FaceLandmarkPoints(points: [[0.35, 0.4], [0.45, 0.4]]),
                faceContour: FaceLandmarkPoints(points: [[0.2, 0.3], [0.5, 0.3]])
            )
        )
    ])
    var detectBarcodesResult = DetectBarcodesResult(barcodes: [
        BarcodeObservation(
            payload: "https://example.com",
            symbology: "VNBarcodeSymbologyQR",
            bounds: FaceBounds(x: 0.1, y: 0.1, width: 0.3, height: 0.3)
        )
    ])
    var saliencyResult = SaliencyResult(type: .attention, regions: [
        SaliencyRegion(
            bounds: FaceBounds(x: 0.2, y: 0.2, width: 0.6, height: 0.6),
            confidence: 0.85
        )
    ])

    func recognizeText(imagePath: String, languages: [String], level: RecognitionLevel) throws -> OCRResult {
        if let err = shouldThrow { throw err }
        // Simulate file-not-found for missing paths
        if imagePath.contains("nonexistent") {
            throw JsonRpcError.invalidParams("File not found: \(imagePath)")
        }
        return ocrResult
    }

    func classifyImage(imagePath: String, maxResults: Int) throws -> ClassifyResult {
        if let err = shouldThrow { throw err }
        if imagePath.contains("nonexistent") {
            throw JsonRpcError.invalidParams("File not found: \(imagePath)")
        }
        let limited = Array(classifyResult.classifications.prefix(maxResults))
        return ClassifyResult(classifications: limited)
    }

    func generateFeaturePrint(imagePath: String) throws -> FeaturePrintResult {
        if let err = shouldThrow { throw err }
        if imagePath.contains("nonexistent") {
            throw JsonRpcError.invalidParams("File not found: \(imagePath)")
        }
        return featurePrintResult
    }

    func computeSimilarity(imagePath1: String, imagePath2: String) throws -> SimilarityResult {
        if let err = shouldThrow { throw err }
        if imagePath1.contains("nonexistent") || imagePath2.contains("nonexistent") {
            throw JsonRpcError.invalidParams("File not found")
        }
        return similarityResult
    }

    func detectFaces(imagePath: String, withLandmarks: Bool) throws -> DetectFacesResult {
        if let err = shouldThrow { throw err }
        if imagePath.contains("nonexistent") {
            throw JsonRpcError.invalidParams("File not found: \(imagePath)")
        }
        return withLandmarks ? detectFacesWithLandmarksResult : detectFacesResult
    }

    func detectBarcodes(imagePath: String, symbologies: [String]?) throws -> DetectBarcodesResult {
        if let err = shouldThrow { throw err }
        if imagePath.contains("nonexistent") {
            throw JsonRpcError.invalidParams("File not found: \(imagePath)")
        }
        return detectBarcodesResult
    }

    func detectSaliency(imagePath: String, type: SaliencyType) throws -> SaliencyResult {
        if let err = shouldThrow { throw err }
        if imagePath.contains("nonexistent") {
            throw JsonRpcError.invalidParams("File not found: \(imagePath)")
        }
        return SaliencyResult(type: type, regions: saliencyResult.regions)
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

    // MARK: - vision.classify

    @Test("classify returns classifications with identifiers and confidence")
    func classifySuccess() throws {
        let handler = VisionHandler(provider: MockVisionProvider())
        let request = makeRequest(method: "vision.classify", params: [
            "path": "/tmp/cat.jpg"
        ])
        let result = try handler.handle(request) as! [String: Any]
        let classifications = result["classifications"] as! [[String: Any]]

        #expect(classifications.count == 3)
        #expect(classifications[0]["identifier"] as? String == "cat")
        #expect(classifications[0]["confidence"] as? Float == 0.95)
    }

    @Test("classify respects max_results param")
    func classifyMaxResults() throws {
        let handler = VisionHandler(provider: MockVisionProvider())
        let request = makeRequest(method: "vision.classify", params: [
            "path": "/tmp/cat.jpg", "max_results": 2
        ])
        let result = try handler.handle(request) as! [String: Any]
        let classifications = result["classifications"] as! [[String: Any]]

        #expect(classifications.count == 2)
    }

    @Test("classify defaults max_results to 10")
    func classifyDefaultMaxResults() throws {
        let handler = VisionHandler(provider: MockVisionProvider())
        let request = makeRequest(method: "vision.classify", params: [
            "path": "/tmp/cat.jpg"
        ])
        let result = try handler.handle(request) as! [String: Any]
        let classifications = result["classifications"] as! [[String: Any]]
        #expect(classifications.count == 3)
    }

    @Test("classify throws on missing path")
    func classifyMissingPath() {
        let handler = VisionHandler(provider: MockVisionProvider())
        let request = makeRequest(method: "vision.classify", params: [:])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    @Test("classify throws on file not found")
    func classifyFileNotFound() {
        let handler = VisionHandler(provider: MockVisionProvider())
        let request = makeRequest(method: "vision.classify", params: [
            "path": "/tmp/nonexistent.jpg"
        ])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }
}
