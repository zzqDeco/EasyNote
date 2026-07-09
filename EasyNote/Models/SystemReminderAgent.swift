import Foundation

struct SystemReminderContext {
    let now: Date
    let calendar: Calendar

    static var current: SystemReminderContext {
        SystemReminderContext(now: Date(), calendar: .current)
    }
}

struct SystemReminderProposal: Equatable {
    let todoID: UUID
    let action: SystemReminderAction
    let title: String
    let notes: String?
    let dueDate: Date
    let alarmDate: Date
    let priority: TodoItem.PriorityLevel
    let reason: String
    let confidence: Double
    let marker: String
}

enum SystemReminderAction: Equatable {
    case createOrUpdate
    case skip(SystemReminderSkipReason)
}

enum SystemReminderSkipReason: Equatable {
    case reminderModeDisabled
    case completedTodo
    case missingDeadline
    case deadlineNotFuture
    case emptyTitle
}

enum SystemReminderProposalOperation: Equatable {
    case apply(SystemReminderProposal)
    case complete(UUID)
    case remove(UUID)
    case ignore
}

struct SystemReminderProposalReconciler {
    static func operation(for proposal: SystemReminderProposal) -> SystemReminderProposalOperation {
        switch proposal.action {
        case .createOrUpdate:
            return .apply(proposal)
        case .skip(.completedTodo):
            return .complete(proposal.todoID)
        case .skip(.missingDeadline), .skip(.deadlineNotFuture), .skip(.emptyTitle):
            return .remove(proposal.todoID)
        case .skip(.reminderModeDisabled):
            return .ignore
        }
    }
}

protocol SystemReminderAgentProviding {
    func proposal(
        for todo: TodoItem,
        mode: TodoReminderMode,
        context: SystemReminderContext
    ) -> SystemReminderProposal
}

struct SystemReminderAgent: SystemReminderAgentProviding {
    static let markerPrefix = "EasyNoteTodoID:"

    func proposal(
        for todo: TodoItem,
        mode: TodoReminderMode,
        context: SystemReminderContext = .current
    ) -> SystemReminderProposal {
        let title = todo.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackDate = todo.deadline ?? context.now
        let marker = Self.marker(for: todo.id)

        guard mode == .systemReminderAgent else {
            return skipProposal(
                for: todo,
                title: title,
                dueDate: fallbackDate,
                alarmDate: fallbackDate,
                marker: marker,
                reason: "系统提醒事项模式未开启",
                skipReason: .reminderModeDisabled
            )
        }

        guard !todo.isCompleted else {
            return skipProposal(
                for: todo,
                title: title,
                dueDate: fallbackDate,
                alarmDate: fallbackDate,
                marker: marker,
                reason: "待办已完成，不创建系统提醒",
                skipReason: .completedTodo
            )
        }

        guard !title.isEmpty else {
            return skipProposal(
                for: todo,
                title: title,
                dueDate: fallbackDate,
                alarmDate: fallbackDate,
                marker: marker,
                reason: "待办标题为空，不创建系统提醒",
                skipReason: .emptyTitle
            )
        }

        guard let deadline = todo.deadline else {
            return skipProposal(
                for: todo,
                title: title,
                dueDate: fallbackDate,
                alarmDate: fallbackDate,
                marker: marker,
                reason: "待办没有截止时间，不创建系统提醒",
                skipReason: .missingDeadline
            )
        }

        guard deadline > context.now else {
            return skipProposal(
                for: todo,
                title: title,
                dueDate: deadline,
                alarmDate: deadline,
                marker: marker,
                reason: "截止时间已过，不创建系统提醒",
                skipReason: .deadlineNotFuture
            )
        }

        guard deadline.timeIntervalSince(context.now) >= 60 else {
            return skipProposal(
                for: todo,
                title: title,
                dueDate: deadline,
                alarmDate: deadline,
                marker: marker,
                reason: "截止时间过近，不创建系统提醒",
                skipReason: .deadlineNotFuture
            )
        }

        let decision = reminderDecision(for: todo, deadline: deadline, now: context.now)
        let desiredAlarmDate = deadline.addingTimeInterval(-decision.leadTime)
        let alarmDate: Date

        if desiredAlarmDate > context.now {
            alarmDate = desiredAlarmDate
        } else {
            alarmDate = min(deadline, context.now.addingTimeInterval(60))
        }

        return SystemReminderProposal(
            todoID: todo.id,
            action: .createOrUpdate,
            title: title,
            notes: todo.notes,
            dueDate: deadline,
            alarmDate: alarmDate,
            priority: todo.priority,
            reason: decision.reason,
            confidence: decision.confidence,
            marker: marker
        )
    }

    static func marker(for todoID: UUID) -> String {
        "\(markerPrefix)\(todoID.uuidString)"
    }

    private func skipProposal(
        for todo: TodoItem,
        title: String,
        dueDate: Date,
        alarmDate: Date,
        marker: String,
        reason: String,
        skipReason: SystemReminderSkipReason
    ) -> SystemReminderProposal {
        SystemReminderProposal(
            todoID: todo.id,
            action: .skip(skipReason),
            title: title,
            notes: todo.notes,
            dueDate: dueDate,
            alarmDate: alarmDate,
            priority: todo.priority,
            reason: reason,
            confidence: 1.0,
            marker: marker
        )
    }

    private func reminderDecision(for todo: TodoItem, deadline: Date, now: Date) -> ReminderDecision {
        let text = "\(todo.title) \(todo.notes ?? "")".lowercased()
        let secondsUntilDeadline = deadline.timeIntervalSince(now)

        if containsAny(text, keywords: ["会议", "开会", "面试", "电话", "call", "zoom"]) {
            return ReminderDecision(
                leadTime: 30 * 60,
                reason: "识别为会议/通话类任务，提前 30 分钟提醒",
                confidence: 0.88
            )
        }

        if containsAny(text, keywords: ["出门", "机场", "高铁", "航班", "打车"]) {
            return ReminderDecision(
                leadTime: 2 * 60 * 60,
                reason: "识别为出行类任务，提前 2 小时提醒",
                confidence: 0.9
            )
        }

        if containsAny(text, keywords: ["提交", "交付", "截止", "deadline", "报告", "作业"]) {
            if secondsUntilDeadline > 24 * 60 * 60 {
                return ReminderDecision(
                    leadTime: 24 * 60 * 60,
                    reason: "识别为提交/截止类任务，提前 24 小时提醒",
                    confidence: 0.9
                )
            }

            return ReminderDecision(
                leadTime: 2 * 60 * 60,
                reason: "识别为提交/截止类任务，提前 2 小时提醒",
                confidence: 0.86
            )
        }

        if containsAny(text, keywords: ["准备", "整理", "购买", "带上", "预约"]) {
            return ReminderDecision(
                leadTime: 60 * 60,
                reason: "识别为准备类任务，提前 1 小时提醒",
                confidence: 0.84
            )
        }

        return ReminderDecision(
            leadTime: 15 * 60,
            reason: "按普通待办处理，提前 15 分钟提醒",
            confidence: 0.7
        )
    }

    private func containsAny(_ text: String, keywords: [String]) -> Bool {
        keywords.contains { text.contains($0) }
    }

    private struct ReminderDecision {
        let leadTime: TimeInterval
        let reason: String
        let confidence: Double
    }
}
