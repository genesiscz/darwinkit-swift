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

// MARK: - Tests

@Suite("Calendar Handler")
struct CalendarHandlerTests {

    // MARK: - calendar.authorized

    @Test("authorized returns fullAccess status")
    func authorizedSuccess() throws {
        let handler = CalendarHandler(provider: MockCalendarProvider())
        let request = makeRequest(method: "calendar.authorized")
        let result = try handler.handle(request) as! [String: Any]

        #expect(result["status"] as? String == "fullAccess")
        #expect(result["authorized"] as? Bool == true)
    }

    @Test("authorized returns denied status")
    func authorizedDenied() throws {
        var mock = MockCalendarProvider()
        mock.authResult = CalendarAuthorizationResult(status: "denied", authorized: false)
        let handler = CalendarHandler(provider: mock)
        let request = makeRequest(method: "calendar.authorized")
        let result = try handler.handle(request) as! [String: Any]

        #expect(result["status"] as? String == "denied")
        #expect(result["authorized"] as? Bool == false)
    }

    // MARK: - calendar.calendars

    @Test("calendars returns empty array when none exist")
    func calendarsEmpty() throws {
        let handler = CalendarHandler(provider: MockCalendarProvider())
        let request = makeRequest(method: "calendar.calendars")
        let result = try handler.handle(request) as! [String: Any]
        let calendars = result["calendars"] as! [[String: Any]]

        #expect(calendars.isEmpty)
    }

    @Test("calendars returns calendar list")
    func calendarsWithEntries() throws {
        var mock = MockCalendarProvider()
        mock.calendars = [makeSampleCalendar()]
        let handler = CalendarHandler(provider: mock)
        let request = makeRequest(method: "calendar.calendars")
        let result = try handler.handle(request) as! [String: Any]
        let calendars = result["calendars"] as! [[String: Any]]

        #expect(calendars.count == 1)
        #expect(calendars[0]["title"] as? String == "Personal")
        #expect(calendars[0]["type"] as? String == "local")
    }

    // MARK: - calendar.events

    @Test("events returns events in date range")
    func eventsSuccess() throws {
        var mock = MockCalendarProvider()
        mock.events = [makeSampleEvent()]
        let handler = CalendarHandler(provider: mock)
        let request = makeRequest(method: "calendar.events", params: [
            "start_date": "2026-03-22T00:00:00.000Z",
            "end_date": "2026-03-23T00:00:00.000Z",
        ])
        let result = try handler.handle(request) as! [String: Any]
        let events = result["events"] as! [[String: Any]]

        #expect(events.count == 1)
        #expect(events[0]["title"] as? String == "Team Meeting")
    }

    @Test("events throws on missing start_date")
    func eventsMissingStart() {
        let handler = CalendarHandler(provider: MockCalendarProvider())
        let request = makeRequest(method: "calendar.events", params: [
            "end_date": "2026-03-23T00:00:00.000Z"
        ])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    @Test("events throws on missing end_date")
    func eventsMissingEnd() {
        let handler = CalendarHandler(provider: MockCalendarProvider())
        let request = makeRequest(method: "calendar.events", params: [
            "start_date": "2026-03-22T00:00:00.000Z"
        ])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    @Test("events filters by calendar_identifiers")
    func eventsFilterByCalendar() throws {
        var mock = MockCalendarProvider()
        mock.events = [
            makeSampleEvent(identifier: "e1", calendarIdentifier: "cal-1"),
            makeSampleEvent(identifier: "e2", calendarIdentifier: "cal-2"),
        ]
        let handler = CalendarHandler(provider: mock)
        let request = makeRequest(method: "calendar.events", params: [
            "start_date": "2026-03-22T00:00:00.000Z",
            "end_date": "2026-03-23T00:00:00.000Z",
            "calendar_identifiers": ["cal-1"],
        ])
        let result = try handler.handle(request) as! [String: Any]
        let events = result["events"] as! [[String: Any]]

        #expect(events.count == 1)
        #expect(events[0]["identifier"] as? String == "e1")
    }

    // MARK: - calendar.event

    @Test("event returns single event by identifier")
    func eventSuccess() throws {
        var mock = MockCalendarProvider()
        mock.events = [makeSampleEvent(identifier: "evt-abc")]
        let handler = CalendarHandler(provider: mock)
        let request = makeRequest(method: "calendar.event", params: ["identifier": "evt-abc"])
        let result = try handler.handle(request) as! [String: Any]

        #expect(result["identifier"] as? String == "evt-abc")
        #expect(result["title"] as? String == "Team Meeting")
    }

    @Test("event throws on missing identifier")
    func eventMissingId() {
        let handler = CalendarHandler(provider: MockCalendarProvider())
        let request = makeRequest(method: "calendar.event")

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    @Test("event throws when not found")
    func eventNotFound() {
        let handler = CalendarHandler(provider: MockCalendarProvider())
        let request = makeRequest(method: "calendar.event", params: ["identifier": "nonexistent"])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    // MARK: - Method registration

    @Test("handler registers all 4 calendar methods")
    func methodRegistration() {
        let handler = CalendarHandler(provider: MockCalendarProvider())
        let expected: Set<String> = [
            "calendar.authorized", "calendar.calendars", "calendar.events", "calendar.event"
        ]
        #expect(Set(handler.methods) == expected)
    }

    // MARK: - Error propagation

    @Test("provider errors propagate through handler")
    func providerError() {
        var mock = MockCalendarProvider()
        mock.shouldThrow = .permissionDenied("Calendar access denied")
        let handler = CalendarHandler(provider: mock)
        let request = makeRequest(method: "calendar.calendars")

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }
}
