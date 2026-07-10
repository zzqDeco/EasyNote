import EventKit
import Foundation
import UserNotifications

enum ReminderCallbackBridgeError: Error, Equatable {
    case timedOut
}

enum ReminderCallbackBridge {
    static let defaultTimeoutNanoseconds: UInt64 = 10_000_000_000

    static func value<Value: Sendable>(
        timeoutNanoseconds: UInt64 = defaultTimeoutNanoseconds,
        operation: @Sendable (@escaping @Sendable (Result<Value, Error>) -> Void) -> Void
    ) async throws -> Value {
        let gate = CheckedContinuationGate<Value>()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard gate.install(continuation) else {
                    return
                }

                let timeoutTask = Task {
                    do {
                        try await Task.sleep(nanoseconds: timeoutNanoseconds)
                    } catch {
                        return
                    }

                    gate.resolve(.failure(ReminderCallbackBridgeError.timedOut))
                }
                gate.setTimeoutTask(timeoutTask)

                operation { result in
                    gate.resolve(result)
                }
            }
        } onCancel: {
            gate.resolve(.failure(CancellationError()))
        }
    }
}

private final class CheckedContinuationGate<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var pendingResult: Result<Value, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var isResolved = false

    func install(_ continuation: CheckedContinuation<Value, Error>) -> Bool {
        lock.lock()
        if isResolved {
            let result = pendingResult
            pendingResult = nil
            lock.unlock()

            if let result {
                continuation.resume(with: result)
            }
            return false
        }

        self.continuation = continuation
        lock.unlock()
        return true
    }

    func setTimeoutTask(_ task: Task<Void, Never>) {
        lock.lock()
        if isResolved {
            lock.unlock()
            task.cancel()
            return
        }

        timeoutTask = task
        lock.unlock()
    }

    func resolve(_ result: Result<Value, Error>) {
        lock.lock()
        guard !isResolved else {
            lock.unlock()
            return
        }

        isResolved = true
        let continuation = continuation
        self.continuation = nil
        let timeoutTask = timeoutTask
        self.timeoutTask = nil

        if continuation == nil {
            pendingResult = result
        }
        lock.unlock()

        timeoutTask?.cancel()
        continuation?.resume(with: result)
    }
}

protocol UserNotificationCenterProviding: AnyObject, Sendable {
    func setDelegate(_ delegate: (any UNUserNotificationCenterDelegate)?)
    func authorizationStatus() async -> TodoNotificationAuthorizationStatus
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func add(_ request: UNNotificationRequest) async throws
    func pendingNotificationRequests() async -> [UNNotificationRequest]
    func deliveredNotifications() async -> [UNNotification]
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
    func removeDeliveredNotifications(withIdentifiers identifiers: [String])
}

final class UserNotificationCenterAdapter: UserNotificationCenterProviding, @unchecked Sendable {
    private let notificationCenter: UNUserNotificationCenter

    init(notificationCenter: UNUserNotificationCenter = .current()) {
        self.notificationCenter = notificationCenter
    }

    func setDelegate(_ delegate: (any UNUserNotificationCenterDelegate)?) {
        notificationCenter.delegate = delegate
    }

    func authorizationStatus() async -> TodoNotificationAuthorizationStatus {
        let settings = await notificationCenter.notificationSettings()
        return TodoNotificationAuthorizationStatus(settings.authorizationStatus)
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        try await notificationCenter.requestAuthorization(options: options)
    }

    func add(_ request: UNNotificationRequest) async throws {
        try await notificationCenter.add(request)
    }

    func pendingNotificationRequests() async -> [UNNotificationRequest] {
        await notificationCenter.pendingNotificationRequests()
    }

    func deliveredNotifications() async -> [UNNotification] {
        await notificationCenter.deliveredNotifications()
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
        notificationCenter.removeDeliveredNotifications(withIdentifiers: identifiers)
    }
}

struct SystemReminderRecord: Equatable, Sendable {
    let identifier: String
    let notes: String?
}

protocol SystemReminderEventStoreProviding: AnyObject, Sendable {
    var authorizationStatus: SystemReminderAuthorizationStatus { get }

    func requestFullAccessToReminders(
        completion: @escaping @Sendable (Result<Bool, Error>) -> Void
    )
    func defaultCalendarIdentifier() -> String?
    func fetchReminders(
        completion: @escaping @Sendable (Result<[SystemReminderRecord], Error>) -> Void
    )
    func saveReminder(
        proposal: SystemReminderProposal,
        existingIdentifier: String?,
        calendarIdentifier: String
    ) throws
    func markReminderCompleted(identifier: String) throws
    func removeReminder(identifier: String) throws
}

final class EventKitReminderStoreAdapter: SystemReminderEventStoreProviding, @unchecked Sendable {
    private let eventStore: EKEventStore

    var authorizationStatus: SystemReminderAuthorizationStatus {
        SystemReminderAuthorizationStatus(EKEventStore.authorizationStatus(for: .reminder))
    }

    init(eventStore: EKEventStore = EKEventStore()) {
        self.eventStore = eventStore
    }

    func requestFullAccessToReminders(
        completion: @escaping @Sendable (Result<Bool, Error>) -> Void
    ) {
        eventStore.requestFullAccessToReminders { granted, error in
            if let error {
                completion(.failure(error))
            } else {
                completion(.success(granted))
            }
        }
    }

    func defaultCalendarIdentifier() -> String? {
        eventStore.defaultCalendarForNewReminders()?.calendarIdentifier
    }

    func fetchReminders(
        completion: @escaping @Sendable (Result<[SystemReminderRecord], Error>) -> Void
    ) {
        let predicate = eventStore.predicateForReminders(in: nil)
        eventStore.fetchReminders(matching: predicate) { reminders in
            let records = (reminders ?? []).map {
                SystemReminderRecord(identifier: $0.calendarItemIdentifier, notes: $0.notes)
            }
            completion(.success(records))
        }
    }

    func saveReminder(
        proposal: SystemReminderProposal,
        existingIdentifier: String?,
        calendarIdentifier: String
    ) throws {
        guard let calendar = eventStore.calendar(withIdentifier: calendarIdentifier) else {
            throw SystemReminderError.missingDefaultReminderList
        }

        let reminder = existingIdentifier
            .flatMap { eventStore.calendarItem(withIdentifier: $0) as? EKReminder }
            ?? EKReminder(eventStore: eventStore)

        reminder.calendar = calendar
        reminder.title = proposal.title
        reminder.notes = Self.notesWithMarker(notes: proposal.notes, marker: proposal.marker)
        reminder.dueDateComponents = Self.dateComponents(for: proposal.dueDate)
        reminder.priority = Self.priorityValue(for: proposal.priority)
        reminder.isCompleted = false
        reminder.alarms?.forEach { reminder.removeAlarm($0) }
        reminder.addAlarm(EKAlarm(absoluteDate: proposal.alarmDate))

        try eventStore.save(reminder, commit: true)
    }

    func markReminderCompleted(identifier: String) throws {
        guard let reminder = eventStore.calendarItem(withIdentifier: identifier) as? EKReminder else {
            return
        }

        reminder.isCompleted = true
        try eventStore.save(reminder, commit: true)
    }

    func removeReminder(identifier: String) throws {
        guard let reminder = eventStore.calendarItem(withIdentifier: identifier) as? EKReminder else {
            return
        }

        try eventStore.remove(reminder, commit: true)
    }

    private static func dateComponents(for date: Date) -> DateComponents {
        var components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        components.timeZone = Calendar.current.timeZone
        return components
    }

    private static func notesWithMarker(notes: String?, marker: String) -> String {
        let trimmedNotes = notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmedNotes.isEmpty {
            return marker
        }

        return "\(trimmedNotes)\n\n\(marker)"
    }

    private static func priorityValue(for priority: TodoItem.PriorityLevel) -> Int {
        switch priority {
        case .high:
            return 1
        case .medium:
            return 5
        case .low:
            return 9
        }
    }
}

extension TodoNotificationAuthorizationStatus {
    init(_ status: UNAuthorizationStatus) {
        switch status {
        case .notDetermined:
            self = .notDetermined
        case .denied:
            self = .denied
        case .authorized:
            self = .authorized
        case .provisional:
            self = .provisional
        case .ephemeral:
            self = .ephemeral
        @unknown default:
            self = .unknown
        }
    }
}

extension SystemReminderAuthorizationStatus {
    init(_ status: EKAuthorizationStatus) {
        switch status {
        case .notDetermined:
            self = .notDetermined
        case .restricted:
            self = .restricted
        case .denied:
            self = .denied
        case .authorized, .fullAccess:
            self = .fullAccess
        case .writeOnly:
            self = .denied
        @unknown default:
            self = .unknown
        }
    }
}
