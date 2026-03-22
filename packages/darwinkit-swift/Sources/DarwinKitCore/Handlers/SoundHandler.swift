import Foundation

/// Handles all sound.* methods: classify, classify_at, categories, available.
public final class SoundHandler: MethodHandler {
    private let provider: SoundProvider

    public var methods: [String] {
        ["sound.classify", "sound.classify_at", "sound.categories", "sound.available"]
    }

    public init(provider: SoundProvider = AppleSoundProvider()) {
        self.provider = provider
    }

    public func handle(_ request: JsonRpcRequest) throws -> Any {
        switch request.method {
        case "sound.classify":
            return try handleClassify(request)
        case "sound.classify_at":
            return try handleClassifyAt(request)
        case "sound.categories":
            return try handleCategories(request)
        case "sound.available":
            return handleAvailable(request)
        default:
            throw JsonRpcError.methodNotFound(request.method)
        }
    }

    public func capability(for method: String) -> MethodCapability {
        switch method {
        case "sound.classify", "sound.classify_at", "sound.categories":
            return MethodCapability(available: true, note: "Requires macOS 12+")
        default:
            return MethodCapability(available: true)
        }
    }

    // MARK: - Method Implementations

    private func handleClassify(_ request: JsonRpcRequest) throws -> Any {
        let path = try request.requireString("path")
        let topN = request.int("top_n") ?? 5

        let result = try provider.classify(path: path, topN: topN)
        return result.toDict()
    }

    private func handleClassifyAt(_ request: JsonRpcRequest) throws -> Any {
        let path = try request.requireString("path")

        guard let start = request.double("start") else {
            throw JsonRpcError.invalidParams("Missing required param: start")
        }
        guard let duration = request.double("duration") else {
            throw JsonRpcError.invalidParams("Missing required param: duration")
        }

        let topN = request.int("top_n") ?? 5

        let result = try provider.classifyAt(path: path, start: start, duration: duration, topN: topN)
        return result.toDict()
    }

    private func handleCategories(_ request: JsonRpcRequest) throws -> Any {
        let categories = try provider.categories()
        return ["categories": categories] as [String: Any]
    }

    private func handleAvailable(_ request: JsonRpcRequest) -> Any {
        return ["available": provider.isAvailable()] as [String: Any]
    }
}
