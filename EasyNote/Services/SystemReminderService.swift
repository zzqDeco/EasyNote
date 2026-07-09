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
    case missingDefaultReminderList
    case eventStore(String)

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "未授予提醒事项权限"
        case .restricted:
            return "系统限制了提醒事项访问"
        case .missingDefaultReminderList:
            return "没有可用的默认提醒事项列表"
        case .eventStore(let message):
            return message
        }
    }
}

final class SystemReminderService: SystemReminderWritingProviding {
    static let shared = SystemReminderService()

    private let eventStore: EKEventStore
    private let reminderQueue = DispatchQueue(label: "EasyNote.SystemReminders")
    private let authorizationStatusSubject = CurrentValueSubject<SystemReminderAuthorizationStatus, Never>(.notDetermined)

    var authorizationStatusPublisher: AnyPublisher<SystemReminderAuthorizationStatus, Never> {
        authorizationStatusSubject.eraseToAnyPublisher()
    }

    init(eventStore: EKEventStore = EKEventStore()) {
        self.eventStore = eventStore
        refreshAuthorizationStatus()
    }

    func refreshAuthorizationStatus() {
        let status = Self.mapAuthorizationStatus(EKEventStore.authorizationStatus(for: .reminder))
        DispatchQueue.main.async { [authorizationStatusSubject] in
            authorizationStatusSubject.send(status)
        }
    }

    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        eventStore.requestFullAccessToReminders { [weak self] granted, _ in
            self?.refreshAuthorizationStatus()
            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }

    func applyProposal(
        _ proposal: SystemReminderProposal,
        completion: @escaping (Result<SystemReminderWriteResult, SystemReminderError>) -> Void
    ) {
        guard proposal.action == .createOrUpdate else {
            DispatchQueue.main.async {
                completion(.success(.skipped))
            }
            return
        }

        reminderQueue.async { [weak self] in
            guard let self else { return }
            let result = self.applyCreateOrUpdateProposal(proposal)
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    func completeReminder(
        forTodoID id: UUID,
        completion: ((Result<Void, SystemReminderError>) -> Void)? = nil
    ) {
        reminderQueue.async { [weak self] in
            guard let self else { return }
            let result: Result<Void, SystemReminderError>

            do {
                let reminders = try self.fetchEasyNoteReminders(forTodoID: id)
                guard let reminder = reminders.first else {
                    result = .success(())
                    DispatchQueue.main.async { completion?(result) }
                    return
                }

                reminder.isCompleted = true
                try self.eventStore.save(reminder, commit: true)
                result = .success(())
            } catch let error as SystemReminderError {
                result = .failure(error)
            } catch {
                result = .failure(.eventStore(error.localizedDescription))
            }

            DispatchQueue.main.async {
                completion?(result)
            }
        }
    }

    func removeReminder(
        forTodoID id: UUID,
        completion: ((Result<Void, SystemReminderError>) -> Void)? = nil
    ) {
        reminderQueue.async { [weak self] in
            guard let self else { return }
            let result: Result<Void, SystemReminderError>

            do {
                let reminders = try self.fetchEasyNoteReminders(forTodoID: id)
                for reminder in reminders {
                    try self.eventStore.remove(reminder, commit: true)
                }
                result = .success(())
            } catch let error as SystemReminderError {
                result = .failure(error)
            } catch {
                result = .failure(.eventStore(error.localizedDescription))
            }

            DispatchQueue.main.async {
                completion?(result)
            }
        }
    }

    private func applyCreateOrUpdateProposal(
        _ proposal: SystemReminderProposal
    ) -> Result<SystemReminderWriteResult, SystemReminderError> {
        do {
            try ensureWritable()
            guard let calendar = eventStore.defaultCalendarForNewReminders() else {
                return .failure(.missingDefaultReminderList)
            }

            var matchingReminders = try fetchEasyNoteReminders(marker: proposal.marker)
            let reminder: EKReminder
            let writeResult: SystemReminderWriteResult

            if let existing = matchingReminders.first {
                reminder = existing
                matchingReminders.removeFirst()
                writeResult = .updated
            } else {
                reminder = EKReminder(eventStore: eventStore)
                writeResult = .created
            }

            reminder.calendar = calendar
            reminder.title = proposal.title
            reminder.notes = notesWithMarker(notes: proposal.notes, marker: proposal.marker)
            reminder.dueDateComponents = dateComponents(for: proposal.dueDate)
            reminder.priority = priorityValue(for: proposal.priority)
            reminder.alarms?.forEach { reminder.removeAlarm($0) }
            reminder.addAlarm(EKAlarm(absoluteDate: proposal.alarmDate))

            try eventStore.save(reminder, commit: true)

            for duplicate in matchingReminders {
                try eventStore.remove(duplicate, commit: true)
            }

            return .success(writeResult)
        } catch let error as SystemReminderError {
            return .failure(error)
        } catch {
            return .failure(.eventStore(error.localizedDescription))
        }
    }

    private func ensureWritable() throws {
        let status = Self.mapAuthorizationStatus(EKEventStore.authorizationStatus(for: .reminder))
        DispatchQueue.main.async { [authorizationStatusSubject] in
            authorizationStatusSubject.send(status)
        }

        switch status {
        case .fullAccess:
            return
        case .restricted:
            throw SystemReminderError.restricted
        case .notDetermined, .denied, .unknown:
            throw SystemReminderError.notAuthorized
        }
    }

    private func fetchEasyNoteReminders(forTodoID id: UUID) throws -> [EKReminder] {
        try fetchEasyNoteReminders(marker: SystemReminderAgent.marker(for: id))
    }

    private func fetchEasyNoteReminders(marker: String) throws -> [EKReminder] {
        try ensureWritable()

        return try fetchAllReminders().filter { reminder in
            reminder.notes?.contains(marker) == true
        }
    }

    private func fetchAllReminders() throws -> [EKReminder] {
        let predicate = eventStore.predicateForReminders(in: nil)

        let semaphore = DispatchSemaphore(value: 0)
        var fetchedReminders: [EKReminder] = []

        eventStore.fetchReminders(matching: predicate) { reminders in
            fetchedReminders = reminders ?? []
            semaphore.signal()
        }

        semaphore.wait()
        return fetchedReminders
    }

    private func dateComponents(for date: Date) -> DateComponents {
        var components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        components.timeZone = Calendar.current.timeZone
        return components
    }

    private func notesWithMarker(notes: String?, marker: String) -> String {
        let trimmedNotes = notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmedNotes.isEmpty {
            return marker
        }

        return "\(trimmedNotes)\n\n\(marker)"
    }

    private func priorityValue(for priority: TodoItem.PriorityLevel) -> Int {
        switch priority {
        case .high:
            return 1
        case .medium:
            return 5
        case .low:
            return 9
        }
    }

    private static func mapAuthorizationStatus(_ status: EKAuthorizationStatus) -> SystemReminderAuthorizationStatus {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .restricted:
            return .restricted
        case .denied:
            return .denied
        case .authorized, .fullAccess:
            return .fullAccess
        case .writeOnly:
            return .fullAccess
        @unknown default:
            return .unknown
        }
    }
}
