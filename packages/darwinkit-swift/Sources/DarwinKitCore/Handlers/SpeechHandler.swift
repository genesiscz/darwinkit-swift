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
        // Check macOS version (10.15+ required)
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        let requiresMajor = 10
        let requiresMinor = 15

        let isVersionOK: Bool
        if osVersion.majorVersion > requiresMajor {
            isVersionOK = true
        } else if osVersion.majorVersion == requiresMajor {
            isVersionOK = osVersion.minorVersion >= requiresMinor
        } else {
            isVersionOK = false
        }

        if !isVersionOK {
            return MethodCapability(
                available: false,
                note: "Requires macOS 10.15+ (current: \(osVersion.majorVersion).\(osVersion.minorVersion))"
            )
        }

        // Defer to provider's capabilities for further checks
        if let caps = try? provider.capabilities() {
            return MethodCapability(
                available: caps.available,
                note: caps.reason
            )
        }

        return MethodCapability(available: true)
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