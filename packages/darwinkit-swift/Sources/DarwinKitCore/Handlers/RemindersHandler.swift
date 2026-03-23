import Foundation

/// Handles all reminders.* methods: authorized, lists, items.
public final class RemindersHandler: MethodHandler {
    private let provider: RemindersProvider

    public var methods: [String] {
        ["reminders.authorized", "reminders.lists", "reminders.items"]
    }

    public init(provider: RemindersProvider) {
        self.provider = provider
    }

    public func handle(_ request: JsonRpcRequest) throws -> Any {
        switch request.method {
        case "reminders.authorized":
            return try handleAuthorized(request)
        case "reminders.lists":
            return try handleLists(request)
        case "reminders.items":
            return try handleItems(request)
        default:
            throw JsonRpcError.methodNotFound(request.method)
        }
    }

    public func capability(for method: String) -> MethodCapability {
        MethodCapability(available: true, note: "Requires Reminders permission (macOS 14+)")
    }

    // MARK: - Method Implementations

    private func handleAuthorized(_ request: JsonRpcRequest) throws -> Any {
        let result = try provider.checkAuthorization()
        return result.toDict()
    }

    private func handleLists(_ request: JsonRpcRequest) throws -> Any {
        let lists = try provider.listReminderLists()
        return ["lists": lists.map { $0.toDict() }] as [String: Any]
    }

    private func handleItems(_ request: JsonRpcRequest) throws -> Any {
        let filter = request.string("filter")
        let listIdentifiers = request.stringArray("list_identifiers")
        let reminders = try provider.fetchReminders(filter: filter, listIdentifiers: listIdentifiers)
        return ["reminders": reminders.map { $0.toDict() }] as [String: Any]
    }
}
