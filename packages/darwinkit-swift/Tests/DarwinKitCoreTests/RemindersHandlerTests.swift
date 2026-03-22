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

// MARK: - Tests (placeholder -- handler tests added in Task 6)
