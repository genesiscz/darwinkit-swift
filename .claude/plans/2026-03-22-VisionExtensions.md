# Vision Extensions Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Extend the existing `vision.*` namespace with 6 new methods (classify, feature_print, similarity, detect_faces, detect_barcodes, saliency) using Apple's Vision framework.

**Architecture:** All 6 methods extend the existing `VisionProvider` protocol and `VisionHandler` class. The provider protocol gains 6 new method signatures; `AppleVisionProvider` implements them using Apple's Vision framework APIs. The handler routes new method names to corresponding provider calls. The TS SDK extends the existing `Vision` class and `MethodMap` with matching types.

**Tech Stack:** Swift (Vision framework, VNImageRequestHandler), TypeScript (darwinkit SDK), Swift Testing framework (`@Test`, `#expect`)

---

## File Overview

All modifications go into existing files. No new files are created.

| Layer | File | Action |
|-------|------|--------|
| Swift Protocol + Impl | `packages/darwinkit-swift/Sources/DarwinKitCore/Providers/VisionProvider.swift` | Add 6 result structs, 6 protocol methods, 6 implementations |
| Swift Handler | `packages/darwinkit-swift/Sources/DarwinKitCore/Handlers/VisionHandler.swift` | Add 6 method routes + parameter parsing |
| Swift Tests | `packages/darwinkit-swift/Tests/DarwinKitCoreTests/VisionHandlerTests.swift` | Extend `MockVisionProvider`, add ~40 tests |
| TS Types | `packages/darwinkit/src/types.ts` | Add 12 interfaces/types, 6 MethodMap entries |
| TS Namespace | `packages/darwinkit/src/namespaces/vision.ts` | Add 6 methods to Vision class |
| TS Exports | `packages/darwinkit/src/index.ts` | Re-export new types |

### How to Run Swift Tests

```bash
cd packages/darwinkit-swift && swift test --filter VisionHandlerTests 2>&1
```

### How to Type-Check TS

```bash
cd packages/darwinkit && bunx tsc --noEmit
```

---

## Task 1: Add `vision.classify` Result Types + Protocol Method

**Files:**
- Modify: `packages/darwinkit-swift/Sources/DarwinKitCore/Providers/VisionProvider.swift`

**Step 1: Add the ClassifyResult structs and protocol method**

Add after the closing brace of `RecognitionLevel` (line 25), before the `// MARK: - Apple Implementation` comment:

```swift
// MARK: - Classification

public struct ClassificationItem {
    public let identifier: String
    public let confidence: Float
}

public struct ClassifyResult {
    public let classifications: [ClassificationItem]
}
```

Then add to the `VisionProvider` protocol (after the `recognizeText` method on line 19):

```swift
    func classifyImage(imagePath: String, maxResults: Int) throws -> ClassifyResult
```

**Step 2: Add AppleVisionProvider implementation**

Add this method inside `AppleVisionProvider` (after the `recognizeText` method, before the closing brace on line 79):

```swift
    public func classifyImage(imagePath: String, maxResults: Int) throws -> ClassifyResult {
        let url = URL(fileURLWithPath: imagePath)

        guard FileManager.default.fileExists(atPath: imagePath) else {
            throw JsonRpcError.invalidParams("File not found: \(imagePath)")
        }

        let handler = VNImageRequestHandler(url: url, options: [:])
        var items: [ClassificationItem] = []

        let request = VNClassifyImageRequest { request, error in
            if let error = error {
                let errMsg = "[darwinkit] classify error: \(error.localizedDescription)\n"
                errMsg.utf8.withContiguousStorageIfAvailable { buf in
                    _ = Darwin.write(STDERR_FILENO, buf.baseAddress, buf.count)
                }
                return
            }

            guard let observations = request.results as? [VNClassificationObservation] else { return }

            let sorted = observations
                .sorted { $0.confidence > $1.confidence }
                .prefix(maxResults)

            for obs in sorted {
                items.append(ClassificationItem(
                    identifier: obs.identifier,
                    confidence: obs.confidence
                ))
            }
        }

        try handler.perform([request])

        return ClassifyResult(classifications: items)
    }
```

**Step 3: Verify it compiles**

Run:
```bash
cd packages/darwinkit-swift && swift build 2>&1 | head -20
```
Expected: Build errors about `MockVisionProvider` not conforming (this is expected -- we fix that in Task 3).

**Step 4: Commit**

```bash
git add packages/darwinkit-swift/Sources/DarwinKitCore/Providers/VisionProvider.swift
git commit -m "feat(vision): add classify protocol method and AppleVisionProvider implementation"
```

---

## Task 2: Add Remaining 5 Provider Result Types + Protocol Methods

**Files:**
- Modify: `packages/darwinkit-swift/Sources/DarwinKitCore/Providers/VisionProvider.swift`

**Step 1: Add all remaining result structs**

Add after the `ClassifyResult` struct (from Task 1):

```swift
// MARK: - Feature Print

public struct FeaturePrintResult {
    public let vector: [Float]
    public let dimensions: Int
}

// MARK: - Similarity

public struct SimilarityResult {
    public let distance: Float
}

// MARK: - Face Detection

public struct FaceBounds {
    public let x: CGFloat
    public let y: CGFloat
    public let width: CGFloat
    public let height: CGFloat
}

public struct FaceLandmarkPoints {
    public let points: [[CGFloat]]  // Array of [x, y] pairs
}

public struct FaceLandmarks {
    public let leftEye: FaceLandmarkPoints?
    public let rightEye: FaceLandmarkPoints?
    public let nose: FaceLandmarkPoints?
    public let mouth: FaceLandmarkPoints?
    public let faceContour: FaceLandmarkPoints?
}

public struct FaceObservation {
    public let bounds: FaceBounds
    public let confidence: Float
    public let landmarks: FaceLandmarks?
}

public struct DetectFacesResult {
    public let faces: [FaceObservation]
}

// MARK: - Barcode Detection

public struct BarcodeObservation {
    public let payload: String?
    public let symbology: String
    public let bounds: FaceBounds  // Reuse same bounds struct
}

public struct DetectBarcodesResult {
    public let barcodes: [BarcodeObservation]
}

// MARK: - Saliency

public enum SaliencyType: String {
    case attention
    case objectness
}

public struct SaliencyRegion {
    public let bounds: FaceBounds
    public let confidence: Float
}

public struct SaliencyResult {
    public let type: SaliencyType
    public let regions: [SaliencyRegion]
}
```

**Step 2: Add remaining 5 protocol methods**

Add to the `VisionProvider` protocol (after `classifyImage`):

```swift
    func generateFeaturePrint(imagePath: String) throws -> FeaturePrintResult
    func computeSimilarity(imagePath1: String, imagePath2: String) throws -> SimilarityResult
    func detectFaces(imagePath: String, withLandmarks: Bool) throws -> DetectFacesResult
    func detectBarcodes(imagePath: String, symbologies: [String]?) throws -> DetectBarcodesResult
    func detectSaliency(imagePath: String, type: SaliencyType) throws -> SaliencyResult
```

**Step 3: Implement all 5 in AppleVisionProvider**

Add these methods inside `AppleVisionProvider`, after `classifyImage`:

```swift
    public func generateFeaturePrint(imagePath: String) throws -> FeaturePrintResult {
        let url = URL(fileURLWithPath: imagePath)

        guard FileManager.default.fileExists(atPath: imagePath) else {
            throw JsonRpcError.invalidParams("File not found: \(imagePath)")
        }

        let handler = VNImageRequestHandler(url: url, options: [:])
        let request = VNGenerateImageFeaturePrintRequest()

        try handler.perform([request])

        guard let observation = request.results?.first as? VNFeaturePrintObservation else {
            throw JsonRpcError.internalError("No feature print generated")
        }

        // Extract the raw float data from the feature print
        let elementCount = observation.elementCount
        var vector = [Float](repeating: 0, count: elementCount)

        // VNFeaturePrintObservation stores data as Float
        let data = observation.data
        data.withUnsafeBytes { rawBuffer in
            let floatBuffer = rawBuffer.bindMemory(to: Float.self)
            for i in 0..<elementCount {
                vector[i] = floatBuffer[i]
            }
        }

        return FeaturePrintResult(vector: vector, dimensions: elementCount)
    }

    public func computeSimilarity(imagePath1: String, imagePath2: String) throws -> SimilarityResult {
        let url1 = URL(fileURLWithPath: imagePath1)
        let url2 = URL(fileURLWithPath: imagePath2)

        guard FileManager.default.fileExists(atPath: imagePath1) else {
            throw JsonRpcError.invalidParams("File not found: \(imagePath1)")
        }
        guard FileManager.default.fileExists(atPath: imagePath2) else {
            throw JsonRpcError.invalidParams("File not found: \(imagePath2)")
        }

        let handler1 = VNImageRequestHandler(url: url1, options: [:])
        let handler2 = VNImageRequestHandler(url: url2, options: [:])

        let request1 = VNGenerateImageFeaturePrintRequest()
        let request2 = VNGenerateImageFeaturePrintRequest()

        try handler1.perform([request1])
        try handler2.perform([request2])

        guard let obs1 = request1.results?.first as? VNFeaturePrintObservation,
              let obs2 = request2.results?.first as? VNFeaturePrintObservation else {
            throw JsonRpcError.internalError("Could not generate feature prints for comparison")
        }

        var distance: Float = 0
        try obs1.computeDistance(&distance, to: obs2)

        return SimilarityResult(distance: distance)
    }

    public func detectFaces(imagePath: String, withLandmarks: Bool) throws -> DetectFacesResult {
        let url = URL(fileURLWithPath: imagePath)

        guard FileManager.default.fileExists(atPath: imagePath) else {
            throw JsonRpcError.invalidParams("File not found: \(imagePath)")
        }

        let handler = VNImageRequestHandler(url: url, options: [:])
        var faces: [FaceObservation] = []

        if withLandmarks {
            let request = VNDetectFaceLandmarksRequest { request, error in
                if let error = error {
                    let errMsg = "[darwinkit] face landmarks error: \(error.localizedDescription)\n"
                    errMsg.utf8.withContiguousStorageIfAvailable { buf in
                        _ = Darwin.write(STDERR_FILENO, buf.baseAddress, buf.count)
                    }
                    return
                }

                guard let observations = request.results as? [VNFaceObservation] else { return }

                for obs in observations {
                    let box = obs.boundingBox
                    let bounds = FaceBounds(x: box.origin.x, y: box.origin.y, width: box.width, height: box.height)

                    var landmarks: FaceLandmarks? = nil
                    if let lm = obs.landmarks {
                        landmarks = FaceLandmarks(
                            leftEye: Self.extractPoints(lm.leftEye),
                            rightEye: Self.extractPoints(lm.rightEye),
                            nose: Self.extractPoints(lm.nose),
                            mouth: Self.extractPoints(lm.innerLips),
                            faceContour: Self.extractPoints(lm.faceContour)
                        )
                    }

                    faces.append(FaceObservation(
                        bounds: bounds,
                        confidence: obs.confidence,
                        landmarks: landmarks
                    ))
                }
            }

            try handler.perform([request])
        } else {
            let request = VNDetectFaceRectanglesRequest { request, error in
                if let error = error {
                    let errMsg = "[darwinkit] face detection error: \(error.localizedDescription)\n"
                    errMsg.utf8.withContiguousStorageIfAvailable { buf in
                        _ = Darwin.write(STDERR_FILENO, buf.baseAddress, buf.count)
                    }
                    return
                }

                guard let observations = request.results as? [VNFaceObservation] else { return }

                for obs in observations {
                    let box = obs.boundingBox
                    let bounds = FaceBounds(x: box.origin.x, y: box.origin.y, width: box.width, height: box.height)
                    faces.append(FaceObservation(
                        bounds: bounds,
                        confidence: obs.confidence,
                        landmarks: nil
                    ))
                }
            }

            try handler.perform([request])
        }

        return DetectFacesResult(faces: faces)
    }

    private static func extractPoints(_ region: VNFaceLandmarkRegion2D?) -> FaceLandmarkPoints? {
        guard let region = region else { return nil }
        let points = region.normalizedPoints.map { [$0.x, $0.y] }
        return FaceLandmarkPoints(points: points)
    }

    public func detectBarcodes(imagePath: String, symbologies: [String]?) throws -> DetectBarcodesResult {
        let url = URL(fileURLWithPath: imagePath)

        guard FileManager.default.fileExists(atPath: imagePath) else {
            throw JsonRpcError.invalidParams("File not found: \(imagePath)")
        }

        let handler = VNImageRequestHandler(url: url, options: [:])
        var barcodes: [BarcodeObservation] = []

        let request = VNDetectBarcodesRequest { request, error in
            if let error = error {
                let errMsg = "[darwinkit] barcode detection error: \(error.localizedDescription)\n"
                errMsg.utf8.withContiguousStorageIfAvailable { buf in
                    _ = Darwin.write(STDERR_FILENO, buf.baseAddress, buf.count)
                }
                return
            }

            guard let observations = request.results as? [VNBarcodeObservation] else { return }

            for obs in observations {
                let box = obs.boundingBox
                let bounds = FaceBounds(x: box.origin.x, y: box.origin.y, width: box.width, height: box.height)
                barcodes.append(BarcodeObservation(
                    payload: obs.payloadStringValue,
                    symbology: obs.symbology.rawValue,
                    bounds: bounds
                ))
            }
        }

        if let symbologies = symbologies {
            request.symbologies = symbologies.compactMap { VNBarcodeSymbology(rawValue: $0) }
        }

        try handler.perform([request])

        return DetectBarcodesResult(barcodes: barcodes)
    }

    public func detectSaliency(imagePath: String, type: SaliencyType) throws -> SaliencyResult {
        let url = URL(fileURLWithPath: imagePath)

        guard FileManager.default.fileExists(atPath: imagePath) else {
            throw JsonRpcError.invalidParams("File not found: \(imagePath)")
        }

        let handler = VNImageRequestHandler(url: url, options: [:])
        var regions: [SaliencyRegion] = []

        let request: VNImageBasedRequest
        switch type {
        case .attention:
            request = VNGenerateAttentionBasedSaliencyImageRequest { request, error in
                if let error = error {
                    let errMsg = "[darwinkit] saliency error: \(error.localizedDescription)\n"
                    errMsg.utf8.withContiguousStorageIfAvailable { buf in
                        _ = Darwin.write(STDERR_FILENO, buf.baseAddress, buf.count)
                    }
                    return
                }

                guard let observations = request.results as? [VNSaliencyImageObservation] else { return }

                for obs in observations {
                    guard let salientObjects = obs.salientObjects else { continue }
                    for obj in salientObjects {
                        let box = obj.boundingBox
                        regions.append(SaliencyRegion(
                            bounds: FaceBounds(x: box.origin.x, y: box.origin.y, width: box.width, height: box.height),
                            confidence: obj.confidence
                        ))
                    }
                }
            }
        case .objectness:
            request = VNGenerateObjectnessBasedSaliencyImageRequest { request, error in
                if let error = error {
                    let errMsg = "[darwinkit] saliency error: \(error.localizedDescription)\n"
                    errMsg.utf8.withContiguousStorageIfAvailable { buf in
                        _ = Darwin.write(STDERR_FILENO, buf.baseAddress, buf.count)
                    }
                    return
                }

                guard let observations = request.results as? [VNSaliencyImageObservation] else { return }

                for obs in observations {
                    guard let salientObjects = obs.salientObjects else { continue }
                    for obj in salientObjects {
                        let box = obj.boundingBox
                        regions.append(SaliencyRegion(
                            bounds: FaceBounds(x: box.origin.x, y: box.origin.y, width: box.width, height: box.height),
                            confidence: obj.confidence
                        ))
                    }
                }
            }
        }

        try handler.perform([request])

        return SaliencyResult(type: type, regions: regions)
    }
```

**Step 4: Verify it compiles (will fail on mock)**

Run:
```bash
cd packages/darwinkit-swift && swift build 2>&1 | head -20
```
Expected: Errors about `MockVisionProvider` not conforming to `VisionProvider` -- that is expected and fixed in Task 3.

**Step 5: Commit**

```bash
git add packages/darwinkit-swift/Sources/DarwinKitCore/Providers/VisionProvider.swift
git commit -m "feat(vision): add provider protocol + Apple implementations for feature_print, similarity, detect_faces, detect_barcodes, saliency"
```

---

## Task 3: Extend MockVisionProvider + Write Classify Tests

**Files:**
- Modify: `packages/darwinkit-swift/Tests/DarwinKitCoreTests/VisionHandlerTests.swift`

**Step 1: Extend MockVisionProvider with all 6 new methods**

Add these properties to the existing `MockVisionProvider` struct (after `shouldThrow` on line 15, before `func recognizeText`):

```swift
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
```

Then add the 6 mock method implementations (after the existing `recognizeText` method):

```swift
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
```

**Step 2: Add classify tests**

Add at the end of the `VisionHandlerTests` struct (before its closing brace), after the existing capability test:

```swift
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
```

**Step 3: Run tests to verify they fail (handler does not route classify yet)**

Run:
```bash
cd packages/darwinkit-swift && swift test --filter VisionHandlerTests 2>&1 | tail -20
```
Expected: FAIL -- the `vision.classify` method is not yet handled by VisionHandler.

**Step 4: Commit**

```bash
git add packages/darwinkit-swift/Tests/DarwinKitCoreTests/VisionHandlerTests.swift
git commit -m "test(vision): extend mock provider, add classify handler tests (red)"
```

---

## Task 4: Add All Handler Routing (vision.classify through vision.saliency)

**Files:**
- Modify: `packages/darwinkit-swift/Sources/DarwinKitCore/Handlers/VisionHandler.swift`

**Step 1: Rewrite the entire VisionHandler**

Replace the full contents of `VisionHandler.swift` with:

```swift
import Foundation

/// Handles all vision.* methods.
public final class VisionHandler: MethodHandler {
    private let provider: VisionProvider

    public var methods: [String] {
        [
            "vision.ocr", "vision.classify", "vision.feature_print",
            "vision.similarity", "vision.detect_faces", "vision.detect_barcodes",
            "vision.saliency"
        ]
    }

    public init(provider: VisionProvider = AppleVisionProvider()) {
        self.provider = provider
    }

    public func handle(_ request: JsonRpcRequest) throws -> Any {
        switch request.method {
        case "vision.ocr":
            return try handleOCR(request)
        case "vision.classify":
            return try handleClassify(request)
        case "vision.feature_print":
            return try handleFeaturePrint(request)
        case "vision.similarity":
            return try handleSimilarity(request)
        case "vision.detect_faces":
            return try handleDetectFaces(request)
        case "vision.detect_barcodes":
            return try handleDetectBarcodes(request)
        case "vision.saliency":
            return try handleSaliency(request)
        default:
            throw JsonRpcError.methodNotFound(request.method)
        }
    }

    public func capability(for method: String) -> MethodCapability {
        MethodCapability(available: true)
    }

    // MARK: - Method Implementations

    private func handleOCR(_ request: JsonRpcRequest) throws -> Any {
        let path = try request.requireString("path")
        let languages = request.stringArray("languages") ?? ["en-US"]
        let levelStr = request.string("level") ?? "accurate"

        guard let level = RecognitionLevel(rawValue: levelStr) else {
            throw JsonRpcError.invalidParams("level must be 'accurate' or 'fast'")
        }

        let result = try provider.recognizeText(imagePath: path, languages: languages, level: level)

        return [
            "text": result.text,
            "blocks": result.blocks.map { block in
                [
                    "text": block.text,
                    "confidence": block.confidence,
                    "bounds": [
                        "x": block.bounds.origin.x,
                        "y": block.bounds.origin.y,
                        "width": block.bounds.width,
                        "height": block.bounds.height
                    ]
                ] as [String: Any]
            }
        ] as [String: Any]
    }

    private func handleClassify(_ request: JsonRpcRequest) throws -> Any {
        let path = try request.requireString("path")
        let maxResults = request.int("max_results") ?? 10

        let result = try provider.classifyImage(imagePath: path, maxResults: maxResults)

        return [
            "classifications": result.classifications.map { item in
                [
                    "identifier": item.identifier,
                    "confidence": item.confidence
                ] as [String: Any]
            }
        ] as [String: Any]
    }

    private func handleFeaturePrint(_ request: JsonRpcRequest) throws -> Any {
        let path = try request.requireString("path")
        let result = try provider.generateFeaturePrint(imagePath: path)
        return [
            "vector": result.vector,
            "dimensions": result.dimensions
        ] as [String: Any]
    }

    private func handleSimilarity(_ request: JsonRpcRequest) throws -> Any {
        let path1 = try request.requireString("path1")
        let path2 = try request.requireString("path2")
        let result = try provider.computeSimilarity(imagePath1: path1, imagePath2: path2)
        return [
            "distance": result.distance
        ] as [String: Any]
    }

    private func handleDetectFaces(_ request: JsonRpcRequest) throws -> Any {
        let path = try request.requireString("path")
        let withLandmarks = request.bool("landmarks") ?? false

        let result = try provider.detectFaces(imagePath: path, withLandmarks: withLandmarks)

        return [
            "faces": result.faces.map { face in
                var dict: [String: Any] = [
                    "bounds": [
                        "x": face.bounds.x,
                        "y": face.bounds.y,
                        "width": face.bounds.width,
                        "height": face.bounds.height
                    ],
                    "confidence": face.confidence
                ]
                if let lm = face.landmarks {
                    var landmarksDict: [String: Any] = [:]
                    if let leftEye = lm.leftEye {
                        landmarksDict["left_eye"] = leftEye.points
                    }
                    if let rightEye = lm.rightEye {
                        landmarksDict["right_eye"] = rightEye.points
                    }
                    if let nose = lm.nose {
                        landmarksDict["nose"] = nose.points
                    }
                    if let mouth = lm.mouth {
                        landmarksDict["mouth"] = mouth.points
                    }
                    if let contour = lm.faceContour {
                        landmarksDict["face_contour"] = contour.points
                    }
                    dict["landmarks"] = landmarksDict
                }
                return dict
            }
        ] as [String: Any]
    }

    private func handleDetectBarcodes(_ request: JsonRpcRequest) throws -> Any {
        let path = try request.requireString("path")
        let symbologies = request.stringArray("symbologies")

        let result = try provider.detectBarcodes(imagePath: path, symbologies: symbologies)

        return [
            "barcodes": result.barcodes.map { barcode in
                [
                    "payload": barcode.payload as Any,
                    "symbology": barcode.symbology,
                    "bounds": [
                        "x": barcode.bounds.x,
                        "y": barcode.bounds.y,
                        "width": barcode.bounds.width,
                        "height": barcode.bounds.height
                    ]
                ] as [String: Any]
            }
        ] as [String: Any]
    }

    private func handleSaliency(_ request: JsonRpcRequest) throws -> Any {
        let path = try request.requireString("path")
        let typeStr = request.string("type") ?? "attention"

        guard let type = SaliencyType(rawValue: typeStr) else {
            throw JsonRpcError.invalidParams("type must be 'attention' or 'objectness'")
        }

        let result = try provider.detectSaliency(imagePath: path, type: type)

        return [
            "type": result.type.rawValue,
            "regions": result.regions.map { region in
                [
                    "bounds": [
                        "x": region.bounds.x,
                        "y": region.bounds.y,
                        "width": region.bounds.width,
                        "height": region.bounds.height
                    ],
                    "confidence": region.confidence
                ] as [String: Any]
            }
        ] as [String: Any]
    }
}
```

**Step 2: Run classify tests to verify they pass**

Run:
```bash
cd packages/darwinkit-swift && swift test --filter VisionHandlerTests 2>&1 | tail -30
```
Expected: All classify tests PASS. Existing OCR tests also PASS.

**Step 3: Commit**

```bash
git add packages/darwinkit-swift/Sources/DarwinKitCore/Handlers/VisionHandler.swift
git commit -m "feat(vision): add handler routing for all 6 new vision methods"
```

---

## Task 5: Write Tests for feature_print, similarity, detect_faces, detect_barcodes, saliency

**Files:**
- Modify: `packages/darwinkit-swift/Tests/DarwinKitCoreTests/VisionHandlerTests.swift`

**Step 1: Add feature_print tests**

Add to the `VisionHandlerTests` struct:

```swift
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
```

**Step 2: Add similarity tests**

```swift
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
```

**Step 3: Add detect_faces tests**

```swift
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

    @Test("detect_faces with landmarks returns landmark data")
    func detectFacesWithLandmarks() throws {
        let handler = VisionHandler(provider: MockVisionProvider())
        let request = makeRequest(method: "vision.detect_faces", params: [
            "path": "/tmp/photo.jpg",
            "landmarks": true
        ])
        let result = try handler.handle(request) as! [String: Any]
        let faces = result["faces"] as! [[String: Any]]
        let landmarks = faces[0]["landmarks"] as! [String: Any]

        #expect(landmarks["left_eye"] != nil)
        #expect(landmarks["right_eye"] != nil)
        #expect(landmarks["nose"] != nil)
        #expect(landmarks["mouth"] != nil)
        #expect(landmarks["face_contour"] != nil)
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
        var mock = MockVisionProvider()
        mock.detectFacesResult = DetectFacesResult(faces: [])
        let handler = VisionHandler(provider: mock)
        let request = makeRequest(method: "vision.detect_faces", params: [
            "path": "/tmp/empty.jpg"
        ])
        let result = try handler.handle(request) as! [String: Any]
        let faces = result["faces"] as! [[String: Any]]

        #expect(faces.isEmpty)
    }
```

**Step 4: Add detect_barcodes tests**

```swift
    // MARK: - vision.detect_barcodes

    @Test("detect_barcodes returns barcode payload and symbology")
    func detectBarcodesSuccess() throws {
        let handler = VisionHandler(provider: MockVisionProvider())
        let request = makeRequest(method: "vision.detect_barcodes", params: [
            "path": "/tmp/qr.jpg"
        ])
        let result = try handler.handle(request) as! [String: Any]
        let barcodes = result["barcodes"] as! [[String: Any]]

        #expect(barcodes.count == 1)
        #expect(barcodes[0]["payload"] as? String == "https://example.com")
        #expect(barcodes[0]["symbology"] as? String == "VNBarcodeSymbologyQR")
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
        var mock = MockVisionProvider()
        mock.detectBarcodesResult = DetectBarcodesResult(barcodes: [])
        let handler = VisionHandler(provider: mock)
        let request = makeRequest(method: "vision.detect_barcodes", params: [
            "path": "/tmp/photo.jpg"
        ])
        let result = try handler.handle(request) as! [String: Any]
        let barcodes = result["barcodes"] as! [[String: Any]]

        #expect(barcodes.isEmpty)
    }

    @Test("detect_barcodes accepts symbologies filter")
    func detectBarcodesSymbologies() throws {
        let handler = VisionHandler(provider: MockVisionProvider())
        let request = makeRequest(method: "vision.detect_barcodes", params: [
            "path": "/tmp/qr.jpg",
            "symbologies": ["VNBarcodeSymbologyQR", "VNBarcodeSymbologyEAN13"]
        ])
        let result = try handler.handle(request) as! [String: Any]
        #expect(result["barcodes"] != nil)
    }
```

**Step 5: Add saliency tests**

```swift
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
```

**Step 6: Update method registration test**

Replace the existing method registration test (around line 191-195):

```swift
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
```

**Step 7: Run all tests**

Run:
```bash
cd packages/darwinkit-swift && swift test --filter VisionHandlerTests 2>&1 | tail -30
```
Expected: ALL tests PASS.

**Step 8: Commit**

```bash
git add packages/darwinkit-swift/Tests/DarwinKitCoreTests/VisionHandlerTests.swift
git commit -m "test(vision): add comprehensive tests for all 6 new vision methods"
```

---

## Task 6: Add TypeScript Types

**Files:**
- Modify: `packages/darwinkit/src/types.ts`

**Step 1: Add new Vision types**

In `types.ts`, find the Vision section (line 79-104). Add the following after the existing `OCRResult` interface (after line 104, before the `// Auth` section):

```typescript
// Classification
export interface ClassifyParams {
  path: string
  max_results?: number // default: 10
}
export interface ClassificationItem {
  identifier: string
  confidence: number
}
export interface ClassifyResult {
  classifications: ClassificationItem[]
}

// Feature Print
export interface FeaturePrintParams {
  path: string
}
export interface FeaturePrintResult {
  vector: number[]
  dimensions: number
}

// Similarity
export interface SimilarityParams {
  path1: string
  path2: string
}
export interface SimilarityResult {
  distance: number
}

// Face Detection
export interface FaceBounds {
  x: number
  y: number
  width: number
  height: number
}
export interface FaceLandmarkPoints {
  points: number[][] // Array of [x, y] pairs
}
export interface FaceLandmarks {
  left_eye?: FaceLandmarkPoints
  right_eye?: FaceLandmarkPoints
  nose?: FaceLandmarkPoints
  mouth?: FaceLandmarkPoints
  face_contour?: FaceLandmarkPoints
}
export interface FaceObservation {
  bounds: FaceBounds
  confidence: number
  landmarks?: FaceLandmarks
}
export interface DetectFacesParams {
  path: string
  landmarks?: boolean // default: false
}
export interface DetectFacesResult {
  faces: FaceObservation[]
}

// Barcode Detection
export interface BarcodeObservation {
  payload: string | null
  symbology: string
  bounds: FaceBounds
}
export interface DetectBarcodesParams {
  path: string
  symbologies?: string[]
}
export interface DetectBarcodesResult {
  barcodes: BarcodeObservation[]
}

// Saliency
export type SaliencyType = "attention" | "objectness"
export interface SaliencyRegion {
  bounds: FaceBounds
  confidence: number
}
export interface SaliencyParams {
  path: string
  type?: SaliencyType // default: "attention"
}
export interface SaliencyResultData {
  type: SaliencyType
  regions: SaliencyRegion[]
}
```

**Step 2: Add MethodMap entries**

Find the MethodMap interface. Add these 6 entries after the `"vision.ocr"` line (after line 288):

```typescript
  "vision.classify": { params: ClassifyParams; result: ClassifyResult }
  "vision.feature_print": {
    params: FeaturePrintParams
    result: FeaturePrintResult
  }
  "vision.similarity": { params: SimilarityParams; result: SimilarityResult }
  "vision.detect_faces": {
    params: DetectFacesParams
    result: DetectFacesResult
  }
  "vision.detect_barcodes": {
    params: DetectBarcodesParams
    result: DetectBarcodesResult
  }
  "vision.saliency": { params: SaliencyParams; result: SaliencyResultData }
```

**Step 3: Type-check**

Run:
```bash
cd packages/darwinkit && bunx tsc --noEmit
```
Expected: No errors.

**Step 4: Commit**

```bash
git add packages/darwinkit/src/types.ts
git commit -m "feat(vision): add TypeScript types for 6 new vision methods"
```

---

## Task 7: Extend TS Vision Namespace Class

**Files:**
- Modify: `packages/darwinkit/src/namespaces/vision.ts`

**Step 1: Update imports**

Replace the import block (lines 1-8):

```typescript
import type { DarwinKitClient } from "../client.js"
import type {
  MethodMap,
  MethodName,
  PreparedCall,
  OCRParams,
  OCRResult,
  ClassifyParams,
  ClassifyResult,
  FeaturePrintParams,
  FeaturePrintResult,
  SimilarityParams,
  SimilarityResult,
  DetectFacesParams,
  DetectFacesResult,
  DetectBarcodesParams,
  DetectBarcodesResult,
  SaliencyParams,
  SaliencyResultData,
} from "../types.js"
```

**Step 2: Add 6 new properties to the Vision class**

Add after the existing `ocr` readonly property (after line 28, before `constructor`):

```typescript
  readonly classify: {
    (
      params: ClassifyParams,
      options?: { timeout?: number },
    ): Promise<ClassifyResult>
    prepare(params: ClassifyParams): PreparedCall<"vision.classify">
  }

  readonly featurePrint: {
    (
      params: FeaturePrintParams,
      options?: { timeout?: number },
    ): Promise<FeaturePrintResult>
    prepare(
      params: FeaturePrintParams,
    ): PreparedCall<"vision.feature_print">
  }

  readonly similarity: {
    (
      params: SimilarityParams,
      options?: { timeout?: number },
    ): Promise<SimilarityResult>
    prepare(params: SimilarityParams): PreparedCall<"vision.similarity">
  }

  readonly detectFaces: {
    (
      params: DetectFacesParams,
      options?: { timeout?: number },
    ): Promise<DetectFacesResult>
    prepare(
      params: DetectFacesParams,
    ): PreparedCall<"vision.detect_faces">
  }

  readonly detectBarcodes: {
    (
      params: DetectBarcodesParams,
      options?: { timeout?: number },
    ): Promise<DetectBarcodesResult>
    prepare(
      params: DetectBarcodesParams,
    ): PreparedCall<"vision.detect_barcodes">
  }

  readonly saliency: {
    (
      params: SaliencyParams,
      options?: { timeout?: number },
    ): Promise<SaliencyResultData>
    prepare(params: SaliencyParams): PreparedCall<"vision.saliency">
  }
```

**Step 3: Initialize them in the constructor**

Add after the existing `this.ocr = method(...)` line (after line 31), still inside the constructor:

```typescript
    this.classify = method(client, "vision.classify") as Vision["classify"]
    this.featurePrint = method(
      client,
      "vision.feature_print",
    ) as Vision["featurePrint"]
    this.similarity = method(
      client,
      "vision.similarity",
    ) as Vision["similarity"]
    this.detectFaces = method(
      client,
      "vision.detect_faces",
    ) as Vision["detectFaces"]
    this.detectBarcodes = method(
      client,
      "vision.detect_barcodes",
    ) as Vision["detectBarcodes"]
    this.saliency = method(
      client,
      "vision.saliency",
    ) as Vision["saliency"]
```

**Step 4: Type-check**

Run:
```bash
cd packages/darwinkit && bunx tsc --noEmit
```
Expected: No errors.

**Step 5: Commit**

```bash
git add packages/darwinkit/src/namespaces/vision.ts
git commit -m "feat(vision): add 6 new methods to TS Vision namespace class"
```

---

## Task 8: Export New Types from index.ts

**Files:**
- Modify: `packages/darwinkit/src/index.ts`

**Step 1: Add new Vision type exports**

Find the Vision section in the type re-exports (lines 40-45). Replace:

```typescript
  // Vision
  RecognitionLevel,
  OCRParams,
  OCRBounds,
  OCRBlock,
  OCRResult,
```

With:

```typescript
  // Vision
  RecognitionLevel,
  OCRParams,
  OCRBounds,
  OCRBlock,
  OCRResult,
  ClassifyParams,
  ClassificationItem,
  ClassifyResult,
  FeaturePrintParams,
  FeaturePrintResult,
  SimilarityParams,
  SimilarityResult,
  FaceBounds,
  FaceLandmarkPoints,
  FaceLandmarks,
  FaceObservation,
  DetectFacesParams,
  DetectFacesResult,
  BarcodeObservation,
  DetectBarcodesParams,
  DetectBarcodesResult,
  SaliencyType,
  SaliencyRegion,
  SaliencyParams,
  SaliencyResultData,
```

**Step 2: Type-check**

Run:
```bash
cd packages/darwinkit && bunx tsc --noEmit
```
Expected: No errors.

**Step 3: Commit**

```bash
git add packages/darwinkit/src/index.ts
git commit -m "feat(vision): re-export all new vision types from package index"
```

---

## Task 9: Final Verification

**Step 1: Run all Swift tests**

```bash
cd packages/darwinkit-swift && swift test 2>&1 | tail -30
```
Expected: ALL tests pass (including VisionHandlerTests, CoreMLHandlerTests, NLPHandlerTests, ProtocolTests).

**Step 2: Full TS type-check**

```bash
cd packages/darwinkit && bunx tsc --noEmit
```
Expected: No errors.

**Step 3: Verify method registration count**

The `VisionHandler.methods` should now have 7 entries: `vision.ocr`, `vision.classify`, `vision.feature_print`, `vision.similarity`, `vision.detect_faces`, `vision.detect_barcodes`, `vision.saliency`.

The `MethodMap` in `types.ts` should now have 6 new entries (total grows from the previous count).

**Step 4: Final commit if any adjustments were needed**

```bash
git add -A
git status
# Only commit if there are changes
git commit -m "chore(vision): final cleanup for vision extensions"
```

---

## API Summary (for reference)

| Method | Params | Result |
|--------|--------|--------|
| `vision.classify` | `path`, `max_results?` (default 10) | `{ classifications: [{ identifier, confidence }] }` |
| `vision.feature_print` | `path` | `{ vector: number[], dimensions }` |
| `vision.similarity` | `path1`, `path2` | `{ distance: number }` |
| `vision.detect_faces` | `path`, `landmarks?` (default false) | `{ faces: [{ bounds, confidence, landmarks? }] }` |
| `vision.detect_barcodes` | `path`, `symbologies?` | `{ barcodes: [{ payload, symbology, bounds }] }` |
| `vision.saliency` | `path`, `type?` (default "attention") | `{ type, regions: [{ bounds, confidence }] }` |

All bounds are normalized 0..1 coordinates (origin bottom-left), matching existing `vision.ocr` behavior.
