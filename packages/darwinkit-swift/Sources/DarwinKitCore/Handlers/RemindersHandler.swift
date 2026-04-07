import Foundation

/// Handles all reminders.* methods: authorized, lists, items.
public final class RemindersHandler: MethodHandler {
    private let provider: RemindersProvider

    public var methods: [String] {
        [
            "reminders.authorized", "reminders.lists", "reminders.items",
            "reminders.save_item", "reminders.remove_item", "reminders.complete_item",
            "reminders.incomplete", "reminders.completed",
        ]
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
        case "reminders.save_item":
            return try handleSaveItem(request)
        case "reminders.remove_item":
            return try handleRemoveItem(request)
        case "reminders.complete_item":
            return try handleCompleteItem(request)
        case "reminders.incomplete":
            return try handleIncomplete(request)
        case "reminders.completed":
            return try handleCompleted(request)
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

    // MARK: - Write Methods

    private func handleSaveItem(_ request: JsonRpcRequest) throws -> Any {
        let calendarIdentifier = try request.requireString("calendar_identifier")
        let title = try request.requireString("title")
        let id = request.string("id")
        let dueDate = request.string("due_date")
        let startDate = request.string("start_date")
        let priority = request.int("priority")
        let notes = request.string("notes")
        let completed = request.bool("completed")
        let url = request.string("url")
        let commit = request.bool("commit") ?? true

        let result = try provider.saveReminder(
            id: id, calendarIdentifier: calendarIdentifier, title: title,
            dueDate: dueDate, startDate: startDate, priority: priority,
            notes: notes, completed: completed, url: url,
            commit: commit
        )
        return result.toDict()
    }

    private func handleRemoveItem(_ request: JsonRpcRequest) throws -> Any {
        let identifier = try request.requireString("identifier")
        let commit = request.bool("commit") ?? true
        let removed = try provider.removeReminder(identifier: identifier, commit: commit)
        return OkResult(ok: removed).toDict()
    }

    private func handleCompleteItem(_ request: JsonRpcRequest) throws -> Any {
        let identifier = try request.requireString("identifier")
        let reminder = try provider.completeReminder(identifier: identifier)
        return reminder.toDict()
    }

    private func handleIncomplete(_ request: JsonRpcRequest) throws -> Any {
        let startDate = request.string("start_date")
        let endDate = request.string("end_date")
        let listIdentifiers = request.stringArray("list_identifiers")
        let reminders = try provider.fetchIncompleteReminders(
            startDate: startDate, endDate: endDate, listIdentifiers: listIdentifiers
        )
        return ["reminders": reminders.map { $0.toDict() }] as [String: Any]
    }

    private func handleCompleted(_ request: JsonRpcRequest) throws -> Any {
        let startDate = request.string("start_date")
        let endDate = request.string("end_date")
        let listIdentifiers = request.stringArray("list_identifiers")
        let reminders = try provider.fetchCompletedReminders(
            startDate: startDate, endDate: endDate, listIdentifiers: listIdentifiers
        )
        return ["reminders": reminders.map { $0.toDict() }] as [String: Any]
    }
}
