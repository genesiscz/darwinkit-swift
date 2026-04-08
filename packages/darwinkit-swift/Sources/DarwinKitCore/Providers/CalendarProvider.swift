import EventKit
import Foundation

// MARK: - Data Types

public struct CalendarInfo {
    public let identifier: String
    public let title: String
    public let type: String  // "local" | "calDAV" | "exchange" | "subscription" | "birthday"
    public let color: String  // hex color string e.g. "#FF0000"
    public let isImmutable: Bool
    public let allowsContentModifications: Bool
    public let source: String  // account name e.g. "iCloud", "On My Mac"

    public init(
        identifier: String, title: String, type: String,
        color: String, isImmutable: Bool, allowsContentModifications: Bool,
        source: String
    ) {
        self.identifier = identifier
        self.title = title
        self.type = type
        self.color = color
        self.isImmutable = isImmutable
        self.allowsContentModifications = allowsContentModifications
        self.source = source
    }

    public func toDict() -> [String: Any] {
        [
            "identifier": identifier,
            "title": title,
            "type": type,
            "color": color,
            "is_immutable": isImmutable,
            "allows_content_modifications": allowsContentModifications,
            "source": source,
        ]
    }
}

public struct CalendarEventInfo {
    public let identifier: String
    public let title: String
    public let startDate: String  // ISO 8601
    public let endDate: String    // ISO 8601
    public let isAllDay: Bool
    public let location: String?
    public let notes: String?
    public let calendarIdentifier: String
    public let calendarTitle: String
    public let url: String?
    public let availability: String  // "free" | "busy" | "tentative" | "unavailable"
    public let hasAlarms: Bool
    public let alarms: [Int]  // minutes before event (positive values)
    public let externalIdentifier: String?

    public init(
        identifier: String, title: String, startDate: String, endDate: String,
        isAllDay: Bool, location: String?, notes: String?,
        calendarIdentifier: String, calendarTitle: String, url: String?,
        availability: String, hasAlarms: Bool, alarms: [Int],
        externalIdentifier: String?
    ) {
        self.identifier = identifier
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.location = location
        self.notes = notes
        self.calendarIdentifier = calendarIdentifier
        self.calendarTitle = calendarTitle
        self.url = url
        self.availability = availability
        self.hasAlarms = hasAlarms
        self.alarms = alarms
        self.externalIdentifier = externalIdentifier
    }

    public func toDict() -> [String: Any] {
        var dict: [String: Any] = [
            "identifier": identifier,
            "title": title,
            "start_date": startDate,
            "end_date": endDate,
            "is_all_day": isAllDay,
            "calendar_identifier": calendarIdentifier,
            "calendar_title": calendarTitle,
            "availability": availability,
            "has_alarms": hasAlarms,
            "alarms": alarms,
        ]
        if let location = location { dict["location"] = location }
        if let notes = notes { dict["notes"] = notes }
        if let url = url { dict["url"] = url }
        if let externalIdentifier = externalIdentifier { dict["external_identifier"] = externalIdentifier }
        return dict
    }
}

public struct SourceInfo {
    public let identifier: String
    public let title: String
    public let sourceType: String  // "local" | "exchange" | "calDAV" | "mobileMe" | "subscribed" | "birthdays"

    public func toDict() -> [String: Any] {
        ["identifier": identifier, "title": title, "source_type": sourceType]
    }
}

public struct CalendarSaveResult {
    public let success: Bool
    public let identifier: String?
    public let error: String?

    public func toDict() -> [String: Any] {
        var dict: [String: Any] = ["success": success]
        if let identifier = identifier { dict["identifier"] = identifier }
        if let error = error { dict["error"] = error }
        return dict
    }
}

public struct OkResult {
    public let ok: Bool

    public func toDict() -> [String: Any] {
        ["ok": ok]
    }
}

public struct CalendarAuthorizationResult {
    public let status: String  // "fullAccess" | "writeOnly" | "denied" | "restricted" | "notDetermined"
    public let authorized: Bool

    public init(status: String, authorized: Bool) {
        self.status = status
        self.authorized = authorized
    }

    public func toDict() -> [String: Any] {
        ["status": status, "authorized": authorized]
    }
}

// MARK: - Provider Protocol

public protocol CalendarProvider {
    /// Check/request calendar authorization. Returns current status.
    func checkAuthorization() throws -> CalendarAuthorizationResult

    /// List all calendars for events.
    func listCalendars() throws -> [CalendarInfo]

    /// Fetch events in a date range, optionally filtered by calendar identifiers.
    func fetchEvents(startDate: String, endDate: String, calendarIdentifiers: [String]?) throws -> [CalendarEventInfo]

    /// Get a single event by identifier.
    func getEvent(identifier: String) throws -> CalendarEventInfo

    /// Save (create or update) an event.
    func saveEvent(
        id: String?, calendarIdentifier: String, title: String,
        startDate: String, endDate: String, notes: String?,
        location: String?, url: String?, isAllDay: Bool?,
        availability: String?, alarms: [Int]?,
        span: String, commit: Bool
    ) throws -> CalendarSaveResult

    /// Remove an event.
    func removeEvent(identifier: String, span: String, commit: Bool) throws -> Bool

    /// Get a calendar item (event or reminder) by identifier.
    func getCalendarItem(identifier: String) throws -> [String: Any]

    /// Get calendar items by external identifier.
    func getCalendarItemsByExternalId(externalIdentifier: String) throws -> [[String: Any]]

    /// Get event store sources.
    func getSources() throws -> [SourceInfo]

    /// Get a single source by identifier.
    func getSource(identifier: String) throws -> SourceInfo

    /// Get delegate sources (macOS 12+).
    func getDelegateSources() throws -> [SourceInfo]

    /// Save (create or update) a calendar.
    func saveCalendar(
        id: String?, title: String, sourceIdentifier: String,
        entityType: String?, colorHex: String?, commit: Bool
    ) throws -> CalendarSaveResult

    /// Remove a calendar.
    func removeCalendar(identifier: String, commit: Bool) throws -> Bool

    /// Get default calendar for new events.
    func defaultCalendarForNewEvents() throws -> CalendarInfo?

    /// Get default calendar for new reminders.
    func defaultCalendarForNewReminders() throws -> CalendarInfo?

    /// Commit pending changes.
    func commit() throws

    /// Reset (discard unsaved changes).
    func reset()

    /// Refresh sources if necessary.
    func refreshSources()

    /// Request write-only access to events.
    func requestWriteOnlyAccess() throws -> CalendarAuthorizationResult

    /// Request full access to events (can upgrade from writeOnly).
    func requestFullAccess() throws -> CalendarAuthorizationResult
}

// MARK: - Apple Implementation

public final class AppleCalendarProvider: CalendarProvider {
    private let store = EKEventStore()
    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    public init() {}

    public func checkAuthorization() throws -> CalendarAuthorizationResult {
        let status = EKEventStore.authorizationStatus(for: .event)

        switch status {
        case .fullAccess:
            return CalendarAuthorizationResult(status: "fullAccess", authorized: true)
        case .writeOnly:
            return CalendarAuthorizationResult(status: "writeOnly", authorized: false)
        case .denied:
            return CalendarAuthorizationResult(status: "denied", authorized: false)
        case .restricted:
            return CalendarAuthorizationResult(status: "restricted", authorized: false)
        case .notDetermined:
            let semaphore = DispatchSemaphore(value: 0)
            var granted = false
            if #available(macOS 14, *) {
                store.requestFullAccessToEvents { success, _ in
                    granted = success
                    semaphore.signal()
                }
            } else {
                store.requestAccess(to: .event) { success, _ in
                    granted = success
                    semaphore.signal()
                }
            }
            semaphore.wait()
            let newStatus = granted ? "fullAccess" : "denied"
            return CalendarAuthorizationResult(status: newStatus, authorized: granted)
        @unknown default:
            return CalendarAuthorizationResult(status: "notDetermined", authorized: false)
        }
    }

    public func listCalendars() throws -> [CalendarInfo] {
        try ensureAuthorized()
        return store.calendars(for: .event).map { mapCalendar($0) }
    }

    public func fetchEvents(startDate: String, endDate: String, calendarIdentifiers: [String]?) throws -> [CalendarEventInfo] {
        try ensureAuthorized()

        guard let start = isoFormatter.date(from: startDate) else {
            throw JsonRpcError.invalidParams("Invalid start_date ISO 8601 format: \(startDate)")
        }
        guard let end = isoFormatter.date(from: endDate) else {
            throw JsonRpcError.invalidParams("Invalid end_date ISO 8601 format: \(endDate)")
        }

        var calendars: [EKCalendar]? = nil
        if let ids = calendarIdentifiers {
            calendars = ids.compactMap { store.calendar(withIdentifier: $0) }
            if calendars?.isEmpty == true {
                calendars = nil  // fall back to all calendars
            }
        }

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        let events = store.events(matching: predicate)
        return events.map { mapEvent($0) }
    }

    public func getEvent(identifier: String) throws -> CalendarEventInfo {
        try ensureAuthorized()

        guard let event = store.event(withIdentifier: identifier) else {
            throw JsonRpcError.invalidParams("Event not found: \(identifier)")
        }

        return mapEvent(event)
    }

    // MARK: - Private

    private func ensureAuthorized() throws {
        let status = EKEventStore.authorizationStatus(for: .event)
        guard status == .fullAccess || status == .writeOnly else {
            throw JsonRpcError.permissionDenied(
                "Calendar access not authorized. Call calendar.authorized first."
            )
        }
    }

    private func mapCalendar(_ cal: EKCalendar) -> CalendarInfo {
        let typeName: String
        switch cal.type {
        case .local: typeName = "local"
        case .calDAV: typeName = "calDAV"
        case .exchange: typeName = "exchange"
        case .subscription: typeName = "subscription"
        case .birthday: typeName = "birthday"
        @unknown default: typeName = "unknown"
        }

        let color = cal.cgColor.flatMap { cgColor -> String? in
            guard let components = cgColor.components, cgColor.numberOfComponents >= 3 else { return nil }
            let r = Int(components[0] * 255)
            let g = Int(components[1] * 255)
            let b = Int(components[2] * 255)
            return String(format: "#%02X%02X%02X", r, g, b)
        } ?? "#000000"

        return CalendarInfo(
            identifier: cal.calendarIdentifier,
            title: cal.title,
            type: typeName,
            color: color,
            isImmutable: cal.isImmutable,
            allowsContentModifications: cal.allowsContentModifications,
            source: cal.source.title
        )
    }

    private func mapEvent(_ event: EKEvent) -> CalendarEventInfo {
        let availabilityName: String
        switch event.availability {
        case .free: availabilityName = "free"
        case .busy: availabilityName = "busy"
        case .tentative: availabilityName = "tentative"
        case .unavailable: availabilityName = "unavailable"
        @unknown default: availabilityName = "busy"
        }

        let alarmMinutes: [Int] = (event.alarms ?? []).compactMap { alarm in
            let seconds = alarm.relativeOffset
            guard seconds < 0 else { return nil }
            return Int(-seconds / 60)
        }

        return CalendarEventInfo(
            identifier: event.eventIdentifier,
            title: event.title ?? "",
            startDate: isoFormatter.string(from: event.startDate),
            endDate: isoFormatter.string(from: event.endDate),
            isAllDay: event.isAllDay,
            location: event.location,
            notes: event.notes,
            calendarIdentifier: event.calendar.calendarIdentifier,
            calendarTitle: event.calendar.title,
            url: event.url?.absoluteString,
            availability: availabilityName,
            hasAlarms: event.hasAlarms,
            alarms: alarmMinutes,
            externalIdentifier: event.calendarItemExternalIdentifier
        )
    }

    private func mapSource(_ source: EKSource) -> SourceInfo {
        let typeName: String
        switch source.sourceType {
        case .local: typeName = "local"
        case .exchange: typeName = "exchange"
        case .calDAV: typeName = "calDAV"
        case .mobileMe: typeName = "mobileMe"
        case .subscribed: typeName = "subscribed"
        case .birthdays: typeName = "birthdays"
        @unknown default: typeName = "unknown"
        }
        return SourceInfo(identifier: source.sourceIdentifier, title: source.title, sourceType: typeName)
    }

    private func parseSpan(_ span: String) -> EKSpan {
        switch span {
        case "futureEvents": return .futureEvents
        default: return .thisEvent
        }
    }

    private func parseHexColor(_ hex: String) -> CGColor? {
        guard hex.hasPrefix("#") else { return nil }
        let hexString = String(hex.dropFirst())

        let scanner = Scanner(string: hexString)
        var hexValue: UInt64 = 0

        guard scanner.scanHexInt64(&hexValue) else { return nil }

        let r: CGFloat
        let g: CGFloat
        let b: CGFloat
        let a: CGFloat

        if hexString.count == 8 {
            r = CGFloat((hexValue & 0xFF000000) >> 24) / 255.0
            g = CGFloat((hexValue & 0x00FF0000) >> 16) / 255.0
            b = CGFloat((hexValue & 0x0000FF00) >> 8) / 255.0
            a = CGFloat(hexValue & 0x000000FF) / 255.0
        } else if hexString.count == 6 {
            r = CGFloat((hexValue & 0xFF0000) >> 16) / 255.0
            g = CGFloat((hexValue & 0x00FF00) >> 8) / 255.0
            b = CGFloat(hexValue & 0x0000FF) / 255.0
            a = 1.0
        } else {
            return nil
        }

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGColor(colorSpace: colorSpace, components: [r, g, b, a])
    }

    private func mapCalendarItem(_ item: EKCalendarItem) -> [String: Any] {
        var dict: [String: Any] = [
            "identifier": item.calendarItemIdentifier,
            "title": item.title ?? "",
            "calendar_identifier": item.calendar.calendarIdentifier,
            "calendar_title": item.calendar.title,
            "has_alarms": item.hasAlarms,
        ]

        if let externalId = item.calendarItemExternalIdentifier {
            dict["external_identifier"] = externalId
        }

        if let event = item as? EKEvent {
            dict["type"] = "event"
            dict["start_date"] = isoFormatter.string(from: event.startDate)
            dict["end_date"] = isoFormatter.string(from: event.endDate)
            dict["is_all_day"] = event.isAllDay
            if let location = event.location { dict["location"] = location }
            if let notes = event.notes { dict["notes"] = notes }
            if let url = event.url { dict["url"] = url.absoluteString }
        } else if let reminder = item as? EKReminder {
            dict["type"] = "reminder"
            dict["completed"] = reminder.isCompleted
            if let completionDate = reminder.completionDate {
                dict["completion_date"] = isoFormatter.string(from: completionDate)
            }
        }

        return dict
    }

    // MARK: - Write Methods

    public func saveEvent(
        id: String?, calendarIdentifier: String, title: String,
        startDate: String, endDate: String, notes: String?,
        location: String?, url: String?, isAllDay: Bool?,
        availability: String?, alarms: [Int]?,
        span: String, commit: Bool
    ) throws -> CalendarSaveResult {
        try ensureAuthorized()

        let event: EKEvent
        if let id = id, let existing = store.event(withIdentifier: id) {
            event = existing
        } else {
            event = EKEvent(eventStore: store)
            guard let calendar = store.calendar(withIdentifier: calendarIdentifier) else {
                return CalendarSaveResult(
                    success: false, identifier: nil,
                    error: "Calendar not found: \(calendarIdentifier)"
                )
            }
            event.calendar = calendar
        }

        event.title = title

        guard let start = isoFormatter.date(from: startDate) else {
            throw JsonRpcError.invalidParams("Invalid start_date ISO 8601 format: \(startDate)")
        }
        guard let end = isoFormatter.date(from: endDate) else {
            throw JsonRpcError.invalidParams("Invalid end_date ISO 8601 format: \(endDate)")
        }

        event.startDate = start
        event.endDate = end
        event.notes = notes
        event.location = location

        if let urlString = url, let parsed = URL(string: urlString) {
            event.url = parsed
        } else {
            event.url = nil
        }

        if let isAllDay = isAllDay {
            event.isAllDay = isAllDay
        }

        if let availability = availability {
            switch availability.lowercased() {
            case "free": event.availability = .free
            case "busy": event.availability = .busy
            case "tentative": event.availability = .tentative
            case "unavailable": event.availability = .unavailable
            default: break
            }
        }

        if let alarms = alarms {
            event.alarms?.forEach { event.removeAlarm($0) }
            for mins in alarms {
                event.addAlarm(EKAlarm(relativeOffset: TimeInterval(-mins * 60)))
            }
        }

        let ekSpan = parseSpan(span)

        do {
            try store.save(event, span: ekSpan, commit: commit)
            return CalendarSaveResult(success: true, identifier: event.eventIdentifier, error: nil)
        } catch {
            return CalendarSaveResult(success: false, identifier: nil, error: error.localizedDescription)
        }
    }

    public func removeEvent(identifier: String, span: String, commit: Bool) throws -> Bool {
        try ensureAuthorized()

        guard let event = store.event(withIdentifier: identifier) else {
            throw JsonRpcError.invalidParams("Event not found: \(identifier)")
        }

        let ekSpan = parseSpan(span)
        try store.remove(event, span: ekSpan, commit: commit)
        return true
    }

    public func getCalendarItem(identifier: String) throws -> [String: Any] {
        try ensureAuthorized()

        guard let item = store.calendarItem(withIdentifier: identifier) else {
            throw JsonRpcError.invalidParams("Calendar item not found: \(identifier)")
        }

        return mapCalendarItem(item)
    }

    public func getCalendarItemsByExternalId(externalIdentifier: String) throws -> [[String: Any]] {
        try ensureAuthorized()

        let items = store.calendarItems(withExternalIdentifier: externalIdentifier)
        return items.map { mapCalendarItem($0) }
    }

    public func getSources() throws -> [SourceInfo] {
        try ensureAuthorized()
        return store.sources.map { mapSource($0) }
    }

    public func getSource(identifier: String) throws -> SourceInfo {
        try ensureAuthorized()

        guard let source = store.source(withIdentifier: identifier) else {
            throw JsonRpcError.invalidParams("Source not found: \(identifier)")
        }

        return mapSource(source)
    }

    public func getDelegateSources() throws -> [SourceInfo] {
        try ensureAuthorized()

        if #available(macOS 12.0, *) {
            return store.delegateSources.map { mapSource($0) }
        } else {
            return []
        }
    }

    public func saveCalendar(
        id: String?, title: String, sourceIdentifier: String,
        entityType: String?, colorHex: String?, commit: Bool
    ) throws -> CalendarSaveResult {
        try ensureAuthorized()

        let ekEntityType: EKEntityType = (entityType?.lowercased() == "reminder") ? .reminder : .event

        let calendar: EKCalendar
        if let id = id, let existing = store.calendar(withIdentifier: id) {
            calendar = existing
        } else {
            calendar = EKCalendar(for: ekEntityType, eventStore: store)
            guard let source = store.source(withIdentifier: sourceIdentifier) else {
                return CalendarSaveResult(
                    success: false, identifier: nil,
                    error: "Source not found: \(sourceIdentifier)"
                )
            }
            calendar.source = source
        }

        calendar.title = title

        if let colorHex = colorHex, let cgColor = parseHexColor(colorHex) {
            calendar.cgColor = cgColor
        }

        do {
            try store.saveCalendar(calendar, commit: commit)
            return CalendarSaveResult(success: true, identifier: calendar.calendarIdentifier, error: nil)
        } catch {
            return CalendarSaveResult(success: false, identifier: nil, error: error.localizedDescription)
        }
    }

    public func removeCalendar(identifier: String, commit: Bool) throws -> Bool {
        try ensureAuthorized()

        guard let calendar = store.calendar(withIdentifier: identifier) else {
            throw JsonRpcError.invalidParams("Calendar not found: \(identifier)")
        }

        try store.removeCalendar(calendar, commit: commit)
        return true
    }

    public func defaultCalendarForNewEvents() throws -> CalendarInfo? {
        try ensureAuthorized()

        guard let calendar = store.defaultCalendarForNewEvents else {
            return nil
        }

        return mapCalendar(calendar)
    }

    public func defaultCalendarForNewReminders() throws -> CalendarInfo? {
        try ensureAuthorized()

        guard let calendar = store.defaultCalendarForNewReminders() else {
            return nil
        }

        return mapCalendar(calendar)
    }

    public func commit() throws {
        try store.commit()
    }

    public func reset() {
        store.reset()
    }

    public func refreshSources() {
        store.refreshSourcesIfNecessary()
    }

    public func requestWriteOnlyAccess() throws -> CalendarAuthorizationResult {
        let semaphore = DispatchSemaphore(value: 0)
        var granted = false

        if #available(macOS 14, *) {
            store.requestWriteOnlyAccessToEvents { success, _ in
                granted = success
                semaphore.signal()
            }
        } else {
            store.requestAccess(to: .event) { success, _ in
                granted = success
                semaphore.signal()
            }
        }

        semaphore.wait()
        let status = granted ? "writeOnly" : "denied"
        return CalendarAuthorizationResult(status: status, authorized: granted)
    }

    public func requestFullAccess() throws -> CalendarAuthorizationResult {
        let previousStatus = EKEventStore.authorizationStatus(for: .event)
        let semaphore = DispatchSemaphore(value: 0)

        if #available(macOS 14, *) {
            store.requestFullAccessToEvents { _, _ in
                semaphore.signal()
            }
        } else {
            store.requestAccess(to: .event) { _, _ in
                semaphore.signal()
            }
        }

        semaphore.wait()

        // When upgrading from writeOnly, macOS shows a system dialog but fires
        // the callback immediately. Poll briefly to catch the user's response.
        if previousStatus == .writeOnly {
            for _ in 0..<30 {  // up to 15 seconds
                let current = EKEventStore.authorizationStatus(for: .event)
                if current != previousStatus {
                    return calendarAuthResult(from: current)
                }
                Thread.sleep(forTimeInterval: 0.5)
            }
        }

        return calendarAuthResult(from: EKEventStore.authorizationStatus(for: .event))
    }

    private func calendarAuthResult(from status: EKAuthorizationStatus) -> CalendarAuthorizationResult {
        let statusStr: String
        switch status {
        case .fullAccess: statusStr = "fullAccess"
        case .writeOnly: statusStr = "writeOnly"
        case .denied: statusStr = "denied"
        case .restricted: statusStr = "restricted"
        default: statusStr = "notDetermined"
        }
        return CalendarAuthorizationResult(status: statusStr, authorized: status == .fullAccess)
    }
}
