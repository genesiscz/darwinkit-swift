import Foundation
import NaturalLanguage

/// Handles all nlp.* methods: embed, distance, neighbors, tag, sentiment, language.
public final class NLPHandler: MethodHandler {
    private let provider: NLPProvider

    public var methods: [String] {
        ["nlp.embed", "nlp.distance", "nlp.neighbors", "nlp.tag", "nlp.sentiment", "nlp.language"]
    }

    public init(provider: NLPProvider = AppleNLPProvider()) {
        self.provider = provider
    }

    public func handle(_ request: JsonRpcRequest) throws -> Any {
        switch request.method {
        case "nlp.embed":
            return try handleEmbed(request)
        case "nlp.distance":
            return try handleDistance(request)
        case "nlp.neighbors":
            return try handleNeighbors(request)
        case "nlp.tag":
            return try handleTag(request)
        case "nlp.sentiment":
            return try handleSentiment(request)
        case "nlp.language":
            return try handleLanguage(request)
        default:
            throw JsonRpcError.methodNotFound(request.method)
        }
    }

    public func capability(for method: String) -> MethodCapability {
        switch method {
        case "nlp.embed":
            return MethodCapability(available: true, note: "Sentence embeddings require macOS 11+")
        case "nlp.sentiment":
            return MethodCapability(available: true, note: "Requires macOS 11+")
        default:
            return MethodCapability(available: true)
        }
    }

    // MARK: - Method Implementations

    private func handleEmbed(_ request: JsonRpcRequest) throws -> Any {
        let text = try request.requireString("text")
        let langStr = try request.requireString("language")
        let typeStr = request.string("type") ?? "sentence"

        let language = NLLanguage(rawValue: langStr)
        guard let type = EmbedType(rawValue: typeStr) else {
            throw JsonRpcError.invalidParams("type must be 'word' or 'sentence'")
        }

        let vector = try provider.embed(text: text, language: language, type: type)
        return [
            "vector": vector,
            "dimension": vector.count
        ] as [String: Any]
    }

    private func handleDistance(_ request: JsonRpcRequest) throws -> Any {
        let text1 = try request.requireString("text1")
        let text2 = try request.requireString("text2")
        let langStr = try request.requireString("language")
        let typeStr = request.string("type") ?? "word"

        let language = NLLanguage(rawValue: langStr)
        guard let type = EmbedType(rawValue: typeStr) else {
            throw JsonRpcError.invalidParams("type must be 'word' or 'sentence'")
        }

        let distance = try provider.distance(text1: text1, text2: text2, language: language, type: type)
        return [
            "distance": distance,
            "type": "cosine"
        ] as [String: Any]
    }

    private func handleNeighbors(_ request: JsonRpcRequest) throws -> Any {
        let text = try request.requireString("text")
        let langStr = try request.requireString("language")
        let typeStr = request.string("type") ?? "word"
        let count = request.int("count") ?? 5

        let language = NLLanguage(rawValue: langStr)
        guard let type = EmbedType(rawValue: typeStr) else {
            throw JsonRpcError.invalidParams("type must be 'word' or 'sentence'")
        }

        let neighbors = try provider.neighbors(text: text, language: language, type: type, count: count)
        return [
            "neighbors": neighbors.map { ["text": $0.0, "distance": $0.1] as [String: Any] }
        ] as [String: Any]
    }

    private func handleTag(_ request: JsonRpcRequest) throws -> Any {
        let text = try request.requireString("text")
        let langStr = request.string("language")
        let schemeNames = request.stringArray("schemes") ?? ["lexicalClass"]

        let language = langStr.map { NLLanguage(rawValue: $0) }

        let schemes = schemeNames.compactMap { name -> NLTagScheme? in
            switch name {
            case "lexicalClass": return .lexicalClass
            case "nameType": return .nameType
            case "lemma": return .lemma
            case "sentimentScore": return .sentimentScore
            case "language": return .language
            default: return nil
            }
        }

        guard !schemes.isEmpty else {
            throw JsonRpcError.invalidParams("No valid schemes provided. Use: lexicalClass, nameType, lemma, sentimentScore, language")
        }

        let tokens = try provider.tag(text: text, language: language, schemes: schemes)
        return ["tokens": tokens] as [String: Any]
    }

    private func handleSentiment(_ request: JsonRpcRequest) throws -> Any {
        let text = try request.requireString("text")
        let score = try provider.sentiment(text: text)
        let label: String
        if score > 0.1 { label = "positive" }
        else if score < -0.1 { label = "negative" }
        else { label = "neutral" }

        return [
            "score": score,
            "label": label
        ] as [String: Any]
    }

    private func handleLanguage(_ request: JsonRpcRequest) throws -> Any {
        let text = try request.requireString("text")
        let (language, confidence) = try provider.detectLanguage(text: text)
        return [
            "language": language,
            "confidence": confidence
        ] as [String: Any]
    }
}
