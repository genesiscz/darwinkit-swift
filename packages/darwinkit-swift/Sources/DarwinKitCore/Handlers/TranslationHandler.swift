import Foundation

/// Handles all translate.* methods: text, batch, languages, language_status, prepare.
public final class TranslationHandler: MethodHandler {
    private let provider: TranslationProvider

    public var methods: [String] {
        [
            "translate.text", "translate.batch", "translate.languages",
            "translate.language_status", "translate.prepare"
        ]
    }

    public init(provider: TranslationProvider) {
        self.provider = provider
    }

    public func handle(_ request: JsonRpcRequest) throws -> Any {
        switch request.method {
        case "translate.text":
            return try handleText(request)
        case "translate.batch":
            return try handleBatch(request)
        case "translate.languages":
            return try handleLanguages(request)
        case "translate.language_status":
            return try handleLanguageStatus(request)
        case "translate.prepare":
            return try handlePrepare(request)
        default:
            throw JsonRpcError.methodNotFound(request.method)
        }
    }

    public func capability(for method: String) -> MethodCapability {
        switch method {
        case "translate.languages", "translate.language_status":
            return MethodCapability(available: true, note: "Requires macOS 14.4+")
        default:
            return MethodCapability(available: true, note: "Requires macOS 26.0+")
        }
    }

    // MARK: - Method Implementations

    private func handleText(_ request: JsonRpcRequest) throws -> Any {
        let text = try request.requireString("text")
        let target = request.string("to") ?? request.string("target")
        let source = request.string("from") ?? request.string("source")

        guard let target else {
            throw JsonRpcError.invalidParams("Missing required param: to")
        }

        guard !text.isEmpty else {
            throw JsonRpcError.invalidParams("text must not be empty")
        }

        let result = try provider.translate(text: text, source: source, target: target)
        return result.toDict()
    }

    private func handleBatch(_ request: JsonRpcRequest) throws -> Any {
        let target = request.string("to") ?? request.string("target")
        let source = request.string("from") ?? request.string("source")

        guard let target else {
            throw JsonRpcError.invalidParams("Missing required param: to")
        }

        guard let texts = request.stringArray("texts"), !texts.isEmpty else {
            throw JsonRpcError.invalidParams("texts must be a non-empty array of strings")
        }

        let results = try provider.translateBatch(texts: texts, source: source, target: target)
        return [
            "translations": results.map { $0.toDict() }
        ] as [String: Any]
    }

    private func handleLanguages(_ request: JsonRpcRequest) throws -> Any {
        let languages = try provider.supportedLanguages()
        return [
            "languages": languages.map { $0.toDict() }
        ] as [String: Any]
    }

    private func handleLanguageStatus(_ request: JsonRpcRequest) throws -> Any {
        let source = request.string("from") ?? request.string("source")
        let target = request.string("to") ?? request.string("target")

        guard let source else {
            throw JsonRpcError.invalidParams("Missing required param: from")
        }
        guard let target else {
            throw JsonRpcError.invalidParams("Missing required param: to")
        }

        let status = try provider.languagePairStatus(source: source, target: target)
        return [
            "status": status.rawValue,
            "from": source,
            "to": target,
        ] as [String: Any]
    }

    private func handlePrepare(_ request: JsonRpcRequest) throws -> Any {
        let source = request.string("from") ?? request.string("source")
        let target = request.string("to") ?? request.string("target")

        guard let source else {
            throw JsonRpcError.invalidParams("Missing required param: from")
        }
        guard let target else {
            throw JsonRpcError.invalidParams("Missing required param: to")
        }

        try provider.prepare(source: source, target: target)
        return [
            "ok": true,
            "from": source,
            "to": target,
        ] as [String: Any]
    }
}
