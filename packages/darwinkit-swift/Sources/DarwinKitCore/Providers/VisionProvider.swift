import Darwin
import Foundation
import Vision

// MARK: - Provider Protocol

public struct OCRResult {
    public let text: String
    public let blocks: [OCRBlock]
}

public struct OCRBlock {
    public let text: String
    public let confidence: Float
    public let bounds: CGRect  // Normalized 0..1 coordinates, origin bottom-left
}

public protocol VisionProvider {
    func recognizeText(imagePath: String, languages: [String], level: RecognitionLevel) throws -> OCRResult
    func classifyImage(imagePath: String, maxResults: Int) throws -> ClassifyResult
    func generateFeaturePrint(imagePath: String) throws -> FeaturePrintResult
    func computeSimilarity(imagePath1: String, imagePath2: String) throws -> SimilarityResult
    func detectFaces(imagePath: String, withLandmarks: Bool) throws -> DetectFacesResult
    func detectBarcodes(imagePath: String, symbologies: [String]?) throws -> DetectBarcodesResult
    func detectSaliency(imagePath: String, type: SaliencyType) throws -> SaliencyResult
}

public enum RecognitionLevel: String {
    case accurate
    case fast
}

// MARK: - Classification

public struct ClassificationItem {
    public let identifier: String
    public let confidence: Float
}

public struct ClassifyResult {
    public let classifications: [ClassificationItem]
}

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

// MARK: - Apple Implementation

public struct AppleVisionProvider: VisionProvider {

    public init() {}

    public func recognizeText(imagePath: String, languages: [String], level: RecognitionLevel) throws -> OCRResult {
        let url = URL(fileURLWithPath: imagePath)

        guard FileManager.default.fileExists(atPath: imagePath) else {
            throw JsonRpcError.invalidParams("File not found: \(imagePath)")
        }

        let handler = VNImageRequestHandler(url: url, options: [:])
        var blocks: [OCRBlock] = []
        var fullText: [String] = []

        let request = VNRecognizeTextRequest { request, error in
            if let error = error {
                let errMsg = "[darwinkit] OCR error: \(error.localizedDescription)\n"
                errMsg.utf8.withContiguousStorageIfAvailable { buf in
                    _ = Darwin.write(STDERR_FILENO, buf.baseAddress, buf.count)
                }
                return
            }

            guard let observations = request.results as? [VNRecognizedTextObservation] else { return }

            for observation in observations {
                guard let candidate = observation.topCandidates(1).first else { continue }
                fullText.append(candidate.string)
                blocks.append(OCRBlock(
                    text: candidate.string,
                    confidence: candidate.confidence,
                    bounds: observation.boundingBox
                ))
            }
        }

        request.recognitionLevel = level == .accurate ? .accurate : .fast
        request.usesLanguageCorrection = true
        if !languages.isEmpty {
            request.recognitionLanguages = languages
        }

        try handler.perform([request])

        return OCRResult(
            text: fullText.joined(separator: "\n"),
            blocks: blocks
        )
    }

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
}
