import Foundation
import Testing
@testable import DarwinKitCore

// MARK: - Mock Provider

struct MockCalendarProvider: CalendarProvider {
    var calendars: [CalendarInfo] = []
    var events: [CalendarEventInfo] = []
    var authResult = CalendarAuthorizationResult(status: "fullAccess", authorized: true)
    var shouldThrow: JsonRpcError? = nil

    func checkAuthorization() throws -> CalendarAuthorizationResult {
        if let err = shouldThrow { throw err }
        return authResult
    }

    func listCalendars() throws -> [CalendarInfo] {
        if let err = shouldThrow { throw err }
        return calendars
    }

    func fetchEvents(startDate: String, endDate: String, calendarIdentifiers: [String]?) throws -> [CalendarEventInfo] {
        if let err = shouldThrow { throw err }
        if let ids = calendarIdentifiers {
            return events.filter { ids.contains($0.calendarIdentifier) }
        }
        return events
    }

    func getEvent(identifier: String) throws -> CalendarEventInfo {
        if let err = shouldThrow { throw err }
        guard let event = events.first(where: { $0.identifier == identifier }) else {
            throw JsonRpcError.invalidParams("Event not found: \(identifier)")
        }
        return event
    }
}

// MARK: - Test Helpers

private func makeSampleCalendar(
    identifier: String = "cal-1",
    title: String = "Personal"
) -> CalendarInfo {
    CalendarInfo(
        identifier: identifier, title: title, type: "local",
        color: "#FF0000", isImmutable: false, allowsContentModifications: true
    )
}

private func makeSampleEvent(
    identifier: String = "evt-1",
    title: String = "Team Meeting",
    calendarIdentifier: String = "cal-1"
) -> CalendarEventInfo {
    CalendarEventInfo(
        identifier: identifier, title: title,
        startDate: "2026-03-22T10:00:00.000Z",
        endDate: "2026-03-22T11:00:00.000Z",
        isAllDay: false, location: "Conference Room A",
        notes: "Discuss quarterly goals",
        calendarIdentifier: calendarIdentifier,
        calendarTitle: "Personal", url: nil
    )
}

private func makeRequest(method: String, params: [String: Any] = [:]) -> JsonRpcRequest {
    let codableParams = params.mapValues { AnyCodable($0) }
    return JsonRpcRequest(id: "test", method: method, params: codableParams)
}

// MARK: - Tests (placeholder -- handler tests added in Task 4)
