import Combine
import Foundation
import Testing
import UserNotifications
@testable import EasyNote

@Suite("Reminder async services")
struct ReminderServiceAsyncTests {
    @Test func systemReminderFetchTimesOut() async throws {
        let adapter = FakeSystemReminderEventStore()
        adapter.holdFetchCallbacks = true
        let service = SystemReminderService(
            eventStoreAdapter: adapter,
            callbackTimeoutNanoseconds: 20_000_000
        )

        await expectSystemReminderError(.timeout) {
            _ = try await service.applyProposal(makeProposal())
        }
        #expect(adapter.savedReminders.isEmpty)
    }

    @Test func lateEventKitCallbackAfterTimeoutIsIgnored() async throws {
        let adapter = FakeSystemReminderEventStore()
        adapter.holdFetchCallbacks = true
        let service = SystemReminderService(
            eventStoreAdapter: adapter,
            callbackTimeoutNanoseconds: 20_000_000
        )

        await expectSystemReminderError(.timeout) {
            _ = try await service.applyProposal(makeProposal())
        }

        adapter.completeNextFetch(.success([]))
        try await Task.sleep(nanoseconds: 5_000_000)
        #expect(adapter.savedReminders.isEmpty)
    }

    @Test func reminderAuthorizationCallbackTimesOutAndIgnoresLateGrant() async throws {
        let adapter = FakeSystemReminderEventStore()
        adapter.holdAuthorizationCallbacks = true
        let service = SystemReminderService(
            eventStoreAdapter: adapter,
            authorizationTimeoutNanoseconds: 20_000_000
        )

        await expectSystemReminderError(.timeout) {
            try await service.requestAuthorization()
        }

        adapter.completeNextAuthorization(.success(true))
        try await Task.sleep(nanoseconds: 5_000_000)
        #expect(adapter.pendingAuthorizationCount == 0)
    }

    @Test func cancelingEventKitFetchIgnoresLaterCallback() async throws {
        let adapter = FakeSystemReminderEventStore()
        adapter.holdFetchCallbacks = true
        let service = SystemReminderService(
            eventStoreAdapter: adapter,
            callbackTimeoutNanoseconds: 1_000_000_000
        )
        let task = Task {
            try await service.applyProposal(makeProposal())
        }

        await waitUntil { adapter.pendingFetchCount == 1 }
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        } catch {
            Issue.record("Expected CancellationError, got \(error)")
        }

        adapter.completeNextFetch(.success([]))
        try await Task.sleep(nanoseconds: 5_000_000)
        #expect(adapter.savedReminders.isEmpty)
    }

    @Test func eventKitSystemFailureIsMappedSeparately() async throws {
        let adapter = FakeSystemReminderEventStore()
        adapter.fetchResult = .failure(FakeReminderError.eventStoreUnavailable)
        let service = SystemReminderService(eventStoreAdapter: adapter)

        do {
            _ = try await service.applyProposal(makeProposal())
            Issue.record("Expected EventKit failure")
        } catch let error as SystemReminderError {
            guard case .eventStore(let message) = error else {
                Issue.record("Expected eventStore error, got \(error)")
                return
            }
            #expect(message.contains("eventStoreUnavailable"))
        }
    }

    @Test func eventKitSaveFailureIsMappedSeparately() async throws {
        let adapter = FakeSystemReminderEventStore()
        adapter.saveError = FakeReminderError.eventStoreUnavailable
        let service = SystemReminderService(eventStoreAdapter: adapter)

        do {
            _ = try await service.applyProposal(makeProposal())
            Issue.record("Expected EventKit save failure")
        } catch let error as SystemReminderError {
            guard case .eventStore(let message) = error else {
                Issue.record("Expected eventStore error, got \(error)")
                return
            }
            #expect(message.contains("eventStoreUnavailable"))
        }
    }

    @Test func applyingProposalUpdatesFirstMarkerAndRemovesDuplicates() async throws {
        let todoID = UUID()
        let proposal = makeProposal(todoID: todoID)
        let adapter = FakeSystemReminderEventStore()
        adapter.fetchResult = .success([
            SystemReminderRecord(identifier: "first", notes: proposal.marker),
            SystemReminderRecord(identifier: "duplicate", notes: "note\n\(proposal.marker)"),
            SystemReminderRecord(identifier: "other", notes: "EasyNoteTodoID:\(UUID())")
        ])
        let service = SystemReminderService(eventStoreAdapter: adapter)

        let result = try await service.applyProposal(proposal)

        #expect(result == .updated)
        #expect(adapter.savedReminders.count == 1)
        #expect(adapter.savedReminders.first?.existingIdentifier == "first")
        #expect(adapter.removedIdentifiers == ["duplicate"])
    }

    @Test func applyingProposalFailsWhenDefaultListIsMissing() async throws {
        let adapter = FakeSystemReminderEventStore()
        adapter.defaultCalendarIdentifierValue = nil
        let service = SystemReminderService(eventStoreAdapter: adapter)

        await expectSystemReminderError(.missingDefaultReminderList) {
            _ = try await service.applyProposal(makeProposal())
        }
        #expect(adapter.pendingFetchCount == 0)
    }

    @Test func reminderAuthorizationDeniedAndRestrictedRemainDistinct() async throws {
        let deniedAdapter = FakeSystemReminderEventStore()
        deniedAdapter.authorizationStatus = .denied
        let deniedService = SystemReminderService(eventStoreAdapter: deniedAdapter)
        await expectSystemReminderError(.notAuthorized) {
            _ = try await deniedService.applyProposal(makeProposal())
        }

        let restrictedAdapter = FakeSystemReminderEventStore()
        restrictedAdapter.authorizationStatus = .restricted
        let restrictedService = SystemReminderService(eventStoreAdapter: restrictedAdapter)
        await expectSystemReminderError(.restricted) {
            _ = try await restrictedService.applyProposal(makeProposal())
        }
    }

    @Test func localNotificationAddFailureIsSurfaced() async throws {
        let suiteName = "ReminderServiceAsyncTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: LocalTodoNotificationService.enabledDefaultsKey)

        let adapter = FakeUserNotificationCenter()
        adapter.addError = FakeReminderError.notificationAddFailed
        let service = LocalTodoNotificationService(
            notificationCenterAdapter: adapter,
            defaults: defaults
        )
        let todo = TodoItem(
            title: "需要提醒",
            deadline: Date().addingTimeInterval(3600)
        )

        do {
            try await service.synchronizeNotification(for: todo)
            Issue.record("Expected notification scheduling failure")
        } catch let error as TodoNotificationError {
            guard case .schedulingFailed(let message) = error else {
                Issue.record("Expected schedulingFailed, got \(error)")
                return
            }
            #expect(message.contains("notificationAddFailed"))
        }
        #expect(adapter.addedRequests.count == 1)
    }

    @Test func concurrentLocalNotificationUpdatesKeepNewestRequest() async throws {
        let suiteName = "ReminderServiceAsyncTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: LocalTodoNotificationService.enabledDefaultsKey)

        let todoID = UUID()
        let adapter = FakeUserNotificationCenter()
        adapter.holdAddRequests = true
        let service = LocalTodoNotificationService(
            notificationCenterAdapter: adapter,
            defaults: defaults
        )
        let olderTodo = TodoItem(
            id: todoID,
            title: "旧截止时间",
            deadline: Date().addingTimeInterval(1800)
        )
        let newerTodo = TodoItem(
            id: todoID,
            title: "新截止时间",
            deadline: Date().addingTimeInterval(3600)
        )

        let olderTask = Task { try await service.synchronizeNotification(for: olderTodo) }
        await waitUntil { adapter.pendingAddCount == 1 }
        let newerTask = Task { try await service.synchronizeNotification(for: newerTodo) }

        adapter.completeNextAdd()
        await waitUntil { adapter.pendingAddCount == 1 }
        adapter.completeNextAdd()

        try await olderTask.value
        try await newerTask.value
        #expect(adapter.activeRequestTitle(forTodoID: todoID) == "新截止时间")
    }

    @Test func externalSystemReminderGrantTriggersSyncOnlyForSystemMode() {
        #expect(ReminderAuthorizationTransitionPlanner.shouldSyncSystemReminders(
            mode: .systemReminderAgent,
            previousStatus: .denied,
            currentStatus: .fullAccess
        ))
        #expect(!ReminderAuthorizationTransitionPlanner.shouldSyncSystemReminders(
            mode: .systemReminderAgent,
            previousStatus: .fullAccess,
            currentStatus: .fullAccess
        ))
        #expect(!ReminderAuthorizationTransitionPlanner.shouldSyncSystemReminders(
            mode: .localNotification,
            previousStatus: .denied,
            currentStatus: .fullAccess
        ))
    }

    private func makeProposal(todoID: UUID = UUID()) -> SystemReminderProposal {
        let dueDate = Date().addingTimeInterval(3600)
        return SystemReminderProposal(
            todoID: todoID,
            action: .createOrUpdate,
            title: "提交报告",
            notes: "测试",
            dueDate: dueDate,
            alarmDate: dueDate.addingTimeInterval(-900),
            priority: .high,
            reason: "默认提前 15 分钟提醒",
            confidence: 1,
            marker: SystemReminderAgent.marker(for: todoID)
        )
    }

    private func expectSystemReminderError(
        _ expected: SystemReminderError,
        operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            Issue.record("Expected \(expected)")
        } catch let error as SystemReminderError {
            #expect(error == expected)
        } catch {
            Issue.record("Expected SystemReminderError, got \(error)")
        }
    }

    private func waitUntil(
        attempts: Int = 2_000,
        condition: () -> Bool
    ) async {
        for _ in 0..<attempts {
            if condition() {
                return
            }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        Issue.record("Condition was not satisfied")
    }
}

private enum FakeReminderError: LocalizedError {
    case eventStoreUnavailable
    case notificationAddFailed

    var errorDescription: String? {
        switch self {
        case .eventStoreUnavailable:
            return "eventStoreUnavailable"
        case .notificationAddFailed:
            return "notificationAddFailed"
        }
    }
}

private final class FakeSystemReminderEventStore: SystemReminderEventStoreProviding, @unchecked Sendable {
    struct SavedReminder {
        let proposal: SystemReminderProposal
        let existingIdentifier: String?
        let calendarIdentifier: String
    }

    var authorizationStatus: SystemReminderAuthorizationStatus = .fullAccess
    var defaultCalendarIdentifierValue: String? = "default"
    var fetchResult: Result<[SystemReminderRecord], Error> = .success([])
    var requestAuthorizationResult: Result<Bool, Error> = .success(true)
    var holdFetchCallbacks = false
    var holdAuthorizationCallbacks = false
    var saveError: Error?
    var completionError: Error?
    var removalError: Error?
    private(set) var savedReminders: [SavedReminder] = []
    private(set) var completedIdentifiers: [String] = []
    private(set) var removedIdentifiers: [String] = []
    private var pendingFetchCallbacks: [@Sendable (Result<[SystemReminderRecord], Error>) -> Void] = []
    private var pendingAuthorizationCallbacks: [@Sendable (Result<Bool, Error>) -> Void] = []

    var pendingFetchCount: Int {
        pendingFetchCallbacks.count
    }

    var pendingAuthorizationCount: Int {
        pendingAuthorizationCallbacks.count
    }

    func requestFullAccessToReminders(
        completion: @escaping @Sendable (Result<Bool, Error>) -> Void
    ) {
        if holdAuthorizationCallbacks {
            pendingAuthorizationCallbacks.append(completion)
        } else {
            completion(requestAuthorizationResult)
        }
    }

    func defaultCalendarIdentifier() -> String? {
        defaultCalendarIdentifierValue
    }

    func fetchReminders(
        completion: @escaping @Sendable (Result<[SystemReminderRecord], Error>) -> Void
    ) {
        if holdFetchCallbacks {
            pendingFetchCallbacks.append(completion)
        } else {
            completion(fetchResult)
        }
    }

    func saveReminder(
        proposal: SystemReminderProposal,
        existingIdentifier: String?,
        calendarIdentifier: String
    ) throws {
        savedReminders.append(SavedReminder(
            proposal: proposal,
            existingIdentifier: existingIdentifier,
            calendarIdentifier: calendarIdentifier
        ))
        if let saveError {
            throw saveError
        }
    }

    func markReminderCompleted(identifier: String) throws {
        completedIdentifiers.append(identifier)
        if let completionError {
            throw completionError
        }
    }

    func removeReminder(identifier: String) throws {
        removedIdentifiers.append(identifier)
        if let removalError {
            throw removalError
        }
    }

    func completeNextFetch(_ result: Result<[SystemReminderRecord], Error>) {
        guard !pendingFetchCallbacks.isEmpty else {
            return
        }
        let completion = pendingFetchCallbacks.removeFirst()
        completion(result)
    }

    func completeNextAuthorization(_ result: Result<Bool, Error>) {
        guard !pendingAuthorizationCallbacks.isEmpty else {
            return
        }
        let completion = pendingAuthorizationCallbacks.removeFirst()
        completion(result)
    }
}

private final class FakeUserNotificationCenter: UserNotificationCenterProviding, @unchecked Sendable {
    var status: TodoNotificationAuthorizationStatus = .authorized
    var authorizationResult = true
    var authorizationError: Error?
    var addError: Error?
    var holdAddRequests = false
    var pendingRequests: [UNNotificationRequest] = []
    var delivered: [UNNotification] = []
    private(set) var addedRequests: [UNNotificationRequest] = []
    private(set) var removedPendingIdentifiers: [[String]] = []
    private(set) var removedDeliveredIdentifiers: [[String]] = []
    private let addStateLock = NSLock()
    private var pendingAddContinuations: [CheckedContinuation<Void, Never>] = []
    private var activeRequests: [String: UNNotificationRequest] = [:]

    var pendingAddCount: Int {
        addStateLock.lock()
        defer { addStateLock.unlock() }
        return pendingAddContinuations.count
    }

    func setDelegate(_ delegate: (any UNUserNotificationCenterDelegate)?) {}

    func authorizationStatus() async -> TodoNotificationAuthorizationStatus {
        status
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        if let authorizationError {
            throw authorizationError
        }
        return authorizationResult
    }

    func add(_ request: UNNotificationRequest) async throws {
        let shouldHold = recordAddStart(request)
        if shouldHold {
            await withCheckedContinuation { continuation in
                enqueueAddContinuation(continuation)
            }
        }

        if let error = finishAdd(request) {
            throw error
        }
    }

    func pendingNotificationRequests() async -> [UNNotificationRequest] {
        pendingRequests
    }

    func deliveredNotifications() async -> [UNNotification] {
        delivered
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        addStateLock.lock()
        removedPendingIdentifiers.append(identifiers)
        identifiers.forEach { activeRequests[$0] = nil }
        addStateLock.unlock()
    }

    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
        removedDeliveredIdentifiers.append(identifiers)
    }

    func completeNextAdd() {
        addStateLock.lock()
        let continuation = pendingAddContinuations.isEmpty ? nil : pendingAddContinuations.removeFirst()
        addStateLock.unlock()
        continuation?.resume()
    }

    func activeRequestTitle(forTodoID id: UUID) -> String? {
        let identifier = TodoNotificationPlanner.notificationIdentifier(for: id)
        addStateLock.lock()
        defer { addStateLock.unlock() }
        return activeRequests[identifier]?.content.title
    }

    private func recordAddStart(_ request: UNNotificationRequest) -> Bool {
        addStateLock.lock()
        defer { addStateLock.unlock() }
        addedRequests.append(request)
        return holdAddRequests
    }

    private func enqueueAddContinuation(_ continuation: CheckedContinuation<Void, Never>) {
        addStateLock.lock()
        pendingAddContinuations.append(continuation)
        addStateLock.unlock()
    }

    private func finishAdd(_ request: UNNotificationRequest) -> Error? {
        addStateLock.lock()
        defer { addStateLock.unlock() }
        guard addError == nil else { return addError }
        activeRequests[request.identifier] = request
        return nil
    }
}
