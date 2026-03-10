import Foundation

/// A handler that can process a JSON-RPC request and return a result.
public protocol MethodHandler {
    /// The method names this handler responds to.
    var methods: [String] { get }

    /// Handle a request and return the result (will be wrapped in JSON-RPC response).
    func handle(_ request: JsonRpcRequest) throws -> Any

    /// Capability info for each method (used in system.capabilities).
    func capability(for method: String) -> MethodCapability
}

public struct MethodCapability {
    public let available: Bool
    public let note: String?

    public init(available: Bool, note: String? = nil) {
        self.available = available
        self.note = note
    }
}

/// Routes JSON-RPC requests to the appropriate handler.
public final class MethodRouter {
    private var handlers: [String: MethodHandler] = [:]

    public init() {}

    public func register(_ handler: MethodHandler) {
        for method in handler.methods {
            handlers[method] = handler
        }
    }

    public func dispatch(_ request: JsonRpcRequest) throws -> Any {
        guard let handler = handlers[request.method] else {
            throw JsonRpcError.methodNotFound("Unknown method: \(request.method)")
        }
        return try handler.handle(request)
    }

    public func availableMethods() -> [String] {
        Array(handlers.keys).sorted()
    }

    public func allCapabilities() -> [String: [String: Any]] {
        var result: [String: [String: Any]] = [:]
        for (method, handler) in handlers {
            let cap = handler.capability(for: method)
            var entry: [String: Any] = ["available": cap.available]
            if let note = cap.note { entry["note"] = note }
            result[method] = entry
        }
        return result
    }
}
