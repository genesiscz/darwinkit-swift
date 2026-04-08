import Foundation
import Testing
@testable import DarwinKitCore

// MARK: - Mock Provider

struct MockRemindersProvider: RemindersProvider {
    var lists: [ReminderListInfo] = []
    var reminders: [ReminderInfo] = []
    var authResult = RemindersAuthorizationResult(status: "fullAccess", authorized: true)
    var shouldThrow: JsonRpcError? = nil
    var savedReminder = CalendarSaveResult(success: true, identifier: "new-rem-1", error: nil)

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

    func saveReminder(
        id: String?, calendarIdentifier: String, title: String,
        dueDate: String?, startDate: String?, priority: Int?,
        notes: String?, completed: Bool?, url: String?,
        flagged: Bool?, alarms: [[String: Any]]?,
        commit: Bool
    ) throws -> CalendarSaveResult {
        if let err = shouldThrow { throw err }
        return savedReminder
    }

    func removeReminder(identifier: String, commit: Bool) throws -> Bool {
        if let err = shouldThrow { throw err }
        return true
    }

    func completeReminder(identifier: String) throws -> ReminderInfo {
        if let err = shouldThrow { throw err }
        guard let r = reminders.first(where: { $0.identifier == identifier }) else {
            throw JsonRpcError.invalidParams("Not found: \(identifier)")
        }
        return r
    }

    func fetchIncompleteReminders(
        startDate: String?, endDate: String?, listIdentifiers: [String]?
    ) throws -> [ReminderInfo] {
        if let err = shouldThrow { throw err }
        return reminders.filter { !$0.isCompleted }
    }

    func fetchCompletedReminders(
        startDate: String?, endDate: String?, listIdentifiers: [String]?
    ) throws -> [ReminderInfo] {
        if let err = shouldThrow { throw err }
        return reminders.filter { $0.isCompleted }
    }

    func requestFullAccess() throws -> RemindersAuthorizationResult {
        if let err = shouldThrow { throw err }
        return authResult
    }
}

// MARK: - Test Helpers

private func makeSampleList(
    identifier: String = "list-1",
    title: String = "Groceries"
) -> ReminderListInfo {
    ReminderListInfo(identifier: identifier, title: title, color: "#34C759", source: "iCloud")
}

private func makeSampleReminder(
    identifier: String = "rem-1",
    title: String = "Buy milk",
    isCompleted: Bool = false,
    isFlagged: Bool = false,
    listIdentifier: String = "list-1"
) -> ReminderInfo {
    ReminderInfo(
        identifier: identifier, title: title,
        isCompleted: isCompleted,
        completionDate: isCompleted ? "2026-03-21T15:30:00.000Z" : nil,
        dueDate: "2026-03-22T17:00:00.000Z",
        startDate: nil,
        priority: 0,
        notes: nil,
        url: nil,
        hasAlarms: false,
        alarms: [],
        isFlagged: isFlagged,
        listIdentifier: listIdentifier,
        listTitle: "Groceries",
        externalIdentifier: nil
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

    @Test("handler registers all 9 reminders methods")
    func methodRegistration() {
        let handler = RemindersHandler(provider: MockRemindersProvider())
        let expected: Set<String> = [
            "reminders.authorized", "reminders.lists", "reminders.items",
            "reminders.save_item", "reminders.remove_item", "reminders.complete_item",
            "reminders.incomplete", "reminders.completed",
            "reminders.request_full_access",
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

    // MARK: - reminders.request_full_access

    @Test("request_full_access returns authorization result")
    func requestFullAccess() throws {
        let handler = RemindersHandler(provider: MockRemindersProvider())
        let request = makeRequest(method: "reminders.request_full_access")
        let result = try handler.handle(request) as! [String: Any]

        #expect(result["status"] as? String == "fullAccess")
        #expect(result["authorized"] as? Bool == true)
    }

    // MARK: - ReminderInfo new fields

    @Test("ReminderInfo includes is_flagged and alarms in dict")
    func reminderInfoNewFields() {
        let alarm = AlarmInfo(
            type: "time", relativeOffset: -3600,
            absoluteDate: nil, location: nil, proximity: nil
        )
        let reminder = ReminderInfo(
            identifier: "r1", title: "Test",
            isCompleted: false, completionDate: nil,
            dueDate: nil, startDate: nil,
            priority: 1, notes: nil, url: nil,
            hasAlarms: true, alarms: [alarm], isFlagged: true,
            listIdentifier: "list-1", listTitle: "Tasks",
            externalIdentifier: nil
        )
        let dict = reminder.toDict()

        #expect(dict["is_flagged"] as? Bool == true)
        let alarmsArr = dict["alarms"] as! [[String: Any]]
        #expect(alarmsArr.count == 1)
        #expect(alarmsArr[0]["type"] as? String == "time")
        #expect(alarmsArr[0]["relative_offset"] as? Double == -3600)
    }

    @Test("AlarmInfo location type includes coordinates")
    func alarmInfoLocation() {
        let loc = AlarmLocationInfo(
            title: "Home", latitude: 37.7749, longitude: -122.4194, radius: 100
        )
        let alarm = AlarmInfo(
            type: "location", relativeOffset: nil,
            absoluteDate: nil, location: loc, proximity: "leave"
        )
        let dict = alarm.toDict()

        #expect(dict["type"] as? String == "location")
        #expect(dict["proximity"] as? String == "leave")
        let locDict = dict["location"] as! [String: Any]
        #expect(locDict["title"] as? String == "Home")
        #expect(locDict["latitude"] as? Double == 37.7749)
    }
}
