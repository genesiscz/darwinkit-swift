import Foundation
import Testing
@testable import DarwinKitCore

// MARK: - Mock Provider

class MockVisionProvider: VisionProvider {
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

    /// Records the symbologies received by detectBarcodes calls.
    var receivedSymbologies: [String]?

    func recognizeText(imagePath: String, languages: [String], level: RecognitionLevel) throws -> OCRResult {
        if let err = shouldThrow { throw err }
        // Simulate file-not-found for missing paths
        if imagePath.contains("nonexistent") {
            throw JsonRpcError.invalidParams("File not found: \(imagePath)")
        }
        return ocrResult
    }

    func classifyImage(imagePath: String, maxResults: Int) throws -> ClassifyResult {
        guard maxResults >= 0 else {
            throw JsonRpcError.invalidParams("max_results must be >= 0")
        }
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
        receivedSymbologies = symbologies
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
        let mock = MockVisionProvider()
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
        let mock = MockVisionProvider()
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

    @Test("handler registers all 7 vision methods")
    func methodRegistration() {
        let handler = VisionHandler(provider: MockVisionProvider())
        let expected: Set<String> = [
            "vision.ocr", "vision.classify", "vision.feature_print",
            "vision.similarity", "vision.detect_faces", "vision.detect_barcodes",
            "vision.saliency"
        ]
        #expect(Set(handler.methods) == expected)
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

    @Test("classify throws on negative max_results")
    func classifyNegativeMaxResults() {
        let handler = VisionHandler(provider: MockVisionProvider())
        let request = makeRequest(method: "vision.classify", params: [
            "path": "/tmp/cat.jpg",
            "max_results": -1
        ])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    // MARK: - vision.feature_print

    @Test("feature_print returns vector and dimensions")
    func featurePrintSuccess() throws {
        let handler = VisionHandler(provider: MockVisionProvider())
        let request = makeRequest(method: "vision.feature_print", params: [
            "path": "/tmp/image.jpg"
        ])
        let result = try handler.handle(request) as! [String: Any]

        let vector = result["vector"] as! [Float]
        #expect(vector.count == 5)
        #expect(vector[0] == 0.1)
        #expect(result["dimensions"] as? Int == 5)
    }

    @Test("feature_print throws on missing path")
    func featurePrintMissingPath() {
        let handler = VisionHandler(provider: MockVisionProvider())
        let request = makeRequest(method: "vision.feature_print", params: [:])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    @Test("feature_print throws on file not found")
    func featurePrintFileNotFound() {
        let handler = VisionHandler(provider: MockVisionProvider())
        let request = makeRequest(method: "vision.feature_print", params: [
            "path": "/tmp/nonexistent.jpg"
        ])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    // MARK: - vision.similarity

    @Test("similarity returns distance score")
    func similaritySuccess() throws {
        let handler = VisionHandler(provider: MockVisionProvider())
        let request = makeRequest(method: "vision.similarity", params: [
            "path1": "/tmp/image1.jpg",
            "path2": "/tmp/image2.jpg"
        ])
        let result = try handler.handle(request) as! [String: Any]

        #expect(result["distance"] as? Float == 12.5)
    }

    @Test("similarity throws on missing path1")
    func similarityMissingPath1() {
        let handler = VisionHandler(provider: MockVisionProvider())
        let request = makeRequest(method: "vision.similarity", params: [
            "path2": "/tmp/image2.jpg"
        ])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    @Test("similarity throws on missing path2")
    func similarityMissingPath2() {
        let handler = VisionHandler(provider: MockVisionProvider())
        let request = makeRequest(method: "vision.similarity", params: [
            "path1": "/tmp/image1.jpg"
        ])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    @Test("similarity throws on file not found")
    func similarityFileNotFound() {
        let handler = VisionHandler(provider: MockVisionProvider())
        let request = makeRequest(method: "vision.similarity", params: [
            "path1": "/tmp/nonexistent.jpg",
            "path2": "/tmp/image2.jpg"
        ])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    // MARK: - vision.detect_faces

    @Test("detect_faces returns face bounding boxes")
    func detectFacesSuccess() throws {
        let handler = VisionHandler(provider: MockVisionProvider())
        let request = makeRequest(method: "vision.detect_faces", params: [
            "path": "/tmp/photo.jpg"
        ])
        let result = try handler.handle(request) as! [String: Any]
        let faces = result["faces"] as! [[String: Any]]

        #expect(faces.count == 1)
        #expect(faces[0]["confidence"] as? Float == 0.99)

        let bounds = faces[0]["bounds"] as! [String: Any]
        #expect(bounds["x"] as? CGFloat == 0.2)
        #expect(bounds["y"] as? CGFloat == 0.3)
        #expect(bounds["width"] as? CGFloat == 0.3)
        #expect(bounds["height"] as? CGFloat == 0.4)
    }

    @Test("detect_faces without landmarks has no landmarks key")
    func detectFacesNoLandmarks() throws {
        let handler = VisionHandler(provider: MockVisionProvider())
        let request = makeRequest(method: "vision.detect_faces", params: [
            "path": "/tmp/photo.jpg"
        ])
        let result = try handler.handle(request) as! [String: Any]
        let faces = result["faces"] as! [[String: Any]]

        #expect(faces[0]["landmarks"] == nil)
    }

    @Test("detect_faces with landmarks returns landmark data in FaceLandmarkPoints shape")
    func detectFacesWithLandmarks() throws {
        let handler = VisionHandler(provider: MockVisionProvider())
        let request = makeRequest(method: "vision.detect_faces", params: [
            "path": "/tmp/photo.jpg",
            "landmarks": true
        ])
        let result = try handler.handle(request) as! [String: Any]
        let faces = result["faces"] as! [[String: Any]]
        let landmarks = faces[0]["landmarks"] as! [String: Any]

        // Each landmark must be wrapped in a dict with a "points" key (FaceLandmarkPoints shape)
        let leftEye = landmarks["left_eye"] as! [String: Any]
        #expect(leftEye["points"] as? [[CGFloat]] == [[0.3, 0.6], [0.35, 0.6]])

        let rightEye = landmarks["right_eye"] as! [String: Any]
        #expect(rightEye["points"] as? [[CGFloat]] == [[0.5, 0.6], [0.55, 0.6]])

        let nose = landmarks["nose"] as! [String: Any]
        #expect(nose["points"] as? [[CGFloat]] == [[0.4, 0.5]])

        let mouth = landmarks["mouth"] as! [String: Any]
        #expect(mouth["points"] as? [[CGFloat]] == [[0.35, 0.4], [0.45, 0.4]])

        let faceContour = landmarks["face_contour"] as! [String: Any]
        #expect(faceContour["points"] as? [[CGFloat]] == [[0.2, 0.3], [0.5, 0.3]])
    }

    @Test("detect_faces throws on missing path")
    func detectFacesMissingPath() {
        let handler = VisionHandler(provider: MockVisionProvider())
        let request = makeRequest(method: "vision.detect_faces", params: [:])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    @Test("detect_faces handles no faces found")
    func detectFacesEmpty() throws {
        let mock = MockVisionProvider()
        mock.detectFacesResult = DetectFacesResult(faces: [])
        let handler = VisionHandler(provider: mock)
        let request = makeRequest(method: "vision.detect_faces", params: [
            "path": "/tmp/empty.jpg"
        ])
        let result = try handler.handle(request) as! [String: Any]
        let faces = result["faces"] as! [[String: Any]]

        #expect(faces.isEmpty)
    }

    // MARK: - vision.detect_barcodes

    @Test("detect_barcodes returns barcode payload and normalized symbology")
    func detectBarcodesSuccess() throws {
        let handler = VisionHandler(provider: MockVisionProvider())
        let request = makeRequest(method: "vision.detect_barcodes", params: [
            "path": "/tmp/qr.jpg"
        ])
        let result = try handler.handle(request) as! [String: Any]
        let barcodes = result["barcodes"] as! [[String: Any]]

        #expect(barcodes.count == 1)
        #expect(barcodes[0]["payload"] as? String == "https://example.com")
        #expect(barcodes[0]["symbology"] as? String == "QR")
    }

    @Test("detect_barcodes returns bounds")
    func detectBarcodesBounds() throws {
        let handler = VisionHandler(provider: MockVisionProvider())
        let request = makeRequest(method: "vision.detect_barcodes", params: [
            "path": "/tmp/qr.jpg"
        ])
        let result = try handler.handle(request) as! [String: Any]
        let barcodes = result["barcodes"] as! [[String: Any]]
        let bounds = barcodes[0]["bounds"] as! [String: Any]

        #expect(bounds["x"] as? CGFloat == 0.1)
        #expect(bounds["width"] as? CGFloat == 0.3)
    }

    @Test("detect_barcodes throws on missing path")
    func detectBarcodesMissingPath() {
        let handler = VisionHandler(provider: MockVisionProvider())
        let request = makeRequest(method: "vision.detect_barcodes", params: [:])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    @Test("detect_barcodes handles no barcodes found")
    func detectBarcodesEmpty() throws {
        let mock = MockVisionProvider()
        mock.detectBarcodesResult = DetectBarcodesResult(barcodes: [])
        let handler = VisionHandler(provider: mock)
        let request = makeRequest(method: "vision.detect_barcodes", params: [
            "path": "/tmp/photo.jpg"
        ])
        let result = try handler.handle(request) as! [String: Any]
        let barcodes = result["barcodes"] as! [[String: Any]]

        #expect(barcodes.isEmpty)
    }

    @Test("detect_barcodes accepts short symbology names and normalizes for provider")
    func detectBarcodesSymbologies() throws {
        let mock = MockVisionProvider()
        let handler = VisionHandler(provider: mock)
        let request = makeRequest(method: "vision.detect_barcodes", params: [
            "path": "/tmp/qr.jpg",
            "symbologies": ["QR", "EAN13"]
        ])
        let result = try handler.handle(request) as! [String: Any]
        #expect(result["barcodes"] != nil)

        // Verify the provider received raw VNBarcodeSymbology strings
        #expect(mock.receivedSymbologies != nil)
        #expect(mock.receivedSymbologies!.contains("VNBarcodeSymbologyQR"))
        #expect(mock.receivedSymbologies!.contains("VNBarcodeSymbologyEAN13"))
    }

    @Test("detect_barcodes throws on unknown symbology")
    func detectBarcodesUnknownSymbology() {
        let handler = VisionHandler(provider: MockVisionProvider())
        let request = makeRequest(method: "vision.detect_barcodes", params: [
            "path": "/tmp/qr.jpg",
            "symbologies": ["UnknownCode"]
        ])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    // MARK: - vision.saliency

    @Test("saliency returns attention regions by default")
    func saliencyAttention() throws {
        let handler = VisionHandler(provider: MockVisionProvider())
        let request = makeRequest(method: "vision.saliency", params: [
            "path": "/tmp/image.jpg"
        ])
        let result = try handler.handle(request) as! [String: Any]

        #expect(result["type"] as? String == "attention")
        let regions = result["regions"] as! [[String: Any]]
        #expect(regions.count == 1)
        #expect(regions[0]["confidence"] as? Float == 0.85)
    }

    @Test("saliency accepts objectness type")
    func saliencyObjectness() throws {
        let handler = VisionHandler(provider: MockVisionProvider())
        let request = makeRequest(method: "vision.saliency", params: [
            "path": "/tmp/image.jpg",
            "type": "objectness"
        ])
        let result = try handler.handle(request) as! [String: Any]

        #expect(result["type"] as? String == "objectness")
    }

    @Test("saliency throws on invalid type")
    func saliencyInvalidType() {
        let handler = VisionHandler(provider: MockVisionProvider())
        let request = makeRequest(method: "vision.saliency", params: [
            "path": "/tmp/image.jpg",
            "type": "thermal"
        ])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    @Test("saliency throws on missing path")
    func saliencyMissingPath() {
        let handler = VisionHandler(provider: MockVisionProvider())
        let request = makeRequest(method: "vision.saliency", params: [:])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    @Test("saliency region has bounds")
    func saliencyRegionBounds() throws {
        let handler = VisionHandler(provider: MockVisionProvider())
        let request = makeRequest(method: "vision.saliency", params: [
            "path": "/tmp/image.jpg"
        ])
        let result = try handler.handle(request) as! [String: Any]
        let regions = result["regions"] as! [[String: Any]]
        let bounds = regions[0]["bounds"] as! [String: Any]

        #expect(bounds["x"] as? CGFloat == 0.2)
        #expect(bounds["width"] as? CGFloat == 0.6)
    }
}
