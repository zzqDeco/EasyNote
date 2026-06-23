import Foundation

enum TodoNotificationPlanner {
    static let notificationIdentifierPrefix = "easynote.todo."

    static func notificationIdentifier(for todoID: UUID) -> String {
        "\(notificationIdentifierPrefix)\(todoID.uuidString)"
    }

    static func shouldScheduleNotification(for todo: TodoItem, now: Date = Date()) -> Bool {
        guard !todo.isCompleted, let deadline = todo.deadline else {
            return false
        }

        return deadline > now
    }
}
