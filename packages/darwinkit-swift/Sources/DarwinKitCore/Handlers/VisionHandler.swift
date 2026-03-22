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
