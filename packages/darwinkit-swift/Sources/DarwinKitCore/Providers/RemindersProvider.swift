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
    public let listIdentifier: String
    public let listTitle: String
    public let externalIdentifier: String?

    public init(
        identifier: String, title: String, isCompleted: Bool,
        completionDate: String?, dueDate: String?, startDate: String?,
        priority: Int, notes: String?, url: String?,
        hasAlarms: Bool, listIdentifier: String, listTitle: String,
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
            listIdentifier: reminder.calendar.calendarIdentifier,
            listTitle: reminder.calendar.title,
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
        commit: Bool
    ) throws -> CalendarSaveResult {
        try ensureAuthorized()

        let reminder: EKReminder
        if let id = id,
           let item = store.calendarItem(withIdentifier: id),
           let existing = item as? EKReminder {
            reminder = existing
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
            if let existingNotes = reminder.notes, !existingNotes.isEmpty {
                reminder.notes = existingNotes + "\n\nURL: \(url)"
            } else {
                reminder.notes = "URL: \(url)"
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

        let start = startDate.flatMap { parseDate($0) }
        let end = endDate.flatMap { parseDate($0) }
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

        let start = startDate.flatMap { parseDate($0) }
        let end = endDate.flatMap { parseDate($0) }
        let calendars = resolveCalendars(listIdentifiers)

        let predicate = store.predicateForCompletedReminders(
            withCompletionDateStarting: start, ending: end, calendars: calendars
        )

        return fetchRemindersSync(matching: predicate).map { mapReminder($0) }
    }
}
