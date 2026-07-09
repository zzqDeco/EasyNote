import Foundation

enum TodoReminderMode: String, CaseIterable, Codable, Identifiable {
    case off
    case localNotification
    case systemReminderAgent

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off:
            return "关闭"
        case .localNotification:
            return "EasyNote 通知"
        case .systemReminderAgent:
            return "系统提醒事项"
        }
    }
}

protocol TodoReminderModeProviding: AnyObject {
    var currentMode: TodoReminderMode { get set }
    var systemRemindersMayExist: Bool { get set }
}

enum TodoReminderModeTransitionPlanner {
    static func shouldRemoveSystemReminders(
        previousMode: TodoReminderMode,
        nextMode: TodoReminderMode,
        systemRemindersMayExist: Bool
    ) -> Bool {
        guard nextMode == .localNotification else {
            return false
        }

        return previousMode == .systemReminderAgent || (previousMode == .off && systemRemindersMayExist)
    }

    static func shouldSyncSystemReminders(nextMode: TodoReminderMode) -> Bool {
        nextMode == .systemReminderAgent
    }
}

final class TodoReminderModeStore: TodoReminderModeProviding {
    static let modeDefaultsKey = "todo_reminder_mode"
    static let legacyLocalNotificationEnabledDefaultsKey = "todo_notifications_enabled"
    static let systemRemindersMayExistDefaultsKey = "todo_system_reminders_may_exist"

    private let defaults: UserDefaults
    private let localNotificationEnabledKey: String

    init(
        defaults: UserDefaults = .standard,
        localNotificationEnabledKey: String = TodoReminderModeStore.legacyLocalNotificationEnabledDefaultsKey
    ) {
        self.defaults = defaults
        self.localNotificationEnabledKey = localNotificationEnabledKey
    }

    var currentMode: TodoReminderMode {
        get {
            if let rawValue = defaults.string(forKey: Self.modeDefaultsKey),
               let mode = TodoReminderMode(rawValue: rawValue) {
                return mode
            }

            if defaults.bool(forKey: localNotificationEnabledKey) {
                return .localNotification
            }

            return .off
        }
        set {
            defaults.set(newValue.rawValue, forKey: Self.modeDefaultsKey)
            defaults.set(newValue == .localNotification, forKey: localNotificationEnabledKey)
        }
    }

    var systemRemindersMayExist: Bool {
        get {
            defaults.bool(forKey: Self.systemRemindersMayExistDefaultsKey)
        }
        set {
            defaults.set(newValue, forKey: Self.systemRemindersMayExistDefaultsKey)
        }
    }
}
