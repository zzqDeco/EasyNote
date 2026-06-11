import Foundation

enum TodoRecurrencePlanner {
    static func nextTodo(afterCompleted item: TodoItem) -> TodoItem? {
        guard item.isCompleted,
              item.isRecurring,
              let intervalString = item.recurringInterval,
              let interval = TodoItem.RecurringInterval(rawValue: intervalString),
              let deadline = item.deadline else {
            return nil
        }

        return TodoItem(
            id: UUID(),
            title: item.title,
            isCompleted: false,
            priority: item.priority,
            deadline: interval.nextDate(from: deadline),
            notes: item.notes,
            isRecurring: true,
            recurringInterval: intervalString
        )
    }
}
