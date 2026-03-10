import Foundation
import Testing
@testable import DarwinKitCore

@Suite("JSON-RPC Protocol")
struct ProtocolTests {

    @Test("Decode valid request")
    func decodeValidRequest() throws {
        let json = """
        {"jsonrpc":"2.0","id":"1","method":"system.capabilities","params":{}}
        """
        let data = Data(json.utf8)
        let request = try JSONDecoder().decode(JsonRpcRequest.self, from: data)
        #expect(request.jsonrpc == "2.0")
        #expect(request.id == "1")
        #expect(request.method == "system.capabilities")
    }

    @Test("Decode request with string params")
    func decodeWithParams() throws {
        let json = """
        {"jsonrpc":"2.0","id":"2","method":"nlp.embed","params":{"text":"hello","language":"en"}}
        """
        let data = Data(json.utf8)
        let request = try JSONDecoder().decode(JsonRpcRequest.self, from: data)
        #expect(request.string("text") == "hello")
        #expect(request.string("language") == "en")
    }

    @Test("Decode request without id (notification)")
    func decodeNotification() throws {
        let json = """
        {"jsonrpc":"2.0","method":"$/cancel","params":{"id":"req-1"}}
        """
        let data = Data(json.utf8)
        let request = try JSONDecoder().decode(JsonRpcRequest.self, from: data)
        #expect(request.id == nil)
        #expect(request.method == "$/cancel")
    }

    @Test("Encode success response")
    func encodeSuccess() throws {
        let response = JsonRpcResponse.success(id: "1", result: ["key": "value"])
        let data = try JSONEncoder().encode(response)
        let str = String(data: data, encoding: .utf8)!
        #expect(str.contains("\"id\":\"1\""))
        #expect(str.contains("\"jsonrpc\":\"2.0\""))
    }

    @Test("Encode error response")
    func encodeError() throws {
        let response = JsonRpcResponse.failure(id: "1", error: .methodNotFound("test.method"))
        let data = try JSONEncoder().encode(response)
        let str = String(data: data, encoding: .utf8)!
        #expect(str.contains("-32601"))
        #expect(str.contains("test.method"))
    }

    @Test("Error codes are correct")
    func errorCodes() {
        #expect(JsonRpcError.parseError("").body.code == -32700)
        #expect(JsonRpcError.invalidRequest("").body.code == -32600)
        #expect(JsonRpcError.methodNotFound("").body.code == -32601)
        #expect(JsonRpcError.invalidParams("").body.code == -32602)
        #expect(JsonRpcError.frameworkUnavailable("").body.code == -32001)
        #expect(JsonRpcError.permissionDenied("").body.code == -32002)
        #expect(JsonRpcError.osVersionTooOld("").body.code == -32003)
        #expect(JsonRpcError.operationCancelled.body.code == -32004)
        #expect(JsonRpcError.internalError("").body.code == -32603)
    }

    @Test("requireString throws on missing param")
    func requireStringMissing() {
        let request = JsonRpcRequest(id: "1", method: "test")
        #expect(throws: (any Error).self) {
            try request.requireString("missing")
        }
    }

    @Test("AnyCodable round-trips all types")
    func anyCodableRoundTrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        // String
        let strData = try encoder.encode(AnyCodable("hello"))
        let strDecoded = try decoder.decode(AnyCodable.self, from: strData)
        #expect(strDecoded.stringValue == "hello")

        // Int
        let intData = try encoder.encode(AnyCodable(42))
        let intDecoded = try decoder.decode(AnyCodable.self, from: intData)
        #expect(intDecoded.intValue == 42)

        // Bool
        let boolData = try encoder.encode(AnyCodable(true))
        let boolDecoded = try decoder.decode(AnyCodable.self, from: boolData)
        #expect(boolDecoded.boolValue == true)

        // Array
        let arrData = try encoder.encode(AnyCodable(["a", "b"]))
        let arrDecoded = try decoder.decode(AnyCodable.self, from: arrData)
        #expect(arrDecoded.stringArrayValue == ["a", "b"])
    }

    @Test("Router dispatches to correct handler")
    func routerDispatch() throws {
        let router = MethodRouter()
        router.register(SystemHandler(router: router))

        let request = JsonRpcRequest(id: "1", method: "system.capabilities")
        let result = try router.dispatch(request)

        // Should return a dict with "version" key
        let dict = result as! [String: Any]
        #expect(dict["version"] as? String == JsonRpcServer.version)
    }

    @Test("Router throws on unknown method")
    func routerUnknown() {
        let router = MethodRouter()
        let request = JsonRpcRequest(id: "1", method: "nonexistent")

        #expect(throws: JsonRpcError.self) {
            try router.dispatch(request)
        }
    }
}
