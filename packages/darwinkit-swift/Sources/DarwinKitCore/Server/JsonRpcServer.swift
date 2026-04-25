import AppKit
import Darwin
import DarwinKitObjC
import Foundation

/// Protocol for handlers that need to push async notifications to the parent process.
public protocol NotificationSink: AnyObject {
    func sendNotification(method: String, params: Any)
}

/// Handles JSON-RPC communication over stdin/stdout.
/// Reads NDJSON requests from stdin, dispatches to registered handlers, writes responses to stdout.
public final class JsonRpcServer: NotificationSink {
    public static let version = "0.1.0"

    private let router: MethodRouter
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(router: MethodRouter) {
        self.router = router
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.sortedKeys]
        self.decoder = JSONDecoder()
    }

    /// Start the server. Blocks until stdin is closed.
    public func start() {
        // Register as a background app so macOS treats us as a proper application.
        // This enables system dialogs (notification permission prompt) and
        // notification delivery via UNUserNotificationCenter.
        NSApplication.shared.setActivationPolicy(.accessory)

        // Ignore SIGPIPE so broken-pipe returns EPIPE instead of killing the process
        signal(SIGPIPE, SIG_IGN)

        // Disable stdout buffering — critical when piped to a parent process.
        // Without this, responses accumulate in a 4KB buffer and the parent never sees them.
        setbuf(stdout, nil)

        // Send ready notification so parent knows we're alive and what we support
        let capabilities = router.availableMethods()
        sendNotification(method: "ready", params: [
            "version": JsonRpcServer.version,
            "capabilities": capabilities
        ])

        // Read stdin on a background thread, dispatch to main thread for framework calls
        let stdinThread = Thread { [self] in
            while let line = readLine(strippingNewline: true) {
                if line.isEmpty { continue }
                self.handleLine(line)
            }
            // stdin closed — parent process is done
            self.log("stdin closed, shutting down")
            exit(0)
        }
        stdinThread.name = "darwinkit.stdin"
        stdinThread.start()

        // Run NSApplication event loop (needed for async Apple framework callbacks
        // and for system dialogs like notification permission prompts)
        NSApp.run()
    }

    private func handleLine(_ line: String) {
        guard let data = line.data(using: .utf8) else {
            sendError(id: nil, error: .parseError("Invalid UTF-8 input"))
            return
        }

        let request: JsonRpcRequest
        do {
            request = try decoder.decode(JsonRpcRequest.self, from: data)
        } catch {
            sendError(id: nil, error: .parseError("Malformed JSON: \(error.localizedDescription)"))
            return
        }

        guard request.jsonrpc == "2.0" else {
            sendError(id: request.id, error: .invalidRequest("jsonrpc must be \"2.0\""))
            return
        }

        // Handle cancellation notifications
        if request.method == "$/cancel" {
            // TODO: implement cancellation for long-running operations
            return
        }

        // Wrap dispatch in an ObjC @try/@catch shim so an Apple framework
        // NSException (e.g. KVC undefined-key inside a typed accessor on
        // macOS 26+) becomes a JSON-RPC error frame instead of aborting
        // the whole process.
        var dispatchResult: Result<Any, JsonRpcError>? = nil
        do {
            try DarwinKitObjC.catchException {
                do {
                    let result = try self.router.dispatch(request)
                    dispatchResult = .success(result)
                } catch let error as JsonRpcError {
                    dispatchResult = .failure(error)
                } catch {
                    dispatchResult = .failure(.internalError(error.localizedDescription))
                }
            }
        } catch {
            let ns = error as NSError
            let name = ns.userInfo[DarwinKitObjCExceptionNameKey] as? String ?? "NSException"
            let reason = ns.userInfo[DarwinKitObjCExceptionReasonKey] as? String ?? ""
            sendError(id: request.id, error: .objcException(name: name, reason: reason))
            return
        }

        switch dispatchResult {
        case .success(let result):
            sendSuccess(id: request.id, result: result)
        case .failure(let error):
            sendError(id: request.id, error: error)
        case .none:
            sendError(id: request.id, error: .internalError("dispatch produced no result"))
        }
    }

    private func sendSuccess(id: String?, result: Any) {
        let response = JsonRpcResponse.success(id: id, result: result)
        writeLine(response)
    }

    private func sendError(id: String?, error: JsonRpcError) {
        let response = JsonRpcResponse.failure(id: id, error: error)
        writeLine(response)
    }

    public func sendNotification(method: String, params: Any) {
        let json: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method,
            "params": params
        ]
        if let data = try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys]),
           let str = String(data: data, encoding: .utf8) {
            safeWriteStdout(str + "\n")
        }
    }

    private func writeLine(_ response: JsonRpcResponse) {
        if let data = try? encoder.encode(response),
           let str = String(data: data, encoding: .utf8) {
            safeWriteStdout(str + "\n")
        }
    }

    /// Write to stdout using POSIX write() — returns silently on broken pipe.
    private func safeWriteStdout(_ string: String) {
        string.utf8.withContiguousStorageIfAvailable { buf in
            _ = Darwin.write(STDOUT_FILENO, buf.baseAddress, buf.count)
        }
    }

    func log(_ message: String) {
        let msg = "[darwinkit] \(message)\n"
        msg.utf8.withContiguousStorageIfAvailable { buf in
            _ = Darwin.write(STDERR_FILENO, buf.baseAddress, buf.count)
        }
    }
}
