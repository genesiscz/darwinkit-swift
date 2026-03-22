import Foundation
import Testing
@testable import DarwinKitCore

// MARK: - Mock Provider

struct MockRemindersProvider: RemindersProvider {
    var lists: [ReminderListInfo] = []
    var reminders: [ReminderInfo] = []
    var authResult = RemindersAuthorizationResult(status: "fullAccess", authorized: true)
    var shouldThrow: JsonRpcError? = nil

    func checkAuthorization() throws -> RemindersAuthorizationResult {
        if let err = shouldThrow { throw err }
        return authResult
    }

    func listReminderLists() throws -> [ReminderListInfo] {
        if let err = shouldThrow { throw err }
        return lists
    }

    func fetchReminders(filter: String?, listIdentifiers: [String]?) throws -> [ReminderInfo] {
        if let err = shouldThrow { throw err }

        var result = reminders

        // Filter by list
        if let ids = listIdentifiers {
            result = result.filter { ids.contains($0.listIdentifier) }
        }

        // Filter by completion status
        switch filter {
        case "completed":
            result = result.filter { $0.isCompleted }
        case "incomplete":
            result = result.filter { !$0.isCompleted }
        default:
            break
        }

        return result
    }
}

// MARK: - Test Helpers

private func makeSampleList(
    identifier: String = "list-1",
    title: String = "Groceries"
) -> ReminderListInfo {
    ReminderListInfo(identifier: identifier, title: title, color: "#34C759")
}

private func makeSampleReminder(
    identifier: String = "rem-1",
    title: String = "Buy milk",
    isCompleted: Bool = false,
    listIdentifier: String = "list-1"
) -> ReminderInfo {
    ReminderInfo(
        identifier: identifier, title: title,
        isCompleted: isCompleted,
        completionDate: isCompleted ? "2026-03-21T15:30:00.000Z" : nil,
        dueDate: "2026-03-22T17:00:00.000Z",
        priority: 0,
        notes: nil,
        listIdentifier: listIdentifier,
        listTitle: "Groceries"
    )
}

private func makeRequest(method: String, params: [String: Any] = [:]) -> JsonRpcRequest {
    let codableParams = params.mapValues { AnyCodable($0) }
    return JsonRpcRequest(id: "test", method: method, params: codableParams)
}

// MARK: - Tests

@Suite("Reminders Handler")
struct RemindersHandlerTests {

    // MARK: - reminders.authorized

    @Test("authorized returns fullAccess status")
    func authorizedSuccess() throws {
        let handler = RemindersHandler(provider: MockRemindersProvider())
        let request = makeRequest(method: "reminders.authorized")
        let result = try handler.handle(request) as! [String: Any]

        #expect(result["status"] as? String == "fullAccess")
        #expect(result["authorized"] as? Bool == true)
    }

    @Test("authorized returns denied status")
    func authorizedDenied() throws {
        var mock = MockRemindersProvider()
        mock.authResult = RemindersAuthorizationResult(status: "denied", authorized: false)
        let handler = RemindersHandler(provider: mock)
        let request = makeRequest(method: "reminders.authorized")
        let result = try handler.handle(request) as! [String: Any]

        #expect(result["status"] as? String == "denied")
        #expect(result["authorized"] as? Bool == false)
    }

    // MARK: - reminders.lists

    @Test("lists returns empty array when none exist")
    func listsEmpty() throws {
        let handler = RemindersHandler(provider: MockRemindersProvider())
        let request = makeRequest(method: "reminders.lists")
        let result = try handler.handle(request) as! [String: Any]
        let lists = result["lists"] as! [[String: Any]]

        #expect(lists.isEmpty)
    }

    @Test("lists returns reminder lists")
    func listsWithEntries() throws {
        var mock = MockRemindersProvider()
        mock.lists = [makeSampleList()]
        let handler = RemindersHandler(provider: mock)
        let request = makeRequest(method: "reminders.lists")
        let result = try handler.handle(request) as! [String: Any]
        let lists = result["lists"] as! [[String: Any]]

        #expect(lists.count == 1)
        #expect(lists[0]["title"] as? String == "Groceries")
        #expect(lists[0]["color"] as? String == "#34C759")
    }

    // MARK: - reminders.items

    @Test("items returns all reminders by default")
    func itemsAll() throws {
        var mock = MockRemindersProvider()
        mock.reminders = [
            makeSampleReminder(identifier: "r1", isCompleted: false),
            makeSampleReminder(identifier: "r2", isCompleted: true),
        ]
        let handler = RemindersHandler(provider: mock)
        let request = makeRequest(method: "reminders.items")
        let result = try handler.handle(request) as! [String: Any]
        let items = result["reminders"] as! [[String: Any]]

        #expect(items.count == 2)
    }

    @Test("items filters by completed")
    func itemsCompleted() throws {
        var mock = MockRemindersProvider()
        mock.reminders = [
            makeSampleReminder(identifier: "r1", isCompleted: false),
            makeSampleReminder(identifier: "r2", isCompleted: true),
        ]
        let handler = RemindersHandler(provider: mock)
        let request = makeRequest(method: "reminders.items", params: ["filter": "completed"])
        let result = try handler.handle(request) as! [String: Any]
        let items = result["reminders"] as! [[String: Any]]

        #expect(items.count == 1)
        #expect(items[0]["is_completed"] as? Bool == true)
    }

    @Test("items filters by incomplete")
    func itemsIncomplete() throws {
        var mock = MockRemindersProvider()
        mock.reminders = [
            makeSampleReminder(identifier: "r1", isCompleted: false),
            makeSampleReminder(identifier: "r2", isCompleted: true),
        ]
        let handler = RemindersHandler(provider: mock)
        let request = makeRequest(method: "reminders.items", params: ["filter": "incomplete"])
        let result = try handler.handle(request) as! [String: Any]
        let items = result["reminders"] as! [[String: Any]]

        #expect(items.count == 1)
        #expect(items[0]["is_completed"] as? Bool == false)
    }

    @Test("items filters by list_identifiers")
    func itemsByList() throws {
        var mock = MockRemindersProvider()
        mock.reminders = [
            makeSampleReminder(identifier: "r1", listIdentifier: "list-1"),
            makeSampleReminder(identifier: "r2", listIdentifier: "list-2"),
        ]
        let handler = RemindersHandler(provider: mock)
        let request = makeRequest(method: "reminders.items", params: [
            "list_identifiers": ["list-1"]
        ])
        let result = try handler.handle(request) as! [String: Any]
        let items = result["reminders"] as! [[String: Any]]

        #expect(items.count == 1)
        #expect(items[0]["identifier"] as? String == "r1")
    }

    // MARK: - Method registration

    @Test("handler registers all 3 reminders methods")
    func methodRegistration() {
        let handler = RemindersHandler(provider: MockRemindersProvider())
        let expected: Set<String> = [
            "reminders.authorized", "reminders.lists", "reminders.items"
        ]
        #expect(Set(handler.methods) == expected)
    }

    // MARK: - Error propagation

    @Test("provider errors propagate through handler")
    func providerError() {
        var mock = MockRemindersProvider()
        mock.shouldThrow = .permissionDenied("Reminders access denied")
        let handler = RemindersHandler(provider: mock)
        let request = makeRequest(method: "reminders.lists")

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }
}
