import Foundation
import SwiftUI
import SwiftData

@Model
final class TodoItem {
    var id: UUID
    var title: String
    var isCompleted: Bool
    var priority: PriorityLevel
    var deadline: Date?
    var notes: String?
    var isRecurring: Bool
    var recurringInterval: String?
    var creationDate: Date

    init(
        id: UUID = UUID(),
        title: String,
        isCompleted: Bool = false,
        priority: PriorityLevel = .medium,
        deadline: Date? = nil,
        notes: String? = nil,
        isRecurring: Bool = false,
        recurringInterval: String? = nil
    ) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.priority = priority
        self.deadline = deadline
        self.notes = notes
        self.isRecurring = isRecurring
        self.recurringInterval = recurringInterval
        self.creationDate = Date()
    }

    enum PriorityLevel: String, Codable, Equatable, Sendable {
        case high, medium, low

        var color: Color {
            switch self {
            case .high: return .red
            case .medium: return .orange
            case .low: return .blue
            }
        }
    }

    // 循环间隔枚举
    enum RecurringInterval: String, Codable, Equatable, Sendable {
        case daily = "每天"
        case weekly = "每周"
        case biweekly = "两周"
        case monthly = "每月"

        static func parse(_ storedValue: String?) -> RecurringInterval? {
            guard let storedValue else { return nil }

            switch storedValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "daily", RecurringInterval.daily.rawValue:
                return .daily
            case "weekly", RecurringInterval.weekly.rawValue:
                return .weekly
            case "biweekly", RecurringInterval.biweekly.rawValue:
                return .biweekly
            case "monthly", RecurringInterval.monthly.rawValue:
                return .monthly
            default:
                return nil
            }
        }

        var displayText: String {
            "\(rawValue)重复"
        }

        // 获取下一个日期
        func nextDate(from date: Date) -> Date {
            let calendar = Calendar.current
            switch self {
            case .daily:
                return calendar.date(byAdding: .day, value: 1, to: date) ?? date
            case .weekly:
                return calendar.date(byAdding: .day, value: 7, to: date) ?? date
            case .biweekly:
                return calendar.date(byAdding: .day, value: 14, to: date) ?? date
            case .monthly:
                return calendar.date(byAdding: .month, value: 1, to: date) ?? date
            }
        }
    }

    var priorityIcon: String {
        switch priority {
        case .high: return "exclamationmark.circle.fill"
        case .medium: return "checkmark.circle.fill"
        case .low: return "circle.fill"
        }
    }
}
