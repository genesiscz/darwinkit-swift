import Foundation

/// Handles all speech.* methods: transcribe, languages, installed_languages,
/// install_language, uninstall_language, capabilities.
public final class SpeechHandler: MethodHandler {
    private let provider: SpeechProvider

    public var methods: [String] {
        [
            "speech.transcribe", "speech.languages", "speech.installed_languages",
            "speech.install_language", "speech.uninstall_language", "speech.capabilities"
        ]
    }

    public init(provider: SpeechProvider) {
        self.provider = provider
    }

    public func handle(_ request: JsonRpcRequest) throws -> Any {
        switch request.method {
        case "speech.transcribe":
            return try handleTranscribe(request)
        case "speech.languages":
            return try handleLanguages(request)
        case "speech.installed_languages":
            return try handleInstalledLanguages(request)
        case "speech.install_language":
            return try handleInstallLanguage(request)
        case "speech.uninstall_language":
            return try handleUninstallLanguage(request)
        case "speech.capabilities":
            return try handleCapabilities(request)
        default:
            throw JsonRpcError.methodNotFound(request.method)
        }
    }

    public func capability(for method: String) -> MethodCapability {
        MethodCapability(available: true, note: "Requires macOS 26+")
    }

    // MARK: - Method Implementations

    private func handleTranscribe(_ request: JsonRpcRequest) throws -> Any {
        let path = try request.requireString("path")
        let language = request.string("language") ?? "en-US"
        let includeTimestamps = request.bool("timestamps") ?? true

        let result = try provider.transcribe(
            path: path, language: language, includeTimestamps: includeTimestamps
        )
        return result.toDict()
    }

    private func handleLanguages(_ request: JsonRpcRequest) throws -> Any {
        let languages = try provider.supportedLanguages()
        return ["languages": languages.map { $0.toDict() }] as [String: Any]
    }

    private func handleInstalledLanguages(_ request: JsonRpcRequest) throws -> Any {
        let languages = try provider.installedLanguages()
        return ["languages": languages.map { $0.toDict() }] as [String: Any]
    }

    private func handleInstallLanguage(_ request: JsonRpcRequest) throws -> Any {
        let locale = try request.requireString("locale")
        try provider.installLanguage(locale: locale)
        return ["ok": true] as [String: Any]
    }

    private func handleUninstallLanguage(_ request: JsonRpcRequest) throws -> Any {
        let locale = try request.requireString("locale")
        try provider.uninstallLanguage(locale: locale)
        return ["ok": true] as [String: Any]
    }

    private func handleCapabilities(_ request: JsonRpcRequest) throws -> Any {
        let caps = try provider.capabilities()
        return caps.toDict()
    }
}
