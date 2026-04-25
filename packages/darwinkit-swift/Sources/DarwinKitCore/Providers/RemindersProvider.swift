import CoreLocation
import EventKit
import Foundation

// MARK: - Data Types

public struct ReminderListInfo {
    public let identifier: String
    public let title: String
    public let color: String  // hex color string
    public let source: String  // account name e.g. "iCloud"

    public init(identifier: String, title: String, color: String, source: String) {
        self.identifier = identifier
        self.title = title
        self.color = color
        self.source = source
    }

    public func toDict() -> [String: Any] {
        ["identifier": identifier, "title": title, "color": color, "source": source]
    }
}

public struct AlarmLocationInfo {
    public let title: String
    public let latitude: Double?
    public let longitude: Double?
    public let radius: Double?

    public func toDict() -> [String: Any] {
        var dict: [String: Any] = ["title": title]
        if let latitude = latitude { dict["latitude"] = latitude }
        if let longitude = longitude { dict["longitude"] = longitude }
        if let radius = radius { dict["radius"] = radius }
        return dict
    }
}

public struct AlarmInfo {
    public let type: String  // "time" | "location"
    public let relativeOffset: Double?  // seconds before event (negative = before)
    public let absoluteDate: String?  // ISO 8601
    public let location: AlarmLocationInfo?
    public let proximity: String?  // "enter" | "leave" | "none"

    public func toDict() -> [String: Any] {
        var dict: [String: Any] = ["type": type]
        if let relativeOffset = relativeOffset { dict["relative_offset"] = relativeOffset }
        if let absoluteDate = absoluteDate { dict["absolute_date"] = absoluteDate }
        if let location = location { dict["location"] = location.toDict() }
        if let proximity = proximity { dict["proximity"] = proximity }
        return dict
    }
}

public struct ReminderInfo {
    public let identifier: String
    public let title: String
    public let isCompleted: Bool
    public let completionDate: String?  // ISO 8601 or nil
    public let dueDate: String?         // ISO 8601 or nil
    public let startDate: String?       // ISO 8601 or nil
    public let priority: Int            // 0 = none, 1 = high, 5 = medium, 9 = low
    public let notes: String?
    public let url: String?             // URL string or nil
    public let hasAlarms: Bool
    public let alarms: [AlarmInfo]
    public let isFlagged: Bool
    public let listIdentifier: String
    public let listTitle: String
    public let externalIdentifier: String?

    public init(
        identifier: String, title: String, isCompleted: Bool,
        completionDate: String?, dueDate: String?, startDate: String?,
        priority: Int, notes: String?, url: String?,
        hasAlarms: Bool, alarms: [AlarmInfo] = [], isFlagged: Bool = false,
        listIdentifier: String, listTitle: String,
        externalIdentifier: String?
    ) {
        self.identifier = identifier
        self.title = title
        self.isCompleted = isCompleted
        self.completionDate = completionDate
        self.dueDate = dueDate
        self.startDate = startDate
        self.priority = priority
        self.notes = notes
        self.url = url
        self.hasAlarms = hasAlarms
        self.alarms = alarms
        self.isFlagged = isFlagged
        self.listIdentifier = listIdentifier
        self.listTitle = listTitle
        self.externalIdentifier = externalIdentifier
    }

    public func toDict() -> [String: Any] {
        var dict: [String: Any] = [
            "identifier": identifier,
            "title": title,
            "is_completed": isCompleted,
            "priority": priority,
            "has_alarms": hasAlarms,
            "alarms": alarms.map { $0.toDict() },
            "is_flagged": isFlagged,
            "list_identifier": listIdentifier,
            "list_title": listTitle,
        ]
        if let completionDate = completionDate { dict["completion_date"] = completionDate }
        if let dueDate = dueDate { dict["due_date"] = dueDate }
        if let startDate = startDate { dict["start_date"] = startDate }
        if let notes = notes { dict["notes"] = notes }
        if let url = url { dict["url"] = url }
        if let externalIdentifier = externalIdentifier { dict["external_identifier"] = externalIdentifier }
        return dict
    }
}

public struct RemindersAuthorizationResult {
    public let status: String  // "fullAccess" | "denied" | "restricted" | "notDetermined"
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

public protocol RemindersProvider {
    /// Check/request reminders authorization.
    func checkAuthorization() throws -> RemindersAuthorizationResult

    /// List all reminder lists (calendars of type .reminder).
    func listReminderLists() throws -> [ReminderListInfo]

    /// Fetch reminders with optional filter. Filter can be "completed", "incomplete", or nil for all.
    /// Optionally filter by list identifiers.
    func fetchReminders(filter: String?, listIdentifiers: [String]?) throws -> [ReminderInfo]

    /// Save (create or update) a reminder.
    func saveReminder(
        id: String?, calendarIdentifier: String, title: String,
        dueDate: String?, startDate: String?, priority: Int?,
        notes: String?, completed: Bool?, url: String?,
        flagged: Bool?, alarms: [[String: Any]]?,
        commit: Bool
    ) throws -> CalendarSaveResult

    /// Remove a reminder.
    func removeReminder(identifier: String, commit: Bool) throws -> Bool

    /// Complete a reminder.
    func completeReminder(identifier: String) throws -> ReminderInfo

    /// Fetch incomplete reminders with optional date range.
    func fetchIncompleteReminders(
        startDate: String?, endDate: String?, listIdentifiers: [String]?
    ) throws -> [ReminderInfo]

    /// Fetch completed reminders with optional date range.
    func fetchCompletedReminders(
        startDate: String?, endDate: String?, listIdentifiers: [String]?
    ) throws -> [ReminderInfo]

    /// Request full access to reminders (can upgrade from limited access).
    func requestFullAccess() throws -> RemindersAuthorizationResult
}

// MARK: - Apple Implementation

public final class AppleRemindersProvider: RemindersProvider {
    private let store = EKEventStore()
    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    public init() {}

    public func checkAuthorization() throws -> RemindersAuthorizationResult {
        let status = EKEventStore.authorizationStatus(for: .reminder)

        switch status {
        case .fullAccess:
            return RemindersAuthorizationResult(status: "fullAccess", authorized: true)
        case .denied:
            return RemindersAuthorizationResult(status: "denied", authorized: false)
        case .restricted:
            return RemindersAuthorizationResult(status: "restricted", authorized: false)
        case .notDetermined:
            let semaphore = DispatchSemaphore(value: 0)
            var granted = false
            if #available(macOS 14, *) {
                store.requestFullAccessToReminders { success, _ in
                    granted = success
                    semaphore.signal()
                }
            } else {
                store.requestAccess(to: .reminder) { success, _ in
                    granted = success
                    semaphore.signal()
                }
            }
            semaphore.wait()
            let newStatus = granted ? "fullAccess" : "denied"
            return RemindersAuthorizationResult(status: newStatus, authorized: granted)
        @unknown default:
            return RemindersAuthorizationResult(status: "notDetermined", authorized: false)
        }
    }

    public func listReminderLists() throws -> [ReminderListInfo] {
        try ensureAuthorized()
        return store.calendars(for: .reminder).map { cal in
            let color = cal.cgColor.flatMap { cgColor -> String? in
                guard let components = cgColor.components, cgColor.numberOfComponents >= 3 else { return nil }
                let r = Int(components[0] * 255)
                let g = Int(components[1] * 255)
                let b = Int(components[2] * 255)
                return String(format: "#%02X%02X%02X", r, g, b)
            } ?? "#000000"

            return ReminderListInfo(
                identifier: cal.calendarIdentifier,
                title: cal.title,
                color: color,
                source: cal.source.title
            )
        }
    }

    public func fetchReminders(filter: String?, listIdentifiers: [String]?) throws -> [ReminderInfo] {
        try ensureAuthorized()

        var calendars: [EKCalendar]? = nil
        if let ids = listIdentifiers {
            calendars = ids.compactMap { store.calendar(withIdentifier: $0) }
            if calendars?.isEmpty == true {
                calendars = nil
            }
        }

        let predicate: NSPredicate
        switch filter {
        case "completed":
            predicate = store.predicateForCompletedReminders(
                withCompletionDateStarting: nil, ending: nil, calendars: calendars
            )
        case "incomplete":
            predicate = store.predicateForIncompleteReminders(
                withDueDateStarting: nil, ending: nil, calendars: calendars
            )
        default:
            predicate = store.predicateForReminders(in: calendars)
        }

        // fetchReminders is callback-based -- bridge to sync
        let semaphore = DispatchSemaphore(value: 0)
        var reminders: [EKReminder]? = nil

        store.fetchReminders(matching: predicate) { result in
            reminders = result
            semaphore.signal()
        }

        semaphore.wait()

        return (reminders ?? []).map { mapReminder($0) }
    }

    // MARK: - Private

    private func ensureAuthorized() throws {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        guard status == .fullAccess else {
            throw JsonRpcError.permissionDenied(
                "Reminders access not authorized. Call reminders.authorized first."
            )
        }
    }

    private func mapReminder(_ reminder: EKReminder) -> ReminderInfo {
        var dueDateStr: String? = nil
        if let components = reminder.dueDateComponents,
           let date = Calendar.current.date(from: components) {
            dueDateStr = isoFormatter.string(from: date)
        }

        var startDateStr: String? = nil
        if let components = reminder.startDateComponents,
           let date = Calendar.current.date(from: components) {
            startDateStr = isoFormatter.string(from: date)
        }

        var completionDateStr: String? = nil
        if let date = reminder.completionDate {
            completionDateStr = isoFormatter.string(from: date)
        }

        let alarmInfos: [AlarmInfo] = (reminder.alarms ?? []).map { alarm in
            if let structuredLocation = alarm.structuredLocation {
                let locInfo = AlarmLocationInfo(
                    title: structuredLocation.title ?? "",
                    latitude: structuredLocation.geoLocation?.coordinate.latitude,
                    longitude: structuredLocation.geoLocation?.coordinate.longitude,
                    radius: structuredLocation.radius > 0 ? structuredLocation.radius : nil
                )
                let proximityStr: String
                switch alarm.proximity {
                case .enter: proximityStr = "enter"
                case .leave: proximityStr = "leave"
                default: proximityStr = "none"
                }
                return AlarmInfo(
                    type: "location",
                    relativeOffset: nil,
                    absoluteDate: nil,
                    location: locInfo,
                    proximity: proximityStr
                )
            } else {
                var absDateStr: String? = nil
                if let absDate = alarm.absoluteDate {
                    absDateStr = isoFormatter.string(from: absDate)
                }
                return AlarmInfo(
                    type: "time",
                    relativeOffset: alarm.relativeOffset,
                    absoluteDate: absDateStr,
                    location: nil,
                    proximity: nil
                )
            }
        }

        return ReminderInfo(
            identifier: reminder.calendarItemIdentifier,
            title: reminder.title ?? "",
            isCompleted: reminder.isCompleted,
            completionDate: completionDateStr,
            dueDate: dueDateStr,
            startDate: startDateStr,
            priority: reminder.priority,
            notes: reminder.notes,
            url: reminder.url?.absoluteString,
            hasAlarms: reminder.hasAlarms,
            alarms: alarmInfos,
            isFlagged: false,  // EKReminder doesn't expose flagged state on macOS
            listIdentifier: reminder.calendar?.calendarIdentifier ?? "",
            listTitle: reminder.calendar?.title ?? "",
            externalIdentifier: reminder.calendarItemExternalIdentifier
        )
    }

    private func parseDate(_ string: String) -> Date? {
        isoFormatter.date(from: string)
    }

    private func resolveCalendars(_ identifiers: [String]?) -> [EKCalendar]? {
        guard let ids = identifiers else { return nil }
        let calendars = ids.compactMap { store.calendar(withIdentifier: $0) }
        return calendars.isEmpty ? nil : calendars
    }

    private func fetchRemindersSync(matching predicate: NSPredicate) -> [EKReminder] {
        let semaphore = DispatchSemaphore(value: 0)
        var reminders: [EKReminder]? = nil

        store.fetchReminders(matching: predicate) { result in
            reminders = result
            semaphore.signal()
        }

        semaphore.wait()
        return reminders ?? []
    }

    // MARK: - Write Methods

    public func saveReminder(
        id: String?, calendarIdentifier: String, title: String,
        dueDate: String?, startDate: String?, priority: Int?,
        notes: String?, completed: Bool?, url: String?,
        flagged: Bool?, alarms: [[String: Any]]?,
        commit: Bool
    ) throws -> CalendarSaveResult {
        try ensureAuthorized()

        let reminder: EKReminder
        if let id = id,
           let item = store.calendarItem(withIdentifier: id),
           let existing = item as? EKReminder {
            reminder = existing
            // Allow moving reminder to a different list
            if let newCalendar = store.calendar(withIdentifier: calendarIdentifier),
               newCalendar.calendarIdentifier != reminder.calendar.calendarIdentifier {
                reminder.calendar = newCalendar
            }
        } else {
            reminder = EKReminder(eventStore: store)
            guard let calendar = store.calendar(withIdentifier: calendarIdentifier) else {
                return CalendarSaveResult(success: false, identifier: nil, error: "Calendar not found: \(calendarIdentifier)")
            }

            reminder.calendar = calendar
        }

        reminder.title = title

        if let notes = notes {
            reminder.notes = notes
        }

        if let priority = priority {
            reminder.priority = priority
        }

        if let completed = completed {
            reminder.isCompleted = completed
            reminder.completionDate = completed ? Date() : nil
        }

        if let dueDateStr = dueDate, let date = parseDate(dueDateStr) {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: date
            )
        }

        if let startDateStr = startDate, let date = parseDate(startDateStr) {
            reminder.startDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: date
            )
        }

        if let url = url {
            guard let urlObj = URL(string: url) else {
                throw JsonRpcError.invalidParams("Invalid url: \(url)")
            }
            reminder.url = urlObj
        }

        // Note: EKReminder doesn't expose flagged state on macOS.
        // The flagged param is accepted but ignored until Apple adds API support.
        _ = flagged

        if let alarms = alarms {
            // Clear existing alarms before setting new ones
            reminder.alarms?.forEach { reminder.removeAlarm($0) }

            for alarmDict in alarms {
                if let offset = alarmDict["relative_offset"] as? Double {
                    let alarm = EKAlarm(relativeOffset: offset)
                    reminder.addAlarm(alarm)
                } else if let locationDict = alarmDict["location"] as? [String: Any],
                          let title = locationDict["title"] as? String {
                    let structuredLocation = EKStructuredLocation(title: title)
                    if let lat = locationDict["latitude"] as? Double,
                       let lon = locationDict["longitude"] as? Double {
                        structuredLocation.geoLocation = CLLocation(latitude: lat, longitude: lon)
                    }
                    if let radius = locationDict["radius"] as? Double {
                        structuredLocation.radius = radius
                    }
                    let alarm = EKAlarm()
                    alarm.structuredLocation = structuredLocation
                    let proximityStr = alarmDict["proximity"] as? String ?? "enter"
                    alarm.proximity = proximityStr == "leave" ? .leave : .enter
                    reminder.addAlarm(alarm)
                }
            }
        }

        do {
            try store.save(reminder, commit: commit)
            return CalendarSaveResult(success: true, identifier: reminder.calendarItemIdentifier, error: nil)
        } catch {
            return CalendarSaveResult(success: false, identifier: nil, error: error.localizedDescription)
        }
    }

    public func removeReminder(identifier: String, commit: Bool) throws -> Bool {
        try ensureAuthorized()

        guard let item = store.calendarItem(withIdentifier: identifier),
              let reminder = item as? EKReminder else {
            throw JsonRpcError.invalidParams("Reminder not found: \(identifier)")
        }

        try store.remove(reminder, commit: commit)
        return true
    }

    public func completeReminder(identifier: String) throws -> ReminderInfo {
        try ensureAuthorized()

        guard let item = store.calendarItem(withIdentifier: identifier),
              let reminder = item as? EKReminder else {
            throw JsonRpcError.invalidParams("Reminder not found: \(identifier)")
        }

        reminder.isCompleted = true
        reminder.completionDate = Date()
        try store.save(reminder, commit: true)
        return mapReminder(reminder)
    }

    public func fetchIncompleteReminders(
        startDate: String?, endDate: String?, listIdentifiers: [String]?
    ) throws -> [ReminderInfo] {
        try ensureAuthorized()

        let start = try validateOptionalDate(startDate, param: "start_date")
        let end = try validateOptionalDate(endDate, param: "end_date")
        let calendars = resolveCalendars(listIdentifiers)

        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: start, ending: end, calendars: calendars
        )

        return fetchRemindersSync(matching: predicate).map { mapReminder($0) }
    }

    public func fetchCompletedReminders(
        startDate: String?, endDate: String?, listIdentifiers: [String]?
    ) throws -> [ReminderInfo] {
        try ensureAuthorized()

        let start = try validateOptionalDate(startDate, param: "start_date")
        let end = try validateOptionalDate(endDate, param: "end_date")
        let calendars = resolveCalendars(listIdentifiers)

        let predicate = store.predicateForCompletedReminders(
            withCompletionDateStarting: start, ending: end, calendars: calendars
        )

        return fetchRemindersSync(matching: predicate).map { mapReminder($0) }
    }

    private func validateOptionalDate(_ dateStr: String?, param: String) throws -> Date? {
        guard let dateStr = dateStr else { return nil }
        guard let date = parseDate(dateStr) else {
            throw JsonRpcError.invalidParams("Invalid ISO 8601 date for \(param): \(dateStr)")
        }
        return date
    }

    public func requestFullAccess() throws -> RemindersAuthorizationResult {
        let previousStatus = EKEventStore.authorizationStatus(for: .reminder)
        let semaphore = DispatchSemaphore(value: 0)

        if #available(macOS 14, *) {
            store.requestFullAccessToReminders { _, _ in
                semaphore.signal()
            }
        } else {
            store.requestAccess(to: .reminder) { _, _ in
                semaphore.signal()
            }
        }

        semaphore.wait()

        // When upgrading access, macOS shows a system dialog but fires
        // the callback immediately. Poll briefly to catch the user's response.
        if previousStatus != .notDetermined && previousStatus != .fullAccess {
            for _ in 0..<30 {  // up to 15 seconds
                let current = EKEventStore.authorizationStatus(for: .reminder)
                if current != previousStatus {
                    return remindersAuthResult(from: current)
                }
                Thread.sleep(forTimeInterval: 0.5)
            }
        }

        return remindersAuthResult(from: EKEventStore.authorizationStatus(for: .reminder))
    }

    private func remindersAuthResult(from status: EKAuthorizationStatus) -> RemindersAuthorizationResult {
        let statusStr: String
        switch status {
        case .fullAccess: statusStr = "fullAccess"
        case .denied: statusStr = "denied"
        case .restricted: statusStr = "restricted"
        default: statusStr = "notDetermined"
        }
        return RemindersAuthorizationResult(status: statusStr, authorized: status == .fullAccess)
    }
}
