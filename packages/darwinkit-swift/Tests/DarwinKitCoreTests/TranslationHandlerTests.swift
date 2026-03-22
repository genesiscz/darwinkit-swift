import Foundation
import Testing
@testable import DarwinKitCore

// MARK: - Mock Provider

struct MockTranslationProvider: TranslationProvider {
    var translateResult = TranslationResult(text: "Hola mundo", sourceLanguage: "en", targetLanguage: "es")
    var batchResults = [
        TranslationResult(text: "Hola", sourceLanguage: "en", targetLanguage: "es"),
        TranslationResult(text: "Adios", sourceLanguage: "en", targetLanguage: "es"),
    ]
    var languages = [
        TranslationLanguageInfo(locale: "en", name: "English"),
        TranslationLanguageInfo(locale: "es", name: "Spanish"),
        TranslationLanguageInfo(locale: "fr", name: "French"),
    ]
    var pairStatus: TranslationPairStatus = .installed
    var shouldThrow: JsonRpcError? = nil

    func translate(text: String, source: String?, target: String) throws -> TranslationResult {
        if let err = shouldThrow { throw err }
        return translateResult
    }

    func translateBatch(texts: [String], source: String?, target: String) throws -> [TranslationResult] {
        if let err = shouldThrow { throw err }
        return Array(batchResults.prefix(texts.count))
    }

    func supportedLanguages() throws -> [TranslationLanguageInfo] {
        if let err = shouldThrow { throw err }
        return languages
    }

    func languagePairStatus(source: String, target: String) throws -> TranslationPairStatus {
        if let err = shouldThrow { throw err }
        return pairStatus
    }

    func prepare(source: String, target: String) throws {
        if let err = shouldThrow { throw err }
    }
}

// MARK: - Helper

private func makeRequest(method: String, params: [String: Any] = [:]) -> JsonRpcRequest {
    let codableParams = params.mapValues { AnyCodable($0) }
    return JsonRpcRequest(id: "test", method: method, params: codableParams)
}

// MARK: - Tests

@Suite("Translation Handler")
struct TranslationHandlerTests {

    // MARK: - translate.text

    @Test("text returns translated text with source and target")
    func translateTextSuccess() throws {
        let handler = TranslationHandler(provider: MockTranslationProvider())
        let request = makeRequest(method: "translate.text", params: [
            "text": "Hello world", "target": "es"
        ])
        let result = try handler.handle(request) as! [String: Any]

        #expect(result["text"] as? String == "Hola mundo")
        #expect(result["source"] as? String == "en")
        #expect(result["target"] as? String == "es")
    }

    @Test("text accepts explicit source language")
    func translateTextWithSource() throws {
        let handler = TranslationHandler(provider: MockTranslationProvider())
        let request = makeRequest(method: "translate.text", params: [
            "text": "Hello world", "source": "en", "target": "es"
        ])
        let result = try handler.handle(request) as! [String: Any]

        #expect(result["text"] as? String == "Hola mundo")
    }

    @Test("text throws on missing text")
    func translateTextMissingText() {
        let handler = TranslationHandler(provider: MockTranslationProvider())
        let request = makeRequest(method: "translate.text", params: ["target": "es"])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    @Test("text throws on missing target")
    func translateTextMissingTarget() {
        let handler = TranslationHandler(provider: MockTranslationProvider())
        let request = makeRequest(method: "translate.text", params: ["text": "Hello"])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    @Test("text throws on empty text")
    func translateTextEmptyText() {
        let handler = TranslationHandler(provider: MockTranslationProvider())
        let request = makeRequest(method: "translate.text", params: [
            "text": "", "target": "es"
        ])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    // MARK: - translate.batch

    @Test("batch returns array of translations")
    func translateBatchSuccess() throws {
        let handler = TranslationHandler(provider: MockTranslationProvider())
        let request = makeRequest(method: "translate.batch", params: [
            "texts": ["Hello", "Goodbye"], "target": "es"
        ])
        let result = try handler.handle(request) as! [String: Any]
        let translations = result["translations"] as! [[String: Any]]

        #expect(translations.count == 2)
        #expect(translations[0]["text"] as? String == "Hola")
        #expect(translations[1]["text"] as? String == "Adios")
    }

    @Test("batch throws on empty texts array")
    func translateBatchEmpty() {
        let handler = TranslationHandler(provider: MockTranslationProvider())
        let request = makeRequest(method: "translate.batch", params: [
            "texts": [] as [String], "target": "es"
        ])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    @Test("batch throws on missing texts")
    func translateBatchMissingTexts() {
        let handler = TranslationHandler(provider: MockTranslationProvider())
        let request = makeRequest(method: "translate.batch", params: ["target": "es"])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    @Test("batch throws on missing target")
    func translateBatchMissingTarget() {
        let handler = TranslationHandler(provider: MockTranslationProvider())
        let request = makeRequest(method: "translate.batch", params: [
            "texts": ["Hello"]
        ])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    // MARK: - translate.languages

    @Test("languages returns list of supported languages")
    func languagesSuccess() throws {
        let handler = TranslationHandler(provider: MockTranslationProvider())
        let request = makeRequest(method: "translate.languages")
        let result = try handler.handle(request) as! [String: Any]
        let languages = result["languages"] as! [[String: Any]]

        #expect(languages.count == 3)
        #expect(languages[0]["locale"] as? String == "en")
        #expect(languages[0]["name"] as? String == "English")
    }

    // MARK: - translate.language_status

    @Test("language_status returns status for language pair")
    func languageStatusSuccess() throws {
        let handler = TranslationHandler(provider: MockTranslationProvider())
        let request = makeRequest(method: "translate.language_status", params: [
            "source": "en", "target": "es"
        ])
        let result = try handler.handle(request) as! [String: Any]

        #expect(result["status"] as? String == "installed")
        #expect(result["source"] as? String == "en")
        #expect(result["target"] as? String == "es")
    }

    @Test("language_status throws on missing source")
    func languageStatusMissingSource() {
        let handler = TranslationHandler(provider: MockTranslationProvider())
        let request = makeRequest(method: "translate.language_status", params: ["target": "es"])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    @Test("language_status throws on missing target")
    func languageStatusMissingTarget() {
        let handler = TranslationHandler(provider: MockTranslationProvider())
        let request = makeRequest(method: "translate.language_status", params: ["source": "en"])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    // MARK: - translate.prepare

    @Test("prepare returns ok for valid pair")
    func prepareSuccess() throws {
        let handler = TranslationHandler(provider: MockTranslationProvider())
        let request = makeRequest(method: "translate.prepare", params: [
            "source": "en", "target": "es"
        ])
        let result = try handler.handle(request) as! [String: Any]

        #expect(result["ok"] as? Bool == true)
        #expect(result["source"] as? String == "en")
        #expect(result["target"] as? String == "es")
    }

    @Test("prepare throws on missing source")
    func prepareMissingSource() {
        let handler = TranslationHandler(provider: MockTranslationProvider())
        let request = makeRequest(method: "translate.prepare", params: ["target": "es"])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    @Test("prepare throws on missing target")
    func prepareMissingTarget() {
        let handler = TranslationHandler(provider: MockTranslationProvider())
        let request = makeRequest(method: "translate.prepare", params: ["source": "en"])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    // MARK: - Method registration

    @Test("handler registers all 5 translate methods")
    func methodRegistration() {
        let handler = TranslationHandler(provider: MockTranslationProvider())
        let expected: Set<String> = [
            "translate.text", "translate.batch", "translate.languages",
            "translate.language_status", "translate.prepare"
        ]

        #expect(Set(handler.methods) == expected)
    }

    @Test("handler reports capabilities for all methods")
    func capabilities() {
        let handler = TranslationHandler(provider: MockTranslationProvider())

        for method in handler.methods {
            let cap = handler.capability(for: method)
            #expect(cap.available == true)
        }
    }

    // MARK: - Provider error propagation

    @Test("provider errors propagate through handler")
    func providerError() {
        var mock = MockTranslationProvider()
        mock.shouldThrow = .frameworkUnavailable("Translation not available")
        let handler = TranslationHandler(provider: mock)
        let request = makeRequest(method: "translate.text", params: [
            "text": "Hello", "target": "es"
        ])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }
}
