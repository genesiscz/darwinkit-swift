import Foundation

/// Handles all calendar.* methods: authorized, calendars, events, event, save/remove, sources, etc.
public final class CalendarHandler: MethodHandler {
    private let provider: CalendarProvider

    public var methods: [String] {
        [
            "calendar.authorized", "calendar.calendars", "calendar.events", "calendar.event",
            "calendar.save_event", "calendar.remove_event",
            "calendar.calendar_item", "calendar.calendar_items_external",
            "calendar.sources", "calendar.source", "calendar.delegate_sources",
            "calendar.save_calendar", "calendar.remove_calendar",
            "calendar.default_calendar_events", "calendar.default_calendar_reminders",
            "calendar.commit", "calendar.reset", "calendar.refresh_sources",
            "calendar.request_write_only_access",
            "calendar.request_full_access",
        ]
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
        case "calendar.save_event":
            return try handleSaveEvent(request)
        case "calendar.remove_event":
            return try handleRemoveEvent(request)
        case "calendar.calendar_item":
            return try handleCalendarItem(request)
        case "calendar.calendar_items_external":
            return try handleCalendarItemsExternal(request)
        case "calendar.sources":
            return try handleSources(request)
        case "calendar.source":
            return try handleSource(request)
        case "calendar.delegate_sources":
            return try handleDelegateSources(request)
        case "calendar.save_calendar":
            return try handleSaveCalendar(request)
        case "calendar.remove_calendar":
            return try handleRemoveCalendar(request)
        case "calendar.default_calendar_events":
            return try handleDefaultCalendarEvents(request)
        case "calendar.default_calendar_reminders":
            return try handleDefaultCalendarReminders(request)
        case "calendar.commit":
            return try handleCommit(request)
        case "calendar.reset":
            return handleReset(request)
        case "calendar.refresh_sources":
            return handleRefreshSources(request)
        case "calendar.request_write_only_access":
            return try handleRequestWriteOnlyAccess(request)
        case "calendar.request_full_access":
            return try handleRequestFullAccess(request)
        default:
            throw JsonRpcError.methodNotFound(request.method)
        }
    }

    public func capability(for method: String) -> MethodCapability {
        MethodCapability(available: true, note: "Requires Calendar permission (macOS 14+)")
    }

    // MARK: - Read Methods

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

    // MARK: - Write Methods

    private func handleSaveEvent(_ request: JsonRpcRequest) throws -> Any {
        let calendarIdentifier = try request.requireString("calendar_identifier")
        let title = try request.requireString("title")
        let startDate = try request.requireString("start_date")
        let endDate = try request.requireString("end_date")
        let id = request.string("id")
        let notes = request.string("notes")
        let location = request.string("location")
        let url = request.string("url")
        let isAllDay = request.bool("is_all_day")
        let availability = request.string("availability")
        let span = request.string("span") ?? "thisEvent"
        let commit = request.bool("commit") ?? true

        let alarms = extractIntArray(request, key: "alarms")

        let result = try provider.saveEvent(
            id: id, calendarIdentifier: calendarIdentifier, title: title,
            startDate: startDate, endDate: endDate, notes: notes,
            location: location, url: url, isAllDay: isAllDay,
            availability: availability, alarms: alarms,
            span: span, commit: commit
        )
        return result.toDict()
    }

    private func handleRemoveEvent(_ request: JsonRpcRequest) throws -> Any {
        let identifier = try request.requireString("identifier")
        let span = request.string("span") ?? "thisEvent"
        let commit = request.bool("commit") ?? true
        let removed = try provider.removeEvent(identifier: identifier, span: span, commit: commit)
        return OkResult(ok: removed).toDict()
    }

    private func handleCalendarItem(_ request: JsonRpcRequest) throws -> Any {
        let identifier = try request.requireString("identifier")
        return try provider.getCalendarItem(identifier: identifier)
    }

    private func handleCalendarItemsExternal(_ request: JsonRpcRequest) throws -> Any {
        let externalIdentifier = try request.requireString("external_identifier")
        let items = try provider.getCalendarItemsByExternalId(externalIdentifier: externalIdentifier)
        return ["items": items] as [String: Any]
    }

    // MARK: - Source Methods

    private func handleSources(_ request: JsonRpcRequest) throws -> Any {
        let sources = try provider.getSources()
        return ["sources": sources.map { $0.toDict() }] as [String: Any]
    }

    private func handleSource(_ request: JsonRpcRequest) throws -> Any {
        let identifier = try request.requireString("identifier")
        let source = try provider.getSource(identifier: identifier)
        return source.toDict()
    }

    private func handleDelegateSources(_ request: JsonRpcRequest) throws -> Any {
        let sources = try provider.getDelegateSources()
        return ["sources": sources.map { $0.toDict() }] as [String: Any]
    }

    // MARK: - Calendar Management

    private func handleSaveCalendar(_ request: JsonRpcRequest) throws -> Any {
        let title = try request.requireString("title")
        let sourceIdentifier = try request.requireString("source_identifier")
        let id = request.string("id")
        let entityType = request.string("entity_type")
        let colorHex = request.string("color_hex")
        let commit = request.bool("commit") ?? true

        let result = try provider.saveCalendar(
            id: id, title: title, sourceIdentifier: sourceIdentifier,
            entityType: entityType, colorHex: colorHex, commit: commit
        )
        return result.toDict()
    }

    private func handleRemoveCalendar(_ request: JsonRpcRequest) throws -> Any {
        let identifier = try request.requireString("identifier")
        let commit = request.bool("commit") ?? true
        let removed = try provider.removeCalendar(identifier: identifier, commit: commit)
        return OkResult(ok: removed).toDict()
    }

    private func handleDefaultCalendarEvents(_ request: JsonRpcRequest) throws -> Any {
        guard let calendar = try provider.defaultCalendarForNewEvents() else {
            return NSNull()
        }
        return calendar.toDict()
    }

    private func handleDefaultCalendarReminders(_ request: JsonRpcRequest) throws -> Any {
        guard let calendar = try provider.defaultCalendarForNewReminders() else {
            return NSNull()
        }
        return calendar.toDict()
    }

    // MARK: - Store Operations

    private func handleCommit(_ request: JsonRpcRequest) throws -> Any {
        try provider.commit()
        return OkResult(ok: true).toDict()
    }

    private func handleReset(_ request: JsonRpcRequest) -> Any {
        provider.reset()
        return OkResult(ok: true).toDict()
    }

    private func handleRefreshSources(_ request: JsonRpcRequest) -> Any {
        provider.refreshSources()
        return OkResult(ok: true).toDict()
    }

    private func handleRequestWriteOnlyAccess(_ request: JsonRpcRequest) throws -> Any {
        let result = try provider.requestWriteOnlyAccess()
        return result.toDict()
    }

    private func handleRequestFullAccess(_ request: JsonRpcRequest) throws -> Any {
        let result = try provider.requestFullAccess()
        return result.toDict()
    }

    // MARK: - Helpers

    /// Extract an integer array from params. JsonRpcRequest has no intArray helper,
    /// so we read the raw arrayValue and convert each element.
    private func extractIntArray(_ request: JsonRpcRequest, key: String) -> [Int]? {
        guard let raw = request.params?[key]?.arrayValue else { return nil }
        return raw.compactMap { element -> Int? in
            if let intVal = element as? Int { return intVal }
            if let doubleVal = element as? Double { return Int(doubleVal) }
            return nil
        }
    }
}
