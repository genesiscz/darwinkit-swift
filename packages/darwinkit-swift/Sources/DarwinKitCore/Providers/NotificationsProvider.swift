import AppKit
import Foundation
import UserNotifications

// MARK: - Data Types

public struct NotificationSettingsInfo {
    public let authorizationStatus: String
    public let soundSetting: String
    public let badgeSetting: String
    public let alertSetting: String
    public let notificationCenterSetting: String
    public let lockScreenSetting: String
    public let criticalAlertSetting: String
    public let alertStyle: String

    public func toDict() -> [String: Any] {
        [
            "authorization_status": authorizationStatus,
            "sound_setting": soundSetting,
            "badge_setting": badgeSetting,
            "alert_setting": alertSetting,
            "notification_center_setting": notificationCenterSetting,
            "lock_screen_setting": lockScreenSetting,
            "critical_alert_setting": criticalAlertSetting,
            "alert_style": alertStyle,
        ]
    }
}

public struct PendingNotificationInfo {
    public let identifier: String
    public let title: String
    public let body: String
    public let subtitle: String?
    public let threadIdentifier: String?
    public let categoryIdentifier: String?
    public let triggerType: String?
    public let nextTriggerDate: String?

    public func toDict() -> [String: Any] {
        var dict: [String: Any] = [
            "identifier": identifier,
            "title": title,
            "body": body,
        ]
        if let subtitle = subtitle { dict["subtitle"] = subtitle }
        if let threadIdentifier = threadIdentifier { dict["thread_identifier"] = threadIdentifier }
        if let categoryIdentifier = categoryIdentifier { dict["category_identifier"] = categoryIdentifier }
        if let triggerType = triggerType { dict["trigger_type"] = triggerType }
        if let nextTriggerDate = nextTriggerDate { dict["next_trigger_date"] = nextTriggerDate }
        return dict
    }
}

public struct DeliveredNotificationInfo {
    public let identifier: String
    public let title: String
    public let body: String
    public let subtitle: String?
    public let threadIdentifier: String?
    public let categoryIdentifier: String?
    public let date: String

    public func toDict() -> [String: Any] {
        var dict: [String: Any] = [
            "identifier": identifier,
            "title": title,
            "body": body,
            "date": date,
        ]
        if let subtitle = subtitle { dict["subtitle"] = subtitle }
        if let threadIdentifier = threadIdentifier { dict["thread_identifier"] = threadIdentifier }
        if let categoryIdentifier = categoryIdentifier { dict["category_identifier"] = categoryIdentifier }
        return dict
    }
}

public struct NotificationInteractionEvent {
    public let notificationIdentifier: String
    public let actionIdentifier: String
    public let userText: String?
    public let userInfo: [String: Any]
    public let categoryIdentifier: String

    public func toDict() -> [String: Any] {
        var dict: [String: Any] = [
            "notification_identifier": notificationIdentifier,
            "action_identifier": actionIdentifier,
            "user_info": userInfo,
            "category_identifier": categoryIdentifier,
        ]
        if let userText = userText { dict["user_text"] = userText }
        return dict
    }
}

// MARK: - Provider Protocol

public protocol NotificationsProvider {
    func requestAuthorization(options: UNAuthorizationOptions) throws -> Bool
    func getSettings() throws -> NotificationSettingsInfo
    func send(
        title: String, body: String, subtitle: String?,
        identifier: String, sound: UNNotificationSound?,
        badge: NSNumber?, threadIdentifier: String?,
        categoryIdentifier: String?, userInfo: [String: Any]?,
        attachmentPaths: [String]?, trigger: UNNotificationTrigger?
    ) throws
    func listPending() throws -> [PendingNotificationInfo]
    func removePending(identifiers: [String]) throws
    func removeAllPending() throws
    func listDelivered() throws -> [DeliveredNotificationInfo]
    func removeDelivered(identifiers: [String]) throws
    func removeAllDelivered() throws
    func registerCategory(
        identifier: String, actions: [UNNotificationAction],
        hiddenPreviewPlaceholder: String?, customDismissAction: Bool
    ) throws
    func setInteractionHandler(_ handler: @escaping (NotificationInteractionEvent) -> Void)
}

// MARK: - Apple Implementation

public final class AppleNotificationsProvider: NSObject, NotificationsProvider, UNUserNotificationCenterDelegate {
    private var _center: UNUserNotificationCenter?
    private var interactionHandler: ((NotificationInteractionEvent) -> Void)?
    private var delegateSet = false
    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Lazily access UNUserNotificationCenter — crashes if unavailable (e.g. unbundled CLI without Info.plist).
    private func center() throws -> UNUserNotificationCenter {
        if let c = _center { return c }
        // UNUserNotificationCenter.current() requires a valid bundle proxy.
        // For CLI binaries without Info.plist, this throws NSInternalInconsistencyException
        // which propagates to the caller as a crash — embed Info.plist via -sectcreate.
        let c = UNUserNotificationCenter.current()
        _center = c
        if !delegateSet {
            c.delegate = self
            delegateSet = true
        }
        return c
    }

    public override init() {
        super.init()
    }

    public func setInteractionHandler(_ handler: @escaping (NotificationInteractionEvent) -> Void) {
        self.interactionHandler = handler
    }

    // MARK: - Authorization

    public func requestAuthorization(options: UNAuthorizationOptions) throws -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        var granted = false
        var authError: Error?

        let c = try center()

        // Dispatch to main thread — macOS requires main thread for the permission dialog.
        DispatchQueue.main.async {
            // Bring process to front so the permission dialog is visible
            NSApp.activate(ignoringOtherApps: true)

            c.requestAuthorization(options: options) { g, e in
                granted = g
                authError = e
                semaphore.signal()
            }
        }

        semaphore.wait()
        if let err = authError {
            throw JsonRpcError.permissionDenied(err.localizedDescription)
        }
        return granted
    }

    // MARK: - Settings

    public func getSettings() throws -> NotificationSettingsInfo {
        let semaphore = DispatchSemaphore(value: 0)
        var result: UNNotificationSettings?

        try center().getNotificationSettings { settings in
            result = settings
            semaphore.signal()
        }

        semaphore.wait()

        guard let settings = result else {
            throw JsonRpcError.internalError("Failed to get notification settings")
        }

        return NotificationSettingsInfo(
            authorizationStatus: mapAuthorizationStatus(settings.authorizationStatus),
            soundSetting: mapAlertSetting(settings.soundSetting),
            badgeSetting: mapAlertSetting(settings.badgeSetting),
            alertSetting: mapAlertSetting(settings.alertSetting),
            notificationCenterSetting: mapAlertSetting(settings.notificationCenterSetting),
            lockScreenSetting: mapAlertSetting(settings.lockScreenSetting),
            criticalAlertSetting: mapAlertSetting(settings.criticalAlertSetting),
            alertStyle: mapAlertStyle(settings.alertStyle)
        )
    }

    // MARK: - Send

    public func send(
        title: String, body: String, subtitle: String?,
        identifier: String, sound: UNNotificationSound?,
        badge: NSNumber?, threadIdentifier: String?,
        categoryIdentifier: String?, userInfo: [String: Any]?,
        attachmentPaths: [String]?, trigger: UNNotificationTrigger?
    ) throws {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if let subtitle = subtitle { content.subtitle = subtitle }
        if let sound = sound { content.sound = sound }
        if let badge = badge { content.badge = badge }
        if let threadIdentifier = threadIdentifier { content.threadIdentifier = threadIdentifier }
        if let categoryIdentifier = categoryIdentifier { content.categoryIdentifier = categoryIdentifier }
        if let userInfo = userInfo { content.userInfo = userInfo }

        if let paths = attachmentPaths {
            var attachments: [UNNotificationAttachment] = []
            for path in paths {
                let url = URL(fileURLWithPath: path)
                guard FileManager.default.fileExists(atPath: path) else {
                    throw JsonRpcError.invalidParams("Attachment file not found: \(path)")
                }
                let attachment = try UNNotificationAttachment(identifier: url.lastPathComponent, url: url, options: nil)
                attachments.append(attachment)
            }
            content.attachments = attachments
        }

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        let semaphore = DispatchSemaphore(value: 0)
        var sendError: Error?

        try center().add(request) { error in
            sendError = error
            semaphore.signal()
        }

        semaphore.wait()

        if let err = sendError {
            throw JsonRpcError.internalError("Failed to send notification: \(err.localizedDescription)")
        }
    }

    // MARK: - Pending

    public func listPending() throws -> [PendingNotificationInfo] {
        let semaphore = DispatchSemaphore(value: 0)
        var requests: [UNNotificationRequest] = []

        try center().getPendingNotificationRequests { reqs in
            requests = reqs
            semaphore.signal()
        }

        semaphore.wait()

        return requests.map { req in
            var triggerType: String? = nil
            var nextDate: String? = nil

            if let timeTrigger = req.trigger as? UNTimeIntervalNotificationTrigger {
                triggerType = "timeInterval"
                if let next = timeTrigger.nextTriggerDate() {
                    nextDate = isoFormatter.string(from: next)
                }
            } else if let calTrigger = req.trigger as? UNCalendarNotificationTrigger {
                triggerType = "calendar"
                if let next = calTrigger.nextTriggerDate() {
                    nextDate = isoFormatter.string(from: next)
                }
            }

            return PendingNotificationInfo(
                identifier: req.identifier,
                title: req.content.title,
                body: req.content.body,
                subtitle: req.content.subtitle.isEmpty ? nil : req.content.subtitle,
                threadIdentifier: req.content.threadIdentifier.isEmpty ? nil : req.content.threadIdentifier,
                categoryIdentifier: req.content.categoryIdentifier.isEmpty ? nil : req.content.categoryIdentifier,
                triggerType: triggerType,
                nextTriggerDate: nextDate
            )
        }
    }

    public func removePending(identifiers: [String]) throws {
        try center().removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    public func removeAllPending() throws {
        try center().removeAllPendingNotificationRequests()
    }

    // MARK: - Delivered

    public func listDelivered() throws -> [DeliveredNotificationInfo] {
        let semaphore = DispatchSemaphore(value: 0)
        var notifications: [UNNotification] = []

        try center().getDeliveredNotifications { notifs in
            notifications = notifs
            semaphore.signal()
        }

        semaphore.wait()

        return notifications.map { notif in
            DeliveredNotificationInfo(
                identifier: notif.request.identifier,
                title: notif.request.content.title,
                body: notif.request.content.body,
                subtitle: notif.request.content.subtitle.isEmpty ? nil : notif.request.content.subtitle,
                threadIdentifier: notif.request.content.threadIdentifier.isEmpty ? nil : notif.request.content.threadIdentifier,
                categoryIdentifier: notif.request.content.categoryIdentifier.isEmpty ? nil : notif.request.content.categoryIdentifier,
                date: isoFormatter.string(from: notif.date)
            )
        }
    }

    public func removeDelivered(identifiers: [String]) throws {
        try center().removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    public func removeAllDelivered() throws {
        try center().removeAllDeliveredNotifications()
    }

    // MARK: - Categories

    public func registerCategory(
        identifier: String, actions: [UNNotificationAction],
        hiddenPreviewPlaceholder: String?, customDismissAction: Bool
    ) throws {
        // Get existing categories first, then add the new one
        let semaphore = DispatchSemaphore(value: 0)
        var existingCategories: Set<UNNotificationCategory> = []

        try center().getNotificationCategories { cats in
            existingCategories = cats
            semaphore.signal()
        }

        semaphore.wait()

        // Remove existing category with same identifier
        existingCategories = existingCategories.filter { $0.identifier != identifier }

        var options: UNNotificationCategoryOptions = []
        if customDismissAction {
            options.insert(.customDismissAction)
        }

        let category: UNNotificationCategory
        if let placeholder = hiddenPreviewPlaceholder {
            category = UNNotificationCategory(
                identifier: identifier,
                actions: actions,
                intentIdentifiers: [],
                hiddenPreviewsBodyPlaceholder: placeholder,
                options: options
            )
        } else {
            category = UNNotificationCategory(
                identifier: identifier,
                actions: actions,
                intentIdentifiers: [],
                options: options
            )
        }

        existingCategories.insert(category)
        try center().setNotificationCategories(existingCategories)
    }

    // MARK: - UNUserNotificationCenterDelegate

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notification as banner+sound even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        var userText: String? = nil
        if let textResponse = response as? UNTextInputNotificationResponse {
            userText = textResponse.userText
        }

        // Convert [AnyHashable: Any] to [String: Any], filtering non-serializable values
        var userInfo: [String: Any] = [:]
        for (key, value) in response.notification.request.content.userInfo {
            guard let stringKey = key as? String else { continue }
            if value is String || value is Int || value is Double || value is Bool {
                userInfo[stringKey] = value
            } else if let array = value as? [Any] {
                userInfo[stringKey] = array
            } else if let dict = value as? [String: Any] {
                userInfo[stringKey] = dict
            } else {
                userInfo[stringKey] = String(describing: value)
            }
        }

        let event = NotificationInteractionEvent(
            notificationIdentifier: response.notification.request.identifier,
            actionIdentifier: response.actionIdentifier,
            userText: userText,
            userInfo: userInfo,
            categoryIdentifier: response.notification.request.content.categoryIdentifier
        )

        interactionHandler?(event)
        completionHandler()
    }

    // MARK: - Mapping Helpers

    private func mapAuthorizationStatus(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "notDetermined"
        case .denied: return "denied"
        case .authorized: return "authorized"
        case .provisional: return "provisional"
        case .ephemeral: return "ephemeral"
        @unknown default: return "notDetermined"
        }
    }

    private func mapAlertSetting(_ setting: UNNotificationSetting) -> String {
        switch setting {
        case .notSupported: return "notSupported"
        case .disabled: return "disabled"
        case .enabled: return "enabled"
        @unknown default: return "notSupported"
        }
    }

    private func mapAlertStyle(_ style: UNAlertStyle) -> String {
        switch style {
        case .none: return "none"
        case .banner: return "banner"
        case .alert: return "alert"
        @unknown default: return "none"
        }
    }
}
