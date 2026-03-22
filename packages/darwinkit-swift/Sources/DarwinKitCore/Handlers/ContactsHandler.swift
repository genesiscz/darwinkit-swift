import Foundation

/// Handles all contacts.* methods: list, get, search, authorized.
public final class ContactsHandler: MethodHandler {
    private let provider: ContactsProvider

    public var methods: [String] {
        ["contacts.authorized", "contacts.list", "contacts.get", "contacts.search"]
    }

    public init(provider: ContactsProvider) {
        self.provider = provider
    }

    public func handle(_ request: JsonRpcRequest) throws -> Any {
        switch request.method {
        case "contacts.authorized":
            return try handleAuthorized(request)
        case "contacts.list":
            return try handleList(request)
        case "contacts.get":
            return try handleGet(request)
        case "contacts.search":
            return try handleSearch(request)
        default:
            throw JsonRpcError.methodNotFound(request.method)
        }
    }

    public func capability(for method: String) -> MethodCapability {
        MethodCapability(available: true, note: "Requires Contacts permission")
    }

    // MARK: - Method Implementations

    private func handleAuthorized(_ request: JsonRpcRequest) throws -> Any {
        let result = try provider.checkAuthorization()
        return result.toDict()
    }

    private func handleList(_ request: JsonRpcRequest) throws -> Any {
        let limit = request.int("limit")
        let contacts = try provider.listContacts(limit: limit)
        return ["contacts": contacts.map { $0.toDict() }] as [String: Any]
    }

    private func handleGet(_ request: JsonRpcRequest) throws -> Any {
        let identifier = try request.requireString("identifier")
        let contact = try provider.getContact(identifier: identifier)
        return contact.toDict()
    }

    private func handleSearch(_ request: JsonRpcRequest) throws -> Any {
        let query = try request.requireString("query")
        let limit = request.int("limit")
        let contacts = try provider.searchContacts(query: query, limit: limit)
        return ["contacts": contacts.map { $0.toDict() }] as [String: Any]
    }
}
