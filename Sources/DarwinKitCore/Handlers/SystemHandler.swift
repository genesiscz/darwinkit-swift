import Foundation

/// Handles system.capabilities — reports version, OS info, and available methods.
public final class SystemHandler: MethodHandler {
    private let router: MethodRouter

    public var methods: [String] { ["system.capabilities"] }

    public init(router: MethodRouter) {
        self.router = router
    }

    public func handle(_ request: JsonRpcRequest) throws -> Any {
        let processInfo = ProcessInfo.processInfo
        let osVersion = processInfo.operatingSystemVersion

        return [
            "version": JsonRpcServer.version,
            "os": "\(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)",
            "arch": currentArch(),
            "methods": router.allCapabilities()
        ] as [String: Any]
    }

    public func capability(for method: String) -> MethodCapability {
        MethodCapability(available: true)
    }

    private func currentArch() -> String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }
}
