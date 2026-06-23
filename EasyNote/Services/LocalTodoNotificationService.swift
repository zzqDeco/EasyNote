import Combine
import Foundation
import UserNotifications

enum TodoNotificationAuthorizationStatus: String, Equatable {
    case notDetermined
    case denied
    case authorized
    case provisional
    case ephemeral
    case unknown

    var allowsScheduling: Bool {
        switch self {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined, .denied, .unknown:
            return false
        }
    }
}

final class LocalTodoNotificationService: TodoNotificationSchedulingProviding {
    static let shared = LocalTodoNotificationService()
    static let enabledDefaultsKey = "todo_notifications_enabled"

    private let notificationCenter: UNUserNotificationCenter
    private let defaults: UserDefaults
    private let authorizationStatusSubject = CurrentValueSubject<TodoNotificationAuthorizationStatus, Never>(.notDetermined)

    var authorizationStatusPublisher: AnyPublisher<TodoNotificationAuthorizationStatus, Never> {
        authorizationStatusSubject.eraseToAnyPublisher()
    }

    init(
        notificationCenter: UNUserNotificationCenter = .current(),
        defaults: UserDefaults = .standard
    ) {
        self.notificationCenter = notificationCenter
        self.defaults = defaults
        refreshAuthorizationStatus()
    }

    func refreshAuthorizationStatus() {
        notificationCenter.getNotificationSettings { [weak self] settings in
            let status = Self.mapAuthorizationStatus(settings.authorizationStatus)
            DispatchQueue.main.async {
                self?.authorizationStatusSubject.send(status)
            }
        }
    }

    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        notificationCenter.requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, _ in
            self?.refreshAuthorizationStatus()
            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }

    func synchronizeNotification(for todo: TodoItem) {
        guard defaults.bool(forKey: Self.enabledDefaultsKey),
              TodoNotificationPlanner.shouldScheduleNotification(for: todo),
              let deadline = todo.deadline else {
            cancelNotification(forTodoID: todo.id)
            return
        }

        let todoID = todo.id
        let title = todo.title
        let notes = todo.notes

        notificationCenter.getNotificationSettings { [weak self] settings in
            guard let self else { return }

            let status = Self.mapAuthorizationStatus(settings.authorizationStatus)
            DispatchQueue.main.async {
                self.authorizationStatusSubject.send(status)
            }

            guard status.allowsScheduling else {
                return
            }

            let identifier = TodoNotificationPlanner.notificationIdentifier(for: todoID)
            self.notificationCenter.removePendingNotificationRequests(withIdentifiers: [identifier])

            let content = UNMutableNotificationContent()
            content.title = title.isEmpty ? "待办提醒" : title
            content.body = notes.flatMap { $0.isEmpty ? nil : $0 } ?? "待办事项已到截止时间"
            content.sound = .default
            content.userInfo = ["todoID": todoID.uuidString]

            var dateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: deadline
            )
            dateComponents.timeZone = Calendar.current.timeZone

            let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            self.notificationCenter.add(request)
        }
    }

    func reconcileNotifications(for todos: [TodoItem]) {
        todos.forEach { synchronizeNotification(for: $0) }
    }

    func cancelNotification(forTodoID id: UUID) {
        let identifier = TodoNotificationPlanner.notificationIdentifier(for: id)
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [identifier])
        notificationCenter.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    func cancelAllTodoNotifications() {
        notificationCenter.getPendingNotificationRequests { [weak self] requests in
            let identifiers = requests
                .map(\.identifier)
                .filter { $0.hasPrefix(TodoNotificationPlanner.notificationIdentifierPrefix) }

            self?.notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiers)
        }

        notificationCenter.getDeliveredNotifications { [weak self] notifications in
            let identifiers = notifications
                .map(\.request.identifier)
                .filter { $0.hasPrefix(TodoNotificationPlanner.notificationIdentifierPrefix) }

            self?.notificationCenter.removeDeliveredNotifications(withIdentifiers: identifiers)
        }
    }

    private static func mapAuthorizationStatus(_ status: UNAuthorizationStatus) -> TodoNotificationAuthorizationStatus {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .authorized:
            return .authorized
        case .provisional:
            return .provisional
        case .ephemeral:
            return .ephemeral
        @unknown default:
            return .unknown
        }
    }
}
