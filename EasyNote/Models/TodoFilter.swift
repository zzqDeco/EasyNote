import Foundation

enum TodoFilter: String, CaseIterable, Identifiable {
    case today = "今天"
    case overdue = "逾期"
    case upcoming = "即将到来"
    case noDate = "无日期"
    case recurring = "重复"
    case completed = "已完成"

    var id: String { rawValue }

    func apply(to items: [TodoItem], calendar: Calendar = .current, now: Date = Date()) -> [TodoItem] {
        let startOfToday = calendar.startOfDay(for: now)
        guard let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday) else {
            return items.filter(matchesWithoutDateBoundary)
        }

        return items.filter { item in
            switch self {
            case .today:
                guard !item.isCompleted, let deadline = item.deadline else { return false }
                return deadline >= startOfToday && deadline < startOfTomorrow
            case .overdue:
                guard !item.isCompleted, let deadline = item.deadline else { return false }
                return deadline < startOfToday
            case .upcoming:
                guard !item.isCompleted, let deadline = item.deadline else { return false }
                return deadline >= startOfTomorrow
            case .noDate:
                return !item.isCompleted && item.deadline == nil
            case .recurring:
                return item.isRecurring
            case .completed:
                return item.isCompleted
            }
        }
    }

    private func matchesWithoutDateBoundary(_ item: TodoItem) -> Bool {
        switch self {
        case .today, .overdue, .upcoming:
            return false
        case .noDate:
            return !item.isCompleted && item.deadline == nil
        case .recurring:
            return item.isRecurring
        case .completed:
            return item.isCompleted
        }
    }
}
