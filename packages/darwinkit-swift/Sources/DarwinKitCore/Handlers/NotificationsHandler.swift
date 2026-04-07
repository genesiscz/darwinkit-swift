import Foundation
import UserNotifications

/// Handles all notifications.* JSON-RPC methods for macOS user notifications.
public final class NotificationsHandler: MethodHandler {
    private let provider: NotificationsProvider
    private weak var notificationSink: NotificationSink?

    public var methods: [String] {
        [
            "notifications.request_authorization",
            "notifications.settings",
            "notifications.send",
            "notifications.list_pending",
            "notifications.remove_pending",
            "notifications.remove_all_pending",
            "notifications.list_delivered",
            "notifications.remove_delivered",
            "notifications.remove_all_delivered",
            "notifications.register_category",
        ]
    }

    public init(provider: NotificationsProvider = AppleNotificationsProvider(), notificationSink: NotificationSink? = nil) {
        self.provider = provider
        self.notificationSink = notificationSink

        // Wire up interaction callbacks to push via NotificationSink
        if let sink = notificationSink {
            provider.setInteractionHandler { event in
                sink.sendNotification(method: "notifications.interaction", params: event.toDict())
            }
        }
    }

    public func handle(_ request: JsonRpcRequest) throws -> Any {
        switch request.method {
        case "notifications.request_authorization":
            return try handleRequestAuthorization(request)
        case "notifications.settings":
            return try handleSettings(request)
        case "notifications.send":
            return try handleSend(request)
        case "notifications.list_pending":
            return try handleListPending(request)
        case "notifications.remove_pending":
            return try handleRemovePending(request)
        case "notifications.remove_all_pending":
            return try handleRemoveAllPending(request)
        case "notifications.list_delivered":
            return try handleListDelivered(request)
        case "notifications.remove_delivered":
            return try handleRemoveDelivered(request)
        case "notifications.remove_all_delivered":
            return try handleRemoveAllDelivered(request)
        case "notifications.register_category":
            return try handleRegisterCategory(request)
        default:
            throw JsonRpcError.methodNotFound(request.method)
        }
    }

    public func capability(for method: String) -> MethodCapability {
        return MethodCapability(available: true, note: "Requires macOS 14+ and notification permission")
    }

    // MARK: - Method Implementations

    private func handleRequestAuthorization(_ request: JsonRpcRequest) throws -> Any {
        var options: UNAuthorizationOptions = []

        if let optionStrings = request.stringArray("options") {
            for opt in optionStrings {
                switch opt {
                case "alert": options.insert(.alert)
                case "sound": options.insert(.sound)
                case "badge": options.insert(.badge)
                case "criticalAlert": options.insert(.criticalAlert)
                case "provisional": options.insert(.provisional)
                default: break
                }
            }
        } else {
            // Default to alert + sound + badge
            options = [.alert, .sound, .badge]
        }

        let granted = try provider.requestAuthorization(options: options)
        return ["granted": granted] as [String: Any]
    }

    private func handleSettings(_ request: JsonRpcRequest) throws -> Any {
        let settings = try provider.getSettings()
        return settings.toDict()
    }

    private func handleSend(_ request: JsonRpcRequest) throws -> Any {
        let title = try request.requireString("title")
        let body = try request.requireString("body")
        let subtitle = request.string("subtitle")
        let identifier = request.string("identifier") ?? UUID().uuidString
        let threadIdentifier = request.string("thread_identifier")
        let categoryIdentifier = request.string("category_identifier")
        let badge = request.int("badge")
        let attachments = request.stringArray("attachments")

        // Parse sound
        let sound = parseSoundParam(request)

        // Parse trigger
        let trigger = try parseTriggerParam(request)

        // Parse user_info
        let userInfo = request.params?["user_info"]?.dictValue

        try provider.send(
            title: title, body: body, subtitle: subtitle,
            identifier: identifier, sound: sound,
            badge: badge.map { NSNumber(value: $0) },
            threadIdentifier: threadIdentifier,
            categoryIdentifier: categoryIdentifier,
            userInfo: userInfo,
            attachmentPaths: attachments,
            trigger: trigger
        )

        return ["ok": true, "identifier": identifier] as [String: Any]
    }

    private func handleListPending(_ request: JsonRpcRequest) throws -> Any {
        let pending = try provider.listPending()
        return ["notifications": pending.map { $0.toDict() }] as [String: Any]
    }

    private func handleRemovePending(_ request: JsonRpcRequest) throws -> Any {
        guard let identifiers = request.stringArray("identifiers") else {
            throw JsonRpcError.invalidParams("Missing required param: identifiers")
        }
        try provider.removePending(identifiers: identifiers)
        return ["ok": true] as [String: Any]
    }

    private func handleRemoveAllPending(_ request: JsonRpcRequest) throws -> Any {
        try provider.removeAllPending()
        return ["ok": true] as [String: Any]
    }

    private func handleListDelivered(_ request: JsonRpcRequest) throws -> Any {
        let delivered = try provider.listDelivered()
        return ["notifications": delivered.map { $0.toDict() }] as [String: Any]
    }

    private func handleRemoveDelivered(_ request: JsonRpcRequest) throws -> Any {
        guard let identifiers = request.stringArray("identifiers") else {
            throw JsonRpcError.invalidParams("Missing required param: identifiers")
        }
        try provider.removeDelivered(identifiers: identifiers)
        return ["ok": true] as [String: Any]
    }

    private func handleRemoveAllDelivered(_ request: JsonRpcRequest) throws -> Any {
        try provider.removeAllDelivered()
        return ["ok": true] as [String: Any]
    }

    private func handleRegisterCategory(_ request: JsonRpcRequest) throws -> Any {
        let identifier = try request.requireString("identifier")
        let customDismissAction = request.bool("custom_dismiss_action") ?? false
        let hiddenPreviewPlaceholder = request.string("hidden_preview_placeholder")

        guard let actionsArray = request.params?["actions"]?.arrayValue else {
            throw JsonRpcError.invalidParams("Missing required param: actions")
        }

        var actions: [UNNotificationAction] = []
        for actionAny in actionsArray {
            guard let actionDict = actionAny as? [String: Any] else {
                throw JsonRpcError.invalidParams("Each action must be an object")
            }

            guard let actionId = actionDict["identifier"] as? String else {
                throw JsonRpcError.invalidParams("Each action must have an identifier")
            }
            guard let actionTitle = actionDict["title"] as? String else {
                throw JsonRpcError.invalidParams("Each action must have a title")
            }

            let isTextInput = actionDict["text_input"] as? Bool ?? false
            let destructive = actionDict["destructive"] as? Bool ?? false
            let authRequired = actionDict["auth_required"] as? Bool ?? false

            var actionOptions: UNNotificationActionOptions = []
            if destructive { actionOptions.insert(.destructive) }
            if authRequired { actionOptions.insert(.authenticationRequired) }

            if isTextInput {
                let buttonTitle = actionDict["text_input_button_title"] as? String ?? "Send"
                let placeholder = actionDict["text_input_placeholder"] as? String ?? ""
                actions.append(UNTextInputNotificationAction(
                    identifier: actionId,
                    title: actionTitle,
                    options: actionOptions,
                    textInputButtonTitle: buttonTitle,
                    textInputPlaceholder: placeholder
                ))
            } else {
                actions.append(UNNotificationAction(
                    identifier: actionId,
                    title: actionTitle,
                    options: actionOptions
                ))
            }
        }

        try provider.registerCategory(
            identifier: identifier,
            actions: actions,
            hiddenPreviewPlaceholder: hiddenPreviewPlaceholder,
            customDismissAction: customDismissAction
        )

        return ["ok": true] as [String: Any]
    }

    // MARK: - Param Parsing Helpers

    private func parseSoundParam(_ request: JsonRpcRequest) -> UNNotificationSound? {
        guard let soundParam = request.params?["sound"] else {
            return .default
        }

        // String values: "default" or "none"
        if let soundStr = soundParam.stringValue {
            switch soundStr {
            case "default": return .default
            case "none": return nil
            default: return .default
            }
        }

        // Object: { named: "soundName" } or { critical: { volume?: 0.5 } }
        if let soundDict = soundParam.dictValue {
            if let named = soundDict["named"] as? String {
                return UNNotificationSound(named: UNNotificationSoundName(named))
            }
            if let criticalDict = soundDict["critical"] as? [String: Any] {
                let volume = criticalDict["volume"] as? Float ?? 1.0
                return UNNotificationSound.defaultCriticalSound(withAudioVolume: volume)
            }
        }

        return .default
    }

    private func parseTriggerParam(_ request: JsonRpcRequest) throws -> UNNotificationTrigger? {
        guard let triggerParam = request.params?["trigger"]?.dictValue else {
            return nil
        }

        guard let type = triggerParam["type"] as? String else {
            throw JsonRpcError.invalidParams("trigger must have a 'type' field")
        }

        switch type {
        case "timeInterval":
            guard let seconds = triggerParam["seconds"] as? Double, seconds > 0 else {
                throw JsonRpcError.invalidParams("timeInterval trigger requires 'seconds' > 0")
            }
            let repeats = triggerParam["repeats"] as? Bool ?? false
            return UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: repeats)

        case "calendar":
            var components = DateComponents()
            if let year = triggerParam["year"] as? Int { components.year = year }
            if let month = triggerParam["month"] as? Int { components.month = month }
            if let day = triggerParam["day"] as? Int { components.day = day }
            if let hour = triggerParam["hour"] as? Int { components.hour = hour }
            if let minute = triggerParam["minute"] as? Int { components.minute = minute }
            if let second = triggerParam["second"] as? Int { components.second = second }
            if let weekday = triggerParam["weekday"] as? Int { components.weekday = weekday }
            let repeats = triggerParam["repeats"] as? Bool ?? false
            return UNCalendarNotificationTrigger(dateMatching: components, repeats: repeats)

        default:
            throw JsonRpcError.invalidParams("Unknown trigger type: \(type). Use 'timeInterval' or 'calendar'.")
        }
    }
}
