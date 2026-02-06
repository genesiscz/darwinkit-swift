import ArgumentParser
import DarwinKitCore
import Foundation

@main
struct DarwinKitCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "darwinkit",
        abstract: "Expose Apple's on-device ML frameworks via JSON-RPC over stdio.",
        version: JsonRpcServer.version,
        subcommands: [Serve.self, Query.self],
        defaultSubcommand: Serve.self
    )
}

struct Serve: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Run in server mode — reads JSON-RPC from stdin, writes responses to stdout."
    )

    mutating func run() {
        let router = buildRouter()
        let server = JsonRpcServer(router: router)
        server.start()
    }
}

struct Query: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Execute a single JSON-RPC request and exit."
    )

    @Argument(help: "JSON-RPC request string")
    var json: String

    mutating func run() throws {
        let router = buildRouter()

        let decoder = JSONDecoder()
        guard let data = json.data(using: .utf8) else {
            throw ValidationError("Invalid UTF-8 input")
        }

        let request = try decoder.decode(JsonRpcRequest.self, from: data)
        let result = try router.dispatch(request)

        let response = JsonRpcResponse.success(id: request.id, result: result)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let output = try encoder.encode(response)
        print(String(data: output, encoding: .utf8)!)
    }
}

/// Central router factory — all handlers registered here.
func buildRouter() -> MethodRouter {
    let router = MethodRouter()
    router.register(SystemHandler(router: router))
    router.register(NLPHandler())
    router.register(VisionHandler())
    return router
}
