import Foundation
import NaturalLanguage

// MARK: - Provider Protocol

public protocol NLPProvider {
    func embed(text: String, language: NLLanguage, type: EmbedType) throws -> [Double]
    func distance(text1: String, text2: String, language: NLLanguage, type: EmbedType) throws -> Double
    func neighbors(text: String, language: NLLanguage, type: EmbedType, count: Int) throws -> [(String, Double)]
    func tag(text: String, language: NLLanguage?, schemes: [NLTagScheme]) throws -> [[String: Any]]
    func sentiment(text: String) throws -> Double
    func detectLanguage(text: String) throws -> (String, Double)
    func supportedEmbeddingLanguages() -> [String]
}

public enum EmbedType: String {
    case word
    case sentence
}

// MARK: - Apple Implementation

public struct AppleNLPProvider: NLPProvider {

    public init() {}

    public func embed(text: String, language: NLLanguage, type: EmbedType) throws -> [Double] {
        let embedding = try getEmbedding(language: language, type: type)
        guard let vector = embedding.vector(for: text) else {
            let reason = type == .word ? "Word not in vocabulary" : "Could not compute embedding"
            throw JsonRpcError.frameworkUnavailable(reason)
        }
        return vector
    }

    public func distance(text1: String, text2: String, language: NLLanguage, type: EmbedType) throws -> Double {
        let embedding = try getEmbedding(language: language, type: type)
        return embedding.distance(between: text1, and: text2)
    }

    public func neighbors(text: String, language: NLLanguage, type: EmbedType, count: Int) throws -> [(String, Double)] {
        let embedding = try getEmbedding(language: language, type: type)
        var results: [(String, Double)] = []
        embedding.enumerateNeighbors(for: text, maximumCount: count) { neighbor, dist in
            results.append((neighbor, dist))
            return true
        }
        return results
    }

    public func tag(text: String, language: NLLanguage?, schemes: [NLTagScheme]) throws -> [[String: Any]] {
        let tagger = NLTagger(tagSchemes: schemes)
        tagger.string = text
        if let lang = language {
            tagger.setLanguage(lang, range: text.startIndex..<text.endIndex)
        }

        var tokens: [[String: Any]] = []

        // Use nameType with joinNames if requested, otherwise use first scheme
        let primaryScheme = schemes.contains(.nameType) ? NLTagScheme.nameType : schemes[0]
        var options: NLTagger.Options = [.omitPunctuation, .omitWhitespace]
        if schemes.contains(.nameType) { options.insert(.joinNames) }

        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: primaryScheme,
            options: options
        ) { _, tokenRange in
            let tokenText = String(text[tokenRange])
            var tags: [String: String] = [:]

            for scheme in schemes {
                let (tag, _) = tagger.tag(at: tokenRange.lowerBound, unit: .word, scheme: scheme)
                if let tag = tag {
                    tags[scheme.rawValue] = tag.rawValue
                }
            }

            tokens.append(["text": tokenText, "tags": tags])
            return true
        }

        return tokens
    }

    public func sentiment(text: String) throws -> Double {
        let tagger = NLTagger(tagSchemes: [.sentimentScore])
        tagger.string = text
        let (tag, _) = tagger.tag(at: text.startIndex, unit: .paragraph, scheme: .sentimentScore)
        guard let scoreStr = tag?.rawValue, let score = Double(scoreStr) else {
            return 0.0
        }
        return score
    }

    public func detectLanguage(text: String) throws -> (String, Double) {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let lang = recognizer.dominantLanguage else {
            throw JsonRpcError.frameworkUnavailable("Could not detect language")
        }
        let hypotheses = recognizer.languageHypotheses(withMaximum: 1)
        let confidence = hypotheses[lang] ?? 0.0
        return (lang.rawValue, confidence)
    }

    public func supportedEmbeddingLanguages() -> [String] {
        // These 7 languages have built-in Apple word/sentence embeddings
        ["en", "es", "fr", "de", "it", "pt", "zh-Hans"]
    }

    // MARK: - Private

    private func getEmbedding(language: NLLanguage, type: EmbedType) throws -> NLEmbedding {
        let embedding: NLEmbedding?
        switch type {
        case .word:
            embedding = NLEmbedding.wordEmbedding(for: language)
        case .sentence:
            if #available(macOS 11, *) {
                embedding = NLEmbedding.sentenceEmbedding(for: language)
            } else {
                throw JsonRpcError.osVersionTooOld("Sentence embeddings require macOS 11+")
            }
        }

        guard let emb = embedding else {
            throw JsonRpcError.frameworkUnavailable("No \(type) embedding available for \(language.rawValue)")
        }
        return emb
    }
}
