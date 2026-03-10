import Foundation

/// Handles vision.ocr — text extraction from images.
public final class VisionHandler: MethodHandler {
    private let provider: VisionProvider

    public var methods: [String] { ["vision.ocr"] }

    public init(provider: VisionProvider = AppleVisionProvider()) {
        self.provider = provider
    }

    public func handle(_ request: JsonRpcRequest) throws -> Any {
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

    public func capability(for method: String) -> MethodCapability {
        MethodCapability(available: true)
    }
}
