import Combine
import EventKit
import Foundation

enum SystemReminderAuthorizationStatus: Equatable {
    case notDetermined
    case restricted
    case denied
    case fullAccess
    case unknown

    var allowsWriting: Bool {
        self == .fullAccess
    }
}

enum SystemReminderWriteResult: Equatable {
    case created
    case updated
    case skipped
    case completed
    case removed
    case notFound
}

enum SystemReminderError: Error, Equatable, LocalizedError {
    case notAuthorized
    case restricted
    case timeout
    case missingDefaultReminderList
    case eventStore(String)

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "未授予提醒事项权限"
        case .restricted:
            return "系统限制了提醒事项访问"
        case .timeout:
            return "提醒事项操作超时，请稍后重试"
        case .missingDefaultReminderList:
            return "没有可用的默认提醒事项列表"
        case .eventStore(let message):
            return "提醒事项系统错误: \(message)"
        }
    }
}

final class SystemReminderService: SystemReminderWritingProviding, @unchecked Sendable {
    static let shared = SystemReminderService()

    private let eventStoreAdapter: any SystemReminderEventStoreProviding
    private let executor: SystemReminderOperationExecutor
    private let authorizationStatusSubject: CurrentValueSubject<SystemReminderAuthorizationStatus, Never>

    var authorizationStatusPublisher: AnyPublisher<SystemReminderAuthorizationStatus, Never> {
        authorizationStatusSubject.eraseToAnyPublisher()
    }

    convenience init(eventStore: EKEventStore = EKEventStore()) {
        self.init(eventStoreAdapter: EventKitReminderStoreAdapter(eventStore: eventStore))
    }

    init(
        eventStoreAdapter: any SystemReminderEventStoreProviding,
        callbackTimeoutNanoseconds: UInt64 = ReminderCallbackBridge.defaultTimeoutNanoseconds
    ) {
        self.eventStoreAdapter = eventStoreAdapter
        self.executor = SystemReminderOperationExecutor(
            eventStoreAdapter: eventStoreAdapter,
            callbackTimeoutNanoseconds: callbackTimeoutNanoseconds
        )
        self.authorizationStatusSubject = CurrentValueSubject(eventStoreAdapter.authorizationStatus)
    }

    func refreshAuthorizationStatus() async -> SystemReminderAuthorizationStatus {
        let status = eventStoreAdapter.authorizationStatus
        await publishAuthorizationStatus(status)
        return status
    }

    func requestAuthorization() async throws {
        do {
            try await executor.requestAuthorization()
            _ = await refreshAuthorizationStatus()
        } catch {
            _ = await refreshAuthorizationStatus()
            throw error
        }
    }

    func applyProposal(_ proposal: SystemReminderProposal) async throws -> SystemReminderWriteResult {
        do {
            return try await executor.applyProposal(proposal)
        } catch {
            _ = await refreshAuthorizationStatus()
            throw error
        }
    }

    func completeReminder(forTodoID id: UUID) async throws {
        do {
            try await executor.completeReminder(forTodoID: id)
        } catch {
            _ = await refreshAuthorizationStatus()
            throw error
        }
    }

    func removeReminder(forTodoID id: UUID) async throws {
        do {
            try await executor.removeReminder(forTodoID: id)
        } catch {
            _ = await refreshAuthorizationStatus()
            throw error
        }
    }

    @MainActor
    private func publishAuthorizationStatus(_ status: SystemReminderAuthorizationStatus) {
        authorizationStatusSubject.send(status)
    }
}

private actor SystemReminderOperationExecutor {
    private let eventStoreAdapter: any SystemReminderEventStoreProviding
    private let callbackTimeoutNanoseconds: UInt64
    private var operationInProgress = false
    private var operationWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        eventStoreAdapter: any SystemReminderEventStoreProviding,
        callbackTimeoutNanoseconds: UInt64
    ) {
        self.eventStoreAdapter = eventStoreAdapter
        self.callbackTimeoutNanoseconds = callbackTimeoutNanoseconds
    }

    func requestAuthorization() async throws {
        await acquireOperationSlot()
        defer { releaseOperationSlot() }
        try Task.checkCancellation()

        if eventStoreAdapter.authorizationStatus == .restricted {
            throw SystemReminderError.restricted
        }

        let granted: Bool
        do {
            granted = try await ReminderCallbackBridge.value(
                timeoutNanoseconds: callbackTimeoutNanoseconds
            ) { [eventStoreAdapter] completion in
                eventStoreAdapter.requestFullAccessToReminders(completion: completion)
            }
        } catch ReminderCallbackBridgeError.timedOut {
            throw SystemReminderError.timeout
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw SystemReminderError.eventStore(error.localizedDescription)
        }

        guard granted else {
            if eventStoreAdapter.authorizationStatus == .restricted {
                throw SystemReminderError.restricted
            }
            throw SystemReminderError.notAuthorized
        }
    }

    func applyProposal(_ proposal: SystemReminderProposal) async throws -> SystemReminderWriteResult {
        await acquireOperationSlot()
        defer { releaseOperationSlot() }
        try Task.checkCancellation()

        guard proposal.action == .createOrUpdate else {
            return .skipped
        }

        try ensureWritable()
        guard let calendarIdentifier = eventStoreAdapter.defaultCalendarIdentifier() else {
            throw SystemReminderError.missingDefaultReminderList
        }

        var matchingReminders = try await fetchEasyNoteReminders(marker: proposal.marker)
        let existingIdentifier = matchingReminders.first?.identifier
        if !matchingReminders.isEmpty {
            matchingReminders.removeFirst()
        }

        do {
            try eventStoreAdapter.saveReminder(
                proposal: proposal,
                existingIdentifier: existingIdentifier,
                calendarIdentifier: calendarIdentifier
            )

            for duplicate in matchingReminders {
                try eventStoreAdapter.removeReminder(identifier: duplicate.identifier)
            }
        } catch let error as SystemReminderError {
            throw error
        } catch {
            throw SystemReminderError.eventStore(error.localizedDescription)
        }

        return existingIdentifier == nil ? .created : .updated
    }

    func completeReminder(forTodoID id: UUID) async throws {
        await acquireOperationSlot()
        defer { releaseOperationSlot() }
        try Task.checkCancellation()

        let reminders = try await fetchEasyNoteReminders(
            marker: SystemReminderAgent.marker(for: id)
        )

        do {
            for reminder in reminders {
                try eventStoreAdapter.markReminderCompleted(identifier: reminder.identifier)
            }
        } catch let error as SystemReminderError {
            throw error
        } catch {
            throw SystemReminderError.eventStore(error.localizedDescription)
        }
    }

    func removeReminder(forTodoID id: UUID) async throws {
        await acquireOperationSlot()
        defer { releaseOperationSlot() }
        try Task.checkCancellation()

        let reminders = try await fetchEasyNoteReminders(
            marker: SystemReminderAgent.marker(for: id)
        )

        do {
            for reminder in reminders {
                try eventStoreAdapter.removeReminder(identifier: reminder.identifier)
            }
        } catch let error as SystemReminderError {
            throw error
        } catch {
            throw SystemReminderError.eventStore(error.localizedDescription)
        }
    }

    private func ensureWritable() throws {
        switch eventStoreAdapter.authorizationStatus {
        case .fullAccess:
            return
        case .restricted:
            throw SystemReminderError.restricted
        case .notDetermined, .denied, .unknown:
            throw SystemReminderError.notAuthorized
        }
    }

    private func fetchEasyNoteReminders(marker: String) async throws -> [SystemReminderRecord] {
        try ensureWritable()

        let reminders: [SystemReminderRecord]
        do {
            reminders = try await ReminderCallbackBridge.value(
                timeoutNanoseconds: callbackTimeoutNanoseconds
            ) { [eventStoreAdapter] completion in
                eventStoreAdapter.fetchReminders(completion: completion)
            }
        } catch ReminderCallbackBridgeError.timedOut {
            throw SystemReminderError.timeout
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw SystemReminderError.eventStore(error.localizedDescription)
        }

        return reminders.filter { $0.notes?.contains(marker) == true }
    }

    private func acquireOperationSlot() async {
        guard operationInProgress else {
            operationInProgress = true
            return
        }

        await withCheckedContinuation { continuation in
            operationWaiters.append(continuation)
        }
    }

    private func releaseOperationSlot() {
        guard !operationWaiters.isEmpty else {
            operationInProgress = false
            return
        }

        operationWaiters.removeFirst().resume()
    }
}
