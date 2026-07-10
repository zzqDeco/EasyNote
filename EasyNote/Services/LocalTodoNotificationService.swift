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

enum TodoNotificationError: Error, Equatable, LocalizedError {
    case authorizationDenied
    case authorizationRequestFailed(String)
    case schedulingFailed(String)

    var errorDescription: String? {
        switch self {
        case .authorizationDenied:
            return "未授予通知权限"
        case .authorizationRequestFailed(let message):
            return "请求通知权限失败: \(message)"
        case .schedulingFailed(let message):
            return "写入 EasyNote 通知失败: \(message)"
        }
    }
}

final class LocalTodoNotificationService: NSObject, TodoNotificationSchedulingProviding, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = LocalTodoNotificationService()
    static let enabledDefaultsKey = "todo_notifications_enabled"

    private let notificationCenter: any UserNotificationCenterProviding
    private let defaults: UserDefaults
    private let authorizationStatusSubject = CurrentValueSubject<TodoNotificationAuthorizationStatus, Never>(.notDetermined)
    private let mutationGate = TodoNotificationMutationGate()
    private let scheduleVersionLock = NSLock()
    private var scheduleVersions: [UUID: Int] = [:]
    private var bulkCancellationVersion = 0

    var authorizationStatusPublisher: AnyPublisher<TodoNotificationAuthorizationStatus, Never> {
        authorizationStatusSubject.eraseToAnyPublisher()
    }

    convenience init(
        notificationCenter: UNUserNotificationCenter = .current(),
        defaults: UserDefaults = .standard
    ) {
        self.init(
            notificationCenterAdapter: UserNotificationCenterAdapter(notificationCenter: notificationCenter),
            defaults: defaults
        )
    }

    init(
        notificationCenterAdapter: any UserNotificationCenterProviding,
        defaults: UserDefaults = .standard
    ) {
        self.notificationCenter = notificationCenterAdapter
        self.defaults = defaults
        super.init()
        self.notificationCenter.setDelegate(self)
    }

    func refreshAuthorizationStatus() async -> TodoNotificationAuthorizationStatus {
        let status = await notificationCenter.authorizationStatus()
        await publishAuthorizationStatus(status)
        return status
    }

    func requestAuthorization() async throws {
        let granted: Bool
        do {
            granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw TodoNotificationError.authorizationRequestFailed(error.localizedDescription)
        }

        _ = await refreshAuthorizationStatus()
        guard granted else {
            throw TodoNotificationError.authorizationDenied
        }
    }

    func synchronizeNotification(for todo: TodoItem) async throws {
        guard defaults.bool(forKey: Self.enabledDefaultsKey),
              TodoNotificationPlanner.shouldScheduleNotification(for: todo),
              let deadline = todo.deadline else {
            await cancelNotification(forTodoID: todo.id)
            return
        }

        let todoID = todo.id
        let title = todo.title
        let notes = todo.notes
        invalidateBulkCancellation()
        let scheduleVersion = nextScheduleVersion(for: todoID)
        let status = await notificationCenter.authorizationStatus()
        await publishAuthorizationStatus(status)

        await mutationGate.acquire(for: todoID)
        do {
            try await writeNotification(
                todoID: todoID,
                title: title,
                notes: notes,
                deadline: deadline,
                scheduleVersion: scheduleVersion,
                status: status
            )
            await mutationGate.release(for: todoID)
        } catch {
            await mutationGate.release(for: todoID)
            throw error
        }
    }

    private func writeNotification(
        todoID: UUID,
        title: String,
        notes: String?,
        deadline: Date,
        scheduleVersion: Int,
        status: TodoNotificationAuthorizationStatus
    ) async throws {
        try Task.checkCancellation()

        guard isCurrentScheduleVersion(scheduleVersion, for: todoID) else {
            return
        }

        guard defaults.bool(forKey: Self.enabledDefaultsKey), deadline > Date() else {
            removeNotificationRequests(forTodoID: todoID)
            return
        }

        guard status.allowsScheduling else {
            removeNotificationRequests(forTodoID: todoID)
            throw TodoNotificationError.authorizationDenied
        }

        removeNotificationRequests(forTodoID: todoID)
        let request = Self.makeNotificationRequest(
            todoID: todoID,
            title: title,
            notes: notes,
            deadline: deadline
        )

        do {
            try await notificationCenter.add(request)
        } catch is CancellationError {
            removeNotificationRequests(forTodoID: todoID)
            throw CancellationError()
        } catch {
            throw TodoNotificationError.schedulingFailed(error.localizedDescription)
        }

        guard !Task.isCancelled,
              isCurrentScheduleVersion(scheduleVersion, for: todoID),
              defaults.bool(forKey: Self.enabledDefaultsKey),
              deadline > Date() else {
            removeNotificationRequests(forTodoID: todoID)
            if Task.isCancelled {
                throw CancellationError()
            }
            return
        }
    }

    func reconcileNotifications(for todos: [TodoItem]) async throws {
        let retainedTodos = TodoNotificationPlanner.retainedNotificationTodos(from: todos)
        let retainedIDs = Set(retainedTodos.map(\.id))

        for todo in todos where !retainedIDs.contains(todo.id) {
            await cancelNotification(forTodoID: todo.id)
        }

        var firstError: Error?
        for todo in retainedTodos {
            do {
                try Task.checkCancellation()
                try await synchronizeNotification(for: todo)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if firstError == nil {
                    firstError = error
                }
            }
        }

        if let firstError {
            throw firstError
        }
    }

    func cancelNotification(forTodoID id: UUID) async {
        invalidateSchedule(for: id)
        removeNotificationRequests(forTodoID: id)
    }

    func cancelAllTodoNotifications() async {
        invalidateAllSchedules()
        let cancellationVersion = nextBulkCancellationVersion()

        let pendingIdentifiers = await notificationCenter.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(TodoNotificationPlanner.notificationIdentifierPrefix) }
        let deliveredIdentifiers = await notificationCenter.deliveredNotifications()
            .map(\.request.identifier)
            .filter { $0.hasPrefix(TodoNotificationPlanner.notificationIdentifierPrefix) }

        guard isCurrentBulkCancellationVersion(cancellationVersion) else {
            return
        }

        notificationCenter.removePendingNotificationRequests(withIdentifiers: pendingIdentifiers)
        notificationCenter.removeDeliveredNotifications(withIdentifiers: deliveredIdentifiers)
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

    @MainActor
    private func publishAuthorizationStatus(_ status: TodoNotificationAuthorizationStatus) {
        authorizationStatusSubject.send(status)
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

    private static func makeNotificationRequest(
        todoID: UUID,
        title: String,
        notes: String?,
        deadline: Date
    ) -> UNNotificationRequest {
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
        return UNNotificationRequest(
            identifier: TodoNotificationPlanner.notificationIdentifier(for: todoID),
            content: content,
            trigger: trigger
        )
    }
}

private actor TodoNotificationMutationGate {
    private var activeTodoIDs: Set<UUID> = []
    private var waiters: [UUID: [CheckedContinuation<Void, Never>]] = [:]

    func acquire(for todoID: UUID) async {
        guard activeTodoIDs.contains(todoID) else {
            activeTodoIDs.insert(todoID)
            return
        }

        await withCheckedContinuation { continuation in
            waiters[todoID, default: []].append(continuation)
        }
    }

    func release(for todoID: UUID) {
        guard var todoWaiters = waiters[todoID], !todoWaiters.isEmpty else {
            activeTodoIDs.remove(todoID)
            waiters[todoID] = nil
            return
        }

        let next = todoWaiters.removeFirst()
        waiters[todoID] = todoWaiters.isEmpty ? nil : todoWaiters
        next.resume()
    }
}
