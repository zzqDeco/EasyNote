import Foundation

struct TodoDraft: Equatable {
    var title: String
    var priority: TodoItem.PriorityLevel
    var deadline: Date?
    var notes: String
    var isRecurring: Bool
    var recurringInterval: TodoItem.RecurringInterval

    init(
        title: String = "",
        priority: TodoItem.PriorityLevel = .medium,
        deadline: Date? = nil,
        notes: String = "",
        isRecurring: Bool = false,
        recurringInterval: TodoItem.RecurringInterval = .daily
    ) {
        self.title = title
        self.priority = priority
        self.deadline = deadline
        self.notes = notes
        self.isRecurring = isRecurring
        self.recurringInterval = recurringInterval
    }

    init(item: TodoItem) {
        self.init(
            title: item.title,
            priority: item.priority,
            deadline: item.deadline,
            notes: item.notes ?? "",
            isRecurring: item.isRecurring,
            recurringInterval: TodoItem.RecurringInterval.parse(item.recurringInterval) ?? .daily
        )
    }

    var persistedNotes: String? {
        notes.isEmpty ? nil : notes
    }

    var persistedIsRecurring: Bool {
        isRecurring && deadline != nil
    }

    var persistedRecurringInterval: String? {
        persistedIsRecurring ? recurringInterval.rawValue : nil
    }
}
