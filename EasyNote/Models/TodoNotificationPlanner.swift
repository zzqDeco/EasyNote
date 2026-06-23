import Foundation

enum TodoNotificationPlanner {
    static let notificationIdentifierPrefix = "easynote.todo."
    static let maxPendingNotificationRequests = 64

    static func notificationIdentifier(for todoID: UUID) -> String {
        "\(notificationIdentifierPrefix)\(todoID.uuidString)"
    }

    static func shouldScheduleNotification(for todo: TodoItem, now: Date = Date()) -> Bool {
        guard !todo.isCompleted, let deadline = todo.deadline else {
            return false
        }

        return deadline > now
    }

    static func retainedNotificationTodos(
        from todos: [TodoItem],
        now: Date = Date(),
        limit: Int = maxPendingNotificationRequests
    ) -> [TodoItem] {
        guard limit > 0 else { return [] }

        return todos
            .filter { shouldScheduleNotification(for: $0, now: now) }
            .sorted { lhs, rhs in
                let lhsDeadline = lhs.deadline ?? .distantFuture
                let rhsDeadline = rhs.deadline ?? .distantFuture

                if lhsDeadline != rhsDeadline {
                    return lhsDeadline < rhsDeadline
                }

                if lhs.creationDate != rhs.creationDate {
                    return lhs.creationDate < rhs.creationDate
                }

                return lhs.id.uuidString < rhs.id.uuidString
            }
            .prefix(limit)
            .map { $0 }
    }
}
