import Foundation

/// Handles all calendar.* methods: authorized, calendars, events, event.
public final class CalendarHandler: MethodHandler {
    private let provider: CalendarProvider

    public var methods: [String] {
        ["calendar.authorized", "calendar.calendars", "calendar.events", "calendar.event"]
    }

    public init(provider: CalendarProvider) {
        self.provider = provider
    }

    public func handle(_ request: JsonRpcRequest) throws -> Any {
        switch request.method {
        case "calendar.authorized":
            return try handleAuthorized(request)
        case "calendar.calendars":
            return try handleCalendars(request)
        case "calendar.events":
            return try handleEvents(request)
        case "calendar.event":
            return try handleEvent(request)
        default:
            throw JsonRpcError.methodNotFound(request.method)
        }
    }

    public func capability(for method: String) -> MethodCapability {
        MethodCapability(available: true, note: "Requires Calendar permission (macOS 14+)")
    }

    // MARK: - Method Implementations

    private func handleAuthorized(_ request: JsonRpcRequest) throws -> Any {
        let result = try provider.checkAuthorization()
        return result.toDict()
    }

    private func handleCalendars(_ request: JsonRpcRequest) throws -> Any {
        let calendars = try provider.listCalendars()
        return ["calendars": calendars.map { $0.toDict() }] as [String: Any]
    }

    private func handleEvents(_ request: JsonRpcRequest) throws -> Any {
        let startDate = try request.requireString("start_date")
        let endDate = try request.requireString("end_date")
        let calendarIdentifiers = request.stringArray("calendar_identifiers")
        let events = try provider.fetchEvents(
            startDate: startDate, endDate: endDate,
            calendarIdentifiers: calendarIdentifiers
        )
        return ["events": events.map { $0.toDict() }] as [String: Any]
    }

    private func handleEvent(_ request: JsonRpcRequest) throws -> Any {
        let identifier = try request.requireString("identifier")
        let event = try provider.getEvent(identifier: identifier)
        return event.toDict()
    }
}
