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

final class LocalTodoNotificationService: NSObject, TodoNotificationSchedulingProviding, UNUserNotificationCenterDelegate {
    static let shared = LocalTodoNotificationService()
    static let enabledDefaultsKey = "todo_notifications_enabled"

    private let notificationCenter: UNUserNotificationCenter
    private let defaults: UserDefaults
    private let authorizationStatusSubject = CurrentValueSubject<TodoNotificationAuthorizationStatus, Never>(.notDetermined)
    private let notificationQueue = DispatchQueue(label: "EasyNote.TodoNotifications")
    private let scheduleVersionLock = NSLock()
    private var scheduleVersions: [UUID: Int] = [:]
    private var bulkCancellationVersion = 0

    var authorizationStatusPublisher: AnyPublisher<TodoNotificationAuthorizationStatus, Never> {
        authorizationStatusSubject.eraseToAnyPublisher()
    }

    init(
        notificationCenter: UNUserNotificationCenter = .current(),
        defaults: UserDefaults = .standard
    ) {
        self.notificationCenter = notificationCenter
        self.defaults = defaults
        super.init()
        self.notificationCenter.delegate = self
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
        invalidateBulkCancellation()
        let scheduleVersion = nextScheduleVersion(for: todoID)

        notificationCenter.getNotificationSettings { [weak self] settings in
            guard let self else { return }

            let status = Self.mapAuthorizationStatus(settings.authorizationStatus)
            DispatchQueue.main.async {
                self.authorizationStatusSubject.send(status)
            }

            self.notificationQueue.async {
                guard self.isCurrentScheduleVersion(scheduleVersion, for: todoID) else {
                    return
                }

                let identifier = TodoNotificationPlanner.notificationIdentifier(for: todoID)

                guard self.defaults.bool(forKey: Self.enabledDefaultsKey), deadline > Date() else {
                    self.removeNotificationRequests(forTodoID: todoID)
                    return
                }

                guard status.allowsScheduling else {
                    self.removeNotificationRequests(forTodoID: todoID)
                    return
                }

                self.removeNotificationRequests(forTodoID: todoID)

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
                let addCompletion = DispatchSemaphore(value: 0)
                self.notificationCenter.add(request) { _ in
                    addCompletion.signal()
                }
                addCompletion.wait()

                guard self.isCurrentScheduleVersion(scheduleVersion, for: todoID),
                      self.defaults.bool(forKey: Self.enabledDefaultsKey),
                      deadline > Date() else {
                    self.removeNotificationRequests(forTodoID: todoID)
                    return
                }
            }
        }
    }

    func reconcileNotifications(for todos: [TodoItem]) {
        todos.forEach { synchronizeNotification(for: $0) }
    }

    func cancelNotification(forTodoID id: UUID) {
        invalidateSchedule(for: id)
        notificationQueue.async { [weak self] in
            self?.removeNotificationRequests(forTodoID: id)
        }
    }

    func cancelAllTodoNotifications() {
        invalidateAllSchedules()
        let cancellationVersion = nextBulkCancellationVersion()
        notificationQueue.async { [weak self] in
            self?.removeAllTodoNotificationRequests(cancellationVersion: cancellationVersion)
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if notification.request.identifier.hasPrefix(TodoNotificationPlanner.notificationIdentifierPrefix) {
            completionHandler([.banner, .sound, .badge])
        } else {
            completionHandler([])
        }
    }

    private func nextScheduleVersion(for id: UUID) -> Int {
        scheduleVersionLock.lock()
        defer { scheduleVersionLock.unlock() }

        let nextVersion = (scheduleVersions[id] ?? 0) + 1
        scheduleVersions[id] = nextVersion
        return nextVersion
    }

    private func invalidateSchedule(for id: UUID) {
        _ = nextScheduleVersion(for: id)
    }

    private func invalidateAllSchedules() {
        scheduleVersionLock.lock()
        defer { scheduleVersionLock.unlock() }

        for id in Array(scheduleVersions.keys) {
            scheduleVersions[id, default: 0] += 1
        }
    }

    private func nextBulkCancellationVersion() -> Int {
        scheduleVersionLock.lock()
        defer { scheduleVersionLock.unlock() }

        bulkCancellationVersion += 1
        return bulkCancellationVersion
    }

    private func invalidateBulkCancellation() {
        scheduleVersionLock.lock()
        defer { scheduleVersionLock.unlock() }

        bulkCancellationVersion += 1
    }

    private func isCurrentBulkCancellationVersion(_ version: Int) -> Bool {
        scheduleVersionLock.lock()
        defer { scheduleVersionLock.unlock() }

        return bulkCancellationVersion == version
    }

    private func isCurrentScheduleVersion(_ version: Int, for id: UUID) -> Bool {
        scheduleVersionLock.lock()
        defer { scheduleVersionLock.unlock() }

        return scheduleVersions[id] == version
    }

    private func removeNotificationRequests(forTodoID id: UUID) {
        let identifier = TodoNotificationPlanner.notificationIdentifier(for: id)
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [identifier])
        notificationCenter.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    private func removeAllTodoNotificationRequests(cancellationVersion: Int) {
        notificationCenter.getPendingNotificationRequests { [weak self] requests in
            let identifiers = requests
                .map(\.identifier)
                .filter { $0.hasPrefix(TodoNotificationPlanner.notificationIdentifierPrefix) }

            self?.notificationQueue.async {
                guard let self,
                      self.isCurrentBulkCancellationVersion(cancellationVersion) else {
                    return
                }

                self.notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiers)
            }
        }

        notificationCenter.getDeliveredNotifications { [weak self] notifications in
            let identifiers = notifications
                .map(\.request.identifier)
                .filter { $0.hasPrefix(TodoNotificationPlanner.notificationIdentifierPrefix) }

            self?.notificationQueue.async {
                guard let self,
                      self.isCurrentBulkCancellationVersion(cancellationVersion) else {
                    return
                }

                self.notificationCenter.removeDeliveredNotifications(withIdentifiers: identifiers)
            }
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
