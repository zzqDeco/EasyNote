//
//  EasyNoteTests.swift
//  EasyNoteTests
//
//  Created by 赵子谦 on 2025/3/1.
//

import Testing
import Foundation
import Combine
import SwiftData
import UIKit
@testable import EasyNote

struct EasyNoteTests {

    @Test func recurringIntervalsComputeExpectedNextDates() async throws {
        let calendar = Calendar.current
        let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 10, hour: 9)))
        
        #expect(TodoItem.RecurringInterval.daily.nextDate(from: start) == calendar.date(byAdding: .day, value: 1, to: start))
        #expect(TodoItem.RecurringInterval.weekly.nextDate(from: start) == calendar.date(byAdding: .day, value: 7, to: start))
        #expect(TodoItem.RecurringInterval.biweekly.nextDate(from: start) == calendar.date(byAdding: .day, value: 14, to: start))
        #expect(TodoItem.RecurringInterval.monthly.nextDate(from: start) == calendar.date(byAdding: .month, value: 1, to: start))
    }

    @Test func recurrenceParserSupportsLegacyAndCurrentStoredValues() async throws {
        #expect(TodoItem.RecurringInterval.parse("daily")?.displayText == "每天重复")
        #expect(TodoItem.RecurringInterval.parse("每天")?.displayText == "每天重复")
        #expect(TodoItem.RecurringInterval.parse("weekly") == .weekly)
        #expect(TodoItem.RecurringInterval.parse("每周") == .weekly)
        #expect(TodoItem.RecurringInterval.parse("biweekly")?.displayText == "两周重复")
        #expect(TodoItem.RecurringInterval.parse("每月")?.displayText == "每月重复")
        #expect(TodoItem.RecurringInterval.parse("unknown") == nil)
    }

    @MainActor
    @Test func cancelingTodoDraftCreatesNoData() async throws {
        let context = try makeModelContext()
        let viewModel = TodoViewModel(
            modelContext: context,
            notificationScheduler: FakeTodoNotificationScheduler(),
            systemReminderWriter: FakeSystemReminderWriter(),
            reminderModeStore: FakeTodoReminderModeStore(mode: .off)
        )
        var draft = TodoDraft()

        draft.title = "尚未确认的待办"
        draft.notes = "取消时也不应插入"

        #expect(viewModel.todoItems.isEmpty)
        #expect(try context.fetch(FetchDescriptor<TodoItem>()).isEmpty)
    }

    @MainActor
    @Test func creatingTodoDraftWithoutDeadlineClearsStaleRecurrence() async throws {
        let context = try makeModelContext()
        let viewModel = TodoViewModel(
            modelContext: context,
            notificationScheduler: FakeTodoNotificationScheduler(),
            systemReminderWriter: FakeSystemReminderWriter(),
            reminderModeStore: FakeTodoReminderModeStore(mode: .off)
        )
        var draft = TodoDraft(
            title: "取消截止日期后的待办",
            deadline: Date().addingTimeInterval(3600),
            isRecurring: true,
            recurringInterval: .weekly
        )

        draft.deadline = nil

        #expect(viewModel.addTodoItem(from: draft))
        let persistedTodo = try #require(context.fetch(FetchDescriptor<TodoItem>()).first)
        #expect(persistedTodo.deadline == nil)
        #expect(!persistedTodo.isRecurring)
        #expect(persistedTodo.recurringInterval == nil)
    }

    @Test func persistenceFailureFeedbackKeepsSaveAndDeleteScreensPresented() async throws {
        let saveFeedback = PersistenceFeedback.resolve(
            succeeded: false,
            viewModelError: "保存失败",
            fallbackError: "无法保存"
        )
        let deleteFeedback = PersistenceFeedback.resolve(
            succeeded: false,
            viewModelError: nil,
            fallbackError: "无法删除"
        )
        let successFeedback = PersistenceFeedback.resolve(
            succeeded: true,
            viewModelError: "旧错误",
            fallbackError: "不会显示"
        )

        #expect(!saveFeedback.shouldDismiss)
        #expect(saveFeedback.errorMessage == "保存失败")
        #expect(!deleteFeedback.shouldDismiss)
        #expect(deleteFeedback.errorMessage == "无法删除")
        #expect(successFeedback.shouldDismiss)
        #expect(successFeedback.errorMessage == nil)
    }

    @Test func keyboardObserverRegistrationDoesNotDuplicate() async throws {
        let observer = KeyboardObserver(notificationCenter: NotificationCenter())

        observer.start()
        #expect(observer.registrationCount == 2)

        observer.start()
        #expect(observer.registrationCount == 2)

        observer.stop()
        #expect(observer.registrationCount == 0)
    }

    @Test func recurrencePlannerCreatesNextTodoForCompletedRecurringItem() async throws {
        let calendar = Calendar.current
        let deadline = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 10, hour: 9)))
        let item = TodoItem(
            title: "晨间复盘",
            isCompleted: true,
            priority: .high,
            deadline: deadline,
            notes: "保持节奏",
            isRecurring: true,
            recurringInterval: TodoItem.RecurringInterval.daily.rawValue
        )

        let nextTodo = try #require(TodoRecurrencePlanner.nextTodo(afterCompleted: item))

        #expect(nextTodo.id != item.id)
        #expect(nextTodo.title == item.title)
        #expect(nextTodo.isCompleted == false)
        #expect(nextTodo.priority == item.priority)
        #expect(nextTodo.deadline == calendar.date(byAdding: .day, value: 1, to: deadline))
        #expect(nextTodo.notes == item.notes)
        #expect(nextTodo.isRecurring)
        #expect(nextTodo.recurringInterval == item.recurringInterval)
    }

    @Test func recurrencePlannerSkipsNonRecurringTodo() async throws {
        let item = TodoItem(title: "一次性任务", isCompleted: true, isRecurring: false)

        #expect(TodoRecurrencePlanner.nextTodo(afterCompleted: item) == nil)
    }

    @Test func recurrencePlannerSkipsRecurringTodoWithoutDeadline() async throws {
        let item = TodoItem(
            title: "缺少截止日期",
            isCompleted: true,
            isRecurring: true,
            recurringInterval: TodoItem.RecurringInterval.weekly.rawValue
        )

        #expect(TodoRecurrencePlanner.nextTodo(afterCompleted: item) == nil)
    }

    @Test func recurrencePlannerSkipsRecurringTodoWithInvalidInterval() async throws {
        let item = TodoItem(
            title: "无效周期",
            isCompleted: true,
            deadline: Date(),
            isRecurring: true,
            recurringInterval: "每十天"
        )

        #expect(TodoRecurrencePlanner.nextTodo(afterCompleted: item) == nil)
    }

    @Test func todoFilterProjectsFocusedCategories() async throws {
        let calendar = Calendar.current
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 11, hour: 12)))
        let yesterday = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 10, hour: 18)))
        let today = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 11, hour: 9)))
        let tomorrow = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 12, hour: 9)))
        let items = [
            makeTodo(title: "今天", deadline: today),
            makeTodo(title: "逾期", deadline: yesterday),
            makeTodo(title: "即将到来", deadline: tomorrow),
            makeTodo(title: "无日期"),
            makeTodo(title: "已完成今天", isCompleted: true, deadline: today),
            makeTodo(title: "已完成无日期", isCompleted: true),
            makeTodo(title: "重复", deadline: tomorrow, isRecurring: true, recurringInterval: TodoItem.RecurringInterval.weekly.rawValue)
        ]

        #expect(TodoFilter.today.apply(to: items, calendar: calendar, now: now).map(\.title) == ["今天"])
        #expect(TodoFilter.overdue.apply(to: items, calendar: calendar, now: now).map(\.title) == ["逾期"])
        #expect(TodoFilter.upcoming.apply(to: items, calendar: calendar, now: now).map(\.title) == ["即将到来", "重复"])
        #expect(TodoFilter.noDate.apply(to: items, calendar: calendar, now: now).map(\.title) == ["无日期"])
        #expect(TodoFilter.recurring.apply(to: items, calendar: calendar, now: now).map(\.title) == ["重复"])
        #expect(TodoFilter.completed.apply(to: items, calendar: calendar, now: now).map(\.title) == ["已完成今天", "已完成无日期"])
    }

    @Test func todoFilterExcludesCompletedItemsFromOpenDateGroups() async throws {
        let calendar = Calendar.current
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 11, hour: 12)))
        let yesterday = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 10, hour: 18)))
        let today = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 11, hour: 9)))
        let tomorrow = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 12, hour: 9)))
        let completedItems = [
            makeTodo(title: "完成逾期", isCompleted: true, deadline: yesterday),
            makeTodo(title: "完成今天", isCompleted: true, deadline: today),
            makeTodo(title: "完成即将到来", isCompleted: true, deadline: tomorrow),
            makeTodo(title: "完成无日期", isCompleted: true)
        ]

        #expect(TodoFilter.today.apply(to: completedItems, calendar: calendar, now: now).isEmpty)
        #expect(TodoFilter.overdue.apply(to: completedItems, calendar: calendar, now: now).isEmpty)
        #expect(TodoFilter.upcoming.apply(to: completedItems, calendar: calendar, now: now).isEmpty)
        #expect(TodoFilter.noDate.apply(to: completedItems, calendar: calendar, now: now).isEmpty)
        #expect(TodoFilter.completed.apply(to: completedItems, calendar: calendar, now: now).count == completedItems.count)
    }

    @Test func todoFilterIncludesNextRecurringTodoFromPlanner() async throws {
        let calendar = Calendar.current
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 11, hour: 12)))
        let deadline = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 11, hour: 9)))
        let completedRecurring = makeTodo(
            title: "循环任务",
            isCompleted: true,
            deadline: deadline,
            isRecurring: true,
            recurringInterval: TodoItem.RecurringInterval.daily.rawValue
        )

        let nextTodo = try #require(TodoRecurrencePlanner.nextTodo(afterCompleted: completedRecurring))

        #expect(nextTodo.isCompleted == false)
        #expect(TodoFilter.recurring.apply(to: [nextTodo], calendar: calendar, now: now).map(\.title) == ["循环任务"])
        #expect(TodoFilter.completed.apply(to: [nextTodo], calendar: calendar, now: now).isEmpty)
    }

    @Test func todoNotificationPlannerSchedulesFutureIncompleteTodo() async throws {
        let calendar = Calendar.current
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 11, hour: 12)))
        let deadline = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 11, hour: 13)))
        let todo = makeTodo(title: "提醒我", deadline: deadline)

        #expect(TodoNotificationPlanner.shouldScheduleNotification(for: todo, now: now))
        #expect(TodoNotificationPlanner.notificationIdentifier(for: todo.id) == "easynote.todo.\(todo.id.uuidString)")
    }

    @Test func todoNotificationPlannerSkipsIneligibleTodos() async throws {
        let calendar = Calendar.current
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 11, hour: 12)))
        let past = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 11, hour: 11)))
        let future = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 11, hour: 13)))

        #expect(!TodoNotificationPlanner.shouldScheduleNotification(for: makeTodo(title: "无截止时间"), now: now))
        #expect(!TodoNotificationPlanner.shouldScheduleNotification(for: makeTodo(title: "已完成", isCompleted: true, deadline: future), now: now))
        #expect(!TodoNotificationPlanner.shouldScheduleNotification(for: makeTodo(title: "已过期", deadline: past), now: now))
    }

    @Test func todoNotificationPlannerRetainsNearestPendingSlots() async throws {
        let calendar = Calendar.current
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 11, hour: 12)))
        let futureTodos = try (0..<70).reversed().map { offset in
            let deadline = try #require(calendar.date(byAdding: .minute, value: offset + 1, to: now))
            return makeTodo(title: "提醒 \(offset)", deadline: deadline)
        }
        let ineligibleTodos = [
            makeTodo(title: "无截止时间"),
            makeTodo(title: "已完成", isCompleted: true, deadline: calendar.date(byAdding: .minute, value: 1, to: now)),
            makeTodo(title: "已过期", deadline: calendar.date(byAdding: .minute, value: -1, to: now))
        ]

        let retained = TodoNotificationPlanner.retainedNotificationTodos(
            from: futureTodos + ineligibleTodos,
            now: now
        )

        #expect(retained.count == TodoNotificationPlanner.maxPendingNotificationRequests)
        #expect(Array(retained.map(\.title).prefix(3)) == ["提醒 0", "提醒 1", "提醒 2"])
        #expect(Array(retained.map(\.title).suffix(3)) == ["提醒 61", "提醒 62", "提醒 63"])
        #expect(!retained.map(\.title).contains("提醒 64"))
        #expect(!retained.map(\.title).contains("无截止时间"))
        #expect(!retained.map(\.title).contains("已完成"))
        #expect(!retained.map(\.title).contains("已过期"))
    }

    @Test func systemReminderAgentSkipsCompletedTodo() async throws {
        let calendar = makeGregorianCalendar()
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 11, hour: 12)))
        let deadline = try #require(calendar.date(byAdding: .hour, value: 1, to: now))
        let todo = makeTodo(title: "已完成", isCompleted: true, deadline: deadline)

        let proposal = SystemReminderAgent().proposal(
            for: todo,
            mode: .systemReminderAgent,
            context: SystemReminderContext(now: now, calendar: calendar)
        )

        #expect(proposal.action == .skip(.completedTodo))
    }

    @Test func systemReminderAgentSkipsMissingDeadline() async throws {
        let calendar = makeGregorianCalendar()
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 11, hour: 12)))
        let todo = makeTodo(title: "无截止时间")

        let proposal = SystemReminderAgent().proposal(
            for: todo,
            mode: .systemReminderAgent,
            context: SystemReminderContext(now: now, calendar: calendar)
        )

        #expect(proposal.action == .skip(.missingDeadline))
    }

    @Test func systemReminderAgentSkipsPastDeadline() async throws {
        let calendar = makeGregorianCalendar()
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 11, hour: 12)))
        let deadline = try #require(calendar.date(byAdding: .minute, value: -5, to: now))
        let todo = makeTodo(title: "已过期", deadline: deadline)

        let proposal = SystemReminderAgent().proposal(
            for: todo,
            mode: .systemReminderAgent,
            context: SystemReminderContext(now: now, calendar: calendar)
        )

        #expect(proposal.action == .skip(.deadlineNotFuture))
    }

    @Test func systemReminderAgentUsesMeetingLeadTime() async throws {
        let calendar = makeGregorianCalendar()
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 11, hour: 12)))
        let deadline = try #require(calendar.date(byAdding: .hour, value: 3, to: now))
        let todo = makeTodo(title: "项目会议", deadline: deadline)

        let proposal = SystemReminderAgent().proposal(
            for: todo,
            mode: .systemReminderAgent,
            context: SystemReminderContext(now: now, calendar: calendar)
        )

        #expect(proposal.action == .createOrUpdate)
        #expect(proposal.alarmDate == deadline.addingTimeInterval(-30 * 60))
        #expect(proposal.reason.contains("会议"))
    }

    @Test func systemReminderAgentUsesTravelLeadTime() async throws {
        let calendar = makeGregorianCalendar()
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 11, hour: 12)))
        let deadline = try #require(calendar.date(byAdding: .hour, value: 4, to: now))
        let todo = makeTodo(title: "去机场", deadline: deadline)

        let proposal = SystemReminderAgent().proposal(
            for: todo,
            mode: .systemReminderAgent,
            context: SystemReminderContext(now: now, calendar: calendar)
        )

        #expect(proposal.alarmDate == deadline.addingTimeInterval(-2 * 60 * 60))
        #expect(proposal.reason.contains("出行"))
    }

    @Test func systemReminderAgentUsesLongSubmissionLeadTime() async throws {
        let calendar = makeGregorianCalendar()
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 11, hour: 12)))
        let deadline = try #require(calendar.date(byAdding: .hour, value: 48, to: now))
        let todo = makeTodo(title: "提交报告", deadline: deadline)

        let proposal = SystemReminderAgent().proposal(
            for: todo,
            mode: .systemReminderAgent,
            context: SystemReminderContext(now: now, calendar: calendar)
        )

        #expect(proposal.alarmDate == deadline.addingTimeInterval(-24 * 60 * 60))
        #expect(proposal.reason.contains("24 小时"))
    }

    @Test func systemReminderAgentUsesShortSubmissionLeadTimeWhenPossible() async throws {
        let calendar = makeGregorianCalendar()
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 11, hour: 12)))
        let deadline = try #require(calendar.date(byAdding: .hour, value: 5, to: now))
        let todo = makeTodo(title: "作业截止", deadline: deadline)

        let proposal = SystemReminderAgent().proposal(
            for: todo,
            mode: .systemReminderAgent,
            context: SystemReminderContext(now: now, calendar: calendar)
        )

        #expect(proposal.alarmDate == deadline.addingTimeInterval(-2 * 60 * 60))
        #expect(proposal.reason.contains("2 小时"))
    }

    @Test func systemReminderAgentUsesPreparationLeadTime() async throws {
        let calendar = makeGregorianCalendar()
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 11, hour: 12)))
        let deadline = try #require(calendar.date(byAdding: .hour, value: 3, to: now))
        let todo = makeTodo(title: "准备材料", deadline: deadline)

        let proposal = SystemReminderAgent().proposal(
            for: todo,
            mode: .systemReminderAgent,
            context: SystemReminderContext(now: now, calendar: calendar)
        )

        #expect(proposal.alarmDate == deadline.addingTimeInterval(-60 * 60))
        #expect(proposal.reason.contains("准备"))
    }

    @Test func systemReminderAgentUsesDefaultLeadTime() async throws {
        let calendar = makeGregorianCalendar()
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 11, hour: 12)))
        let deadline = try #require(calendar.date(byAdding: .hour, value: 2, to: now))
        let todo = makeTodo(title: "普通待办", deadline: deadline)

        let proposal = SystemReminderAgent().proposal(
            for: todo,
            mode: .systemReminderAgent,
            context: SystemReminderContext(now: now, calendar: calendar)
        )

        #expect(proposal.alarmDate == deadline.addingTimeInterval(-15 * 60))
        #expect(proposal.reason.contains("15 分钟"))
    }

    @Test func systemReminderAgentClampsPastLeadTimeToFutureAlarm() async throws {
        let calendar = makeGregorianCalendar()
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 11, hour: 12)))
        let deadline = try #require(calendar.date(byAdding: .minute, value: 90, to: now))
        let todo = makeTodo(title: "去机场", deadline: deadline)

        let proposal = SystemReminderAgent().proposal(
            for: todo,
            mode: .systemReminderAgent,
            context: SystemReminderContext(now: now, calendar: calendar)
        )

        #expect(proposal.action == .createOrUpdate)
        #expect(proposal.alarmDate == now.addingTimeInterval(60))
        #expect(proposal.alarmDate > now)
    }

    @Test func systemReminderAgentSkipsDeadlineTooClose() async throws {
        let calendar = makeGregorianCalendar()
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 11, hour: 12)))
        let deadline = try #require(calendar.date(byAdding: .second, value: 30, to: now))
        let todo = makeTodo(title: "马上到期", deadline: deadline)

        let proposal = SystemReminderAgent().proposal(
            for: todo,
            mode: .systemReminderAgent,
            context: SystemReminderContext(now: now, calendar: calendar)
        )

        #expect(proposal.action == .skip(.deadlineNotFuture))
    }

    @Test func systemReminderAgentMarkerUsesTodoID() async throws {
        let todo = makeTodo(title: "标记")

        #expect(SystemReminderAgent.marker(for: todo.id) == "EasyNoteTodoID:\(todo.id.uuidString)")
    }

    @Test func systemReminderProposalReconcilerMapsProposalActions() async throws {
        let calendar = makeGregorianCalendar()
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 11, hour: 12)))
        let deadline = try #require(calendar.date(byAdding: .hour, value: 2, to: now))
        let agent = SystemReminderAgent()
        let activeTodo = makeTodo(title: "普通待办", deadline: deadline)
        let completedTodo = makeTodo(title: "完成待办", isCompleted: true, deadline: deadline)
        let noDeadlineTodo = makeTodo(title: "无截止时间")
        let disabledProposal = agent.proposal(
            for: activeTodo,
            mode: .off,
            context: SystemReminderContext(now: now, calendar: calendar)
        )

        let activeProposal = agent.proposal(
            for: activeTodo,
            mode: .systemReminderAgent,
            context: SystemReminderContext(now: now, calendar: calendar)
        )
        let completedProposal = agent.proposal(
            for: completedTodo,
            mode: .systemReminderAgent,
            context: SystemReminderContext(now: now, calendar: calendar)
        )
        let noDeadlineProposal = agent.proposal(
            for: noDeadlineTodo,
            mode: .systemReminderAgent,
            context: SystemReminderContext(now: now, calendar: calendar)
        )

        #expect(SystemReminderProposalReconciler.operation(for: activeProposal) == .apply(activeProposal))
        #expect(SystemReminderProposalReconciler.operation(for: completedProposal) == .complete(completedTodo.id))
        #expect(SystemReminderProposalReconciler.operation(for: noDeadlineProposal) == .remove(noDeadlineTodo.id))
        #expect(SystemReminderProposalReconciler.operation(for: disabledProposal) == .ignore)
    }

    @MainActor
    @Test func todoViewModelSynchronizesNotificationAfterAddingTodo() async throws {
        let context = try makeModelContext()
        let scheduler = FakeTodoNotificationScheduler()
        let viewModel = TodoViewModel(
            modelContext: context,
            notificationScheduler: scheduler,
            systemReminderWriter: FakeSystemReminderWriter(),
            reminderModeStore: FakeTodoReminderModeStore(mode: .localNotification)
        )
        await viewModel.waitForPendingReminderOperations()
        scheduler.reset()

        let deadline = Date().addingTimeInterval(3600)

        #expect(viewModel.addTodoItem(title: "带提醒的待办", deadline: deadline))
        await viewModel.waitForPendingReminderOperations()
        #expect(scheduler.reconciledTodoIDs == [viewModel.todoItems.map(\.id)])
        #expect(scheduler.canceledTodoIDs.isEmpty)
    }

    @MainActor
    @Test func todoNotificationSnapshotRehydratesAnIndependentValue() async throws {
        let deadline = Date(timeIntervalSince1970: 1_800_000_000)
        let creationDate = Date(timeIntervalSince1970: 1_700_000_000)
        let original = TodoItem(
            title: "Original",
            priority: .high,
            deadline: deadline,
            notes: "Private notes",
            isRecurring: true,
            recurringInterval: TodoItem.RecurringInterval.weekly.rawValue
        )
        original.creationDate = creationDate

        let snapshot = TodoNotificationSnapshot(todo: original)
        original.title = "Mutated after snapshot"
        original.deadline = nil

        let detached = snapshot.makeDetachedTodo()
        #expect(detached !== original)
        #expect(detached.id == original.id)
        #expect(detached.title == "Original")
        #expect(detached.priority == .high)
        #expect(detached.deadline == deadline)
        #expect(detached.notes == "Private notes")
        #expect(detached.isRecurring)
        #expect(detached.recurringInterval == TodoItem.RecurringInterval.weekly.rawValue)
        #expect(detached.creationDate == creationDate)
    }

    @MainActor
    @Test func todoViewModelSynchronizesNotificationAfterEditingTodo() async throws {
        let context = try makeModelContext()
        let scheduler = FakeTodoNotificationScheduler()
        let viewModel = TodoViewModel(
            modelContext: context,
            notificationScheduler: scheduler,
            systemReminderWriter: FakeSystemReminderWriter(),
            reminderModeStore: FakeTodoReminderModeStore(mode: .localNotification)
        )
        await viewModel.waitForPendingReminderOperations()
        let todo = makeTodo(title: "原待办")

        #expect(viewModel.addTodoItem(todo))
        await viewModel.waitForPendingReminderOperations()
        scheduler.reset()

        let deadline = Date().addingTimeInterval(7200)

        #expect(viewModel.updateTodoItem(
            id: todo.id,
            title: "改后的待办",
            priority: .high,
            deadline: deadline,
            notes: "需要提醒"
        ))
        await viewModel.waitForPendingReminderOperations()
        #expect(scheduler.reconciledTodoIDs == [viewModel.todoItems.map(\.id)])
        #expect(viewModel.todoItems.first?.title == "改后的待办")
    }

    @MainActor
    @Test func todoViewModelReconcilesNotificationsAfterCompletingTodo() async throws {
        let context = try makeModelContext()
        let scheduler = FakeTodoNotificationScheduler()
        let viewModel = TodoViewModel(
            modelContext: context,
            notificationScheduler: scheduler,
            systemReminderWriter: FakeSystemReminderWriter(),
            reminderModeStore: FakeTodoReminderModeStore(mode: .localNotification)
        )
        await viewModel.waitForPendingReminderOperations()
        let todo = makeTodo(title: "完成后取消", deadline: Date().addingTimeInterval(3600))

        #expect(viewModel.addTodoItem(todo))
        await viewModel.waitForPendingReminderOperations()
        scheduler.reset()

        #expect(viewModel.toggleTodoCompletion(for: todo.id))
        await viewModel.waitForPendingReminderOperations()
        #expect(scheduler.canceledTodoIDs.isEmpty)
        #expect(scheduler.reconciledTodoIDs == [viewModel.todoItems.map(\.id)])
    }

    @MainActor
    @Test func todoViewModelReconcilesOriginalAndNextRecurringTodo() async throws {
        let calendar = Calendar.current
        let context = try makeModelContext()
        let scheduler = FakeTodoNotificationScheduler()
        let viewModel = TodoViewModel(
            modelContext: context,
            notificationScheduler: scheduler,
            systemReminderWriter: FakeSystemReminderWriter(),
            reminderModeStore: FakeTodoReminderModeStore(mode: .localNotification)
        )
        await viewModel.waitForPendingReminderOperations()
        let deadline = try #require(calendar.date(byAdding: .hour, value: 1, to: Date()))
        let recurringTodo = makeTodo(
            title: "循环提醒",
            deadline: deadline,
            isRecurring: true,
            recurringInterval: TodoItem.RecurringInterval.daily.rawValue
        )

        #expect(viewModel.addTodoItem(recurringTodo))
        await viewModel.waitForPendingReminderOperations()
        scheduler.reset()

        #expect(viewModel.toggleTodoCompletion(for: recurringTodo.id))
        await viewModel.waitForPendingReminderOperations()

        let nextTodo = try #require(viewModel.todoItems.first { $0.id != recurringTodo.id })
        #expect(scheduler.canceledTodoIDs.isEmpty)
        #expect(scheduler.reconciledTodoIDs == [viewModel.todoItems.map(\.id)])
        #expect(nextTodo.id != recurringTodo.id)
        #expect(nextTodo.title == recurringTodo.title)
        #expect(nextTodo.deadline == TodoItem.RecurringInterval.daily.nextDate(from: deadline))
    }

    @MainActor
    @Test func todoViewModelCancelsDeletedNotificationAndReconcilesRemainingTodos() async throws {
        let context = try makeModelContext()
        let scheduler = FakeTodoNotificationScheduler()
        let viewModel = TodoViewModel(
            modelContext: context,
            notificationScheduler: scheduler,
            systemReminderWriter: FakeSystemReminderWriter(),
            reminderModeStore: FakeTodoReminderModeStore(mode: .localNotification)
        )
        await viewModel.waitForPendingReminderOperations()
        let deletedTodo = makeTodo(title: "删除", deadline: Date().addingTimeInterval(3600))
        let retainedTodo = makeTodo(title: "保留", deadline: Date().addingTimeInterval(7200))

        #expect(viewModel.addTodoItem(deletedTodo))
        #expect(viewModel.addTodoItem(retainedTodo))
        await viewModel.waitForPendingReminderOperations()
        scheduler.reset()

        #expect(viewModel.deleteTodoItem(withID: deletedTodo.id))
        await viewModel.waitForPendingReminderOperations()
        #expect(scheduler.canceledTodoIDs == [deletedTodo.id])
        #expect(scheduler.reconciledTodoIDs == [viewModel.todoItems.map(\.id)])
    }

    @MainActor
    @Test func todoViewModelAppliesSystemReminderAfterAddingTodo() async throws {
        let context = try makeModelContext()
        let scheduler = FakeTodoNotificationScheduler()
        let writer = FakeSystemReminderWriter()
        let reminderModeStore = FakeTodoReminderModeStore(mode: .systemReminderAgent)
        let viewModel = TodoViewModel(
            modelContext: context,
            notificationScheduler: scheduler,
            systemReminderWriter: writer,
            reminderModeStore: reminderModeStore
        )

        #expect(viewModel.addTodoItem(title: "提交报告", deadline: Date().addingTimeInterval(48 * 60 * 60)))
        await viewModel.waitForPendingReminderOperations()
        #expect(writer.appliedProposals.count == 1)
        #expect(writer.appliedProposals.first?.title == "提交报告")
        #expect(scheduler.reconciledTodoIDs.isEmpty)
        #expect(reminderModeStore.systemRemindersMayExist)
    }

    @MainActor
    @Test func todoViewModelDoesNotApplySystemReminderInLocalOrOffMode() async throws {
        let localContext = try makeModelContext()
        let localWriter = FakeSystemReminderWriter()
        let localViewModel = TodoViewModel(
            modelContext: localContext,
            notificationScheduler: FakeTodoNotificationScheduler(),
            systemReminderWriter: localWriter,
            reminderModeStore: FakeTodoReminderModeStore(mode: .localNotification)
        )

        #expect(localViewModel.addTodoItem(title: "本地通知", deadline: Date().addingTimeInterval(3600)))
        await localViewModel.waitForPendingReminderOperations()
        #expect(localWriter.appliedProposals.isEmpty)

        let offContext = try makeModelContext()
        let offWriter = FakeSystemReminderWriter()
        let offViewModel = TodoViewModel(
            modelContext: offContext,
            notificationScheduler: FakeTodoNotificationScheduler(),
            systemReminderWriter: offWriter,
            reminderModeStore: FakeTodoReminderModeStore(mode: .off)
        )

        #expect(offViewModel.addTodoItem(title: "关闭提醒", deadline: Date().addingTimeInterval(3600)))
        await offViewModel.waitForPendingReminderOperations()
        #expect(offWriter.appliedProposals.isEmpty)
    }

    @MainActor
    @Test func todoViewModelAppliesUpdatedSystemReminderAfterEditingTodo() async throws {
        let context = try makeModelContext()
        let writer = FakeSystemReminderWriter()
        let viewModel = TodoViewModel(
            modelContext: context,
            notificationScheduler: FakeTodoNotificationScheduler(),
            systemReminderWriter: writer,
            reminderModeStore: FakeTodoReminderModeStore(mode: .systemReminderAgent)
        )
        let todo = makeTodo(title: "原待办", deadline: Date().addingTimeInterval(3600))

        #expect(viewModel.addTodoItem(todo))
        await viewModel.waitForPendingReminderOperations()
        writer.reset()

        let updatedDeadline = Date().addingTimeInterval(7200)
        #expect(viewModel.updateTodoItem(
            id: todo.id,
            title: "更新后的会议",
            priority: .high,
            deadline: updatedDeadline,
            notes: "zoom"
        ))
        await viewModel.waitForPendingReminderOperations()

        #expect(writer.appliedProposals.count == 1)
        #expect(writer.appliedProposals.first?.todoID == todo.id)
        #expect(writer.appliedProposals.first?.title == "更新后的会议")
    }

    @MainActor
    @Test func todoViewModelRemovesSystemReminderWhenEditBecomesIneligible() async throws {
        let context = try makeModelContext()
        let writer = FakeSystemReminderWriter()
        let viewModel = TodoViewModel(
            modelContext: context,
            notificationScheduler: FakeTodoNotificationScheduler(),
            systemReminderWriter: writer,
            reminderModeStore: FakeTodoReminderModeStore(mode: .systemReminderAgent)
        )
        let todo = makeTodo(title: "提交报告", deadline: Date().addingTimeInterval(3600))

        #expect(viewModel.addTodoItem(todo))
        await viewModel.waitForPendingReminderOperations()
        writer.reset()

        #expect(viewModel.updateTodoItem(
            id: todo.id,
            title: "提交报告",
            priority: .medium,
            deadline: nil,
            notes: nil
        ))
        await viewModel.waitForPendingReminderOperations()

        #expect(writer.appliedProposals.isEmpty)
        #expect(writer.removedTodoIDs == [todo.id])
    }

    @MainActor
    @Test func todoViewModelCompletesSystemReminderAfterCompletingTodo() async throws {
        let context = try makeModelContext()
        let writer = FakeSystemReminderWriter()
        let viewModel = TodoViewModel(
            modelContext: context,
            notificationScheduler: FakeTodoNotificationScheduler(),
            systemReminderWriter: writer,
            reminderModeStore: FakeTodoReminderModeStore(mode: .systemReminderAgent)
        )
        let todo = makeTodo(title: "完成提醒", deadline: Date().addingTimeInterval(3600))

        #expect(viewModel.addTodoItem(todo))
        await viewModel.waitForPendingReminderOperations()
        writer.reset()

        #expect(viewModel.toggleTodoCompletion(for: todo.id))
        await viewModel.waitForPendingReminderOperations()
        #expect(writer.completedTodoIDs == [todo.id])
        #expect(writer.appliedProposals.isEmpty)
    }

    @MainActor
    @Test func todoViewModelCompletesOriginalAndAppliesNextRecurringSystemReminder() async throws {
        let context = try makeModelContext()
        let writer = FakeSystemReminderWriter()
        let viewModel = TodoViewModel(
            modelContext: context,
            notificationScheduler: FakeTodoNotificationScheduler(),
            systemReminderWriter: writer,
            reminderModeStore: FakeTodoReminderModeStore(mode: .systemReminderAgent)
        )
        let deadline = Date().addingTimeInterval(3600)
        let recurringTodo = makeTodo(
            title: "循环提醒",
            deadline: deadline,
            isRecurring: true,
            recurringInterval: TodoItem.RecurringInterval.daily.rawValue
        )

        #expect(viewModel.addTodoItem(recurringTodo))
        await viewModel.waitForPendingReminderOperations()
        writer.reset()

        #expect(viewModel.toggleTodoCompletion(for: recurringTodo.id))
        await viewModel.waitForPendingReminderOperations()
        let nextTodo = try #require(viewModel.todoItems.first { $0.id != recurringTodo.id })
        #expect(writer.completedTodoIDs == [recurringTodo.id])
        #expect(writer.appliedProposals.map(\.todoID) == [nextTodo.id])
    }

    @MainActor
    @Test func todoViewModelRemovesSystemReminderAfterDeletingTodo() async throws {
        let context = try makeModelContext()
        let writer = FakeSystemReminderWriter()
        let viewModel = TodoViewModel(
            modelContext: context,
            notificationScheduler: FakeTodoNotificationScheduler(),
            systemReminderWriter: writer,
            reminderModeStore: FakeTodoReminderModeStore(mode: .systemReminderAgent)
        )
        let todo = makeTodo(title: "删除提醒", deadline: Date().addingTimeInterval(3600))

        #expect(viewModel.addTodoItem(todo))
        await viewModel.waitForPendingReminderOperations()
        writer.reset()

        #expect(viewModel.deleteTodoItem(withID: todo.id))
        await viewModel.waitForPendingReminderOperations()
        #expect(writer.removedTodoIDs == [todo.id])
    }

    @MainActor
    @Test func todoViewModelRemovesSystemReminderAfterDeletingTodoInLocalMode() async throws {
        let context = try makeModelContext()
        let scheduler = FakeTodoNotificationScheduler()
        let writer = FakeSystemReminderWriter()
        let viewModel = TodoViewModel(
            modelContext: context,
            notificationScheduler: scheduler,
            systemReminderWriter: writer,
            reminderModeStore: FakeTodoReminderModeStore(mode: .localNotification)
        )
        await viewModel.waitForPendingReminderOperations()
        let todo = makeTodo(title: "曾经写入系统提醒", deadline: Date().addingTimeInterval(3600))

        #expect(viewModel.addTodoItem(todo))
        await viewModel.waitForPendingReminderOperations()
        scheduler.reset()
        writer.reset()

        #expect(viewModel.deleteTodoItem(withID: todo.id))
        await viewModel.waitForPendingReminderOperations()
        #expect(scheduler.canceledTodoIDs == [todo.id])
        #expect(writer.removedTodoIDs == [todo.id])
    }

    @MainActor
    @Test func todoViewModelReconcilesSystemRemindersAfterBackupReload() async throws {
        let context = try makeModelContext()
        let writer = FakeSystemReminderWriter()
        let viewModel = TodoViewModel(
            modelContext: context,
            notificationScheduler: FakeTodoNotificationScheduler(),
            systemReminderWriter: writer,
            reminderModeStore: FakeTodoReminderModeStore(mode: .systemReminderAgent)
        )
        let todo = makeTodo(title: "导入前待办", deadline: Date().addingTimeInterval(3600))

        #expect(viewModel.addTodoItem(todo))
        await viewModel.waitForPendingReminderOperations()
        writer.reset()

        todo.deadline = nil
        try context.save()
        viewModel.reloadTodoItemsAfterExternalImport()
        await viewModel.waitForPendingReminderOperations()

        #expect(writer.removedTodoIDs == [todo.id])
    }

    @MainActor
    @Test func todoViewModelDoesNotWriteSystemReminderWhenSwiftDataSaveFails() async throws {
        let context = try makeModelContext()
        let writer = FakeSystemReminderWriter()
        let viewModel = TodoViewModel(
            modelContext: context,
            notificationScheduler: FakeTodoNotificationScheduler(),
            systemReminderWriter: writer,
            reminderModeStore: FakeTodoReminderModeStore(mode: .systemReminderAgent),
            saveModelContext: { _ in throw TestSaveError.failed }
        )

        #expect(!viewModel.addTodoItem(title: "不会写入", deadline: Date().addingTimeInterval(3600)))
        await viewModel.waitForPendingReminderOperations()
        #expect(writer.appliedProposals.isEmpty)
        #expect(writer.completedTodoIDs.isEmpty)
        #expect(writer.removedTodoIDs.isEmpty)
    }

    @MainActor
    @Test func todoViewModelKeepsSavedTodoWhenSystemReminderWriterFails() async throws {
        let context = try makeModelContext()
        let writer = FakeSystemReminderWriter()
        writer.applyResult = .failure(.notAuthorized)
        let reminderModeStore = FakeTodoReminderModeStore(mode: .systemReminderAgent)
        let viewModel = TodoViewModel(
            modelContext: context,
            notificationScheduler: FakeTodoNotificationScheduler(),
            systemReminderWriter: writer,
            reminderModeStore: reminderModeStore
        )

        #expect(viewModel.addTodoItem(title: "保存成功提醒失败", deadline: Date().addingTimeInterval(3600)))
        await viewModel.waitForPendingReminderOperations()
        #expect(viewModel.todoItems.count == 1)
        #expect(writer.appliedProposals.count == 1)
        #expect(viewModel.systemReminderErrorMessage == "未授予提醒事项权限")
        #expect(!reminderModeStore.systemRemindersMayExist)
    }

    @MainActor
    @Test func todoViewModelKeepsSavedTodoWhenLocalNotificationSchedulingFails() async throws {
        let context = try makeModelContext()
        let scheduler = FakeTodoNotificationScheduler()
        let viewModel = TodoViewModel(
            modelContext: context,
            notificationScheduler: scheduler,
            systemReminderWriter: FakeSystemReminderWriter(),
            reminderModeStore: FakeTodoReminderModeStore(mode: .localNotification)
        )
        await viewModel.waitForPendingReminderOperations()
        scheduler.reset()
        scheduler.reconcileError = TodoNotificationError.schedulingFailed("测试失败")

        #expect(viewModel.addTodoItem(title: "本地保存成功", deadline: Date().addingTimeInterval(3600)))
        await viewModel.waitForPendingReminderOperations()

        let storedTodos = try context.fetch(FetchDescriptor<TodoItem>())
        #expect(storedTodos.count == 1)
        #expect(storedTodos.first?.title == "本地保存成功")
        #expect(viewModel.systemReminderErrorMessage == "写入 EasyNote 通知失败: 测试失败")
    }

    @Test func todoReminderModeStoreMigratesLegacyNotificationSetting() async throws {
        let suiteName = "EasyNoteTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        defaults.set(true, forKey: LocalTodoNotificationService.enabledDefaultsKey)
        let store = TodoReminderModeStore(defaults: defaults)

        #expect(store.currentMode == .localNotification)
    }

    @Test func todoReminderModeStoreUpdatesLegacyNotificationFlag() async throws {
        let suiteName = "EasyNoteTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let store = TodoReminderModeStore(defaults: defaults)

        store.currentMode = .systemReminderAgent
        #expect(defaults.bool(forKey: LocalTodoNotificationService.enabledDefaultsKey) == false)

        store.currentMode = .localNotification
        #expect(defaults.bool(forKey: LocalTodoNotificationService.enabledDefaultsKey))
    }

    @Test func todoReminderModeStorePersistsPossibleSystemReminderOwnership() async throws {
        let suiteName = "EasyNoteTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let store = TodoReminderModeStore(defaults: defaults)

        #expect(!store.systemRemindersMayExist)
        store.currentMode = .systemReminderAgent
        #expect(!store.systemRemindersMayExist)

        store.systemRemindersMayExist = true
        #expect(store.systemRemindersMayExist)
        store.systemRemindersMayExist = false
        #expect(!store.systemRemindersMayExist)
    }

    @Test func todoReminderModeTransitionPlannerClearsSystemRemindersOnlyForLocalHandoff() async throws {
        #expect(TodoReminderModeTransitionPlanner.shouldRemoveSystemReminders(
            previousMode: .systemReminderAgent,
            nextMode: .localNotification,
            systemRemindersMayExist: false
        ))
        #expect(TodoReminderModeTransitionPlanner.shouldRemoveSystemReminders(
            previousMode: .off,
            nextMode: .localNotification,
            systemRemindersMayExist: true
        ))
        #expect(!TodoReminderModeTransitionPlanner.shouldRemoveSystemReminders(
            previousMode: .off,
            nextMode: .localNotification,
            systemRemindersMayExist: false
        ))
        #expect(!TodoReminderModeTransitionPlanner.shouldRemoveSystemReminders(
            previousMode: .systemReminderAgent,
            nextMode: .off,
            systemRemindersMayExist: true
        ))
        #expect(!TodoReminderModeTransitionPlanner.shouldRemoveSystemReminders(
            previousMode: .localNotification,
            nextMode: .systemReminderAgent,
            systemRemindersMayExist: true
        ))
        #expect(TodoReminderModeTransitionPlanner.shouldSyncSystemReminders(nextMode: .systemReminderAgent))
        #expect(!TodoReminderModeTransitionPlanner.shouldSyncSystemReminders(nextMode: .localNotification))
    }
    
    @Test func chatSessionSummaryUsesLatestUserMessage() async throws {
        let session = ChatSession(title: "新会话")
        
        #expect(session.generateSummary() == "新会话")
        
        session.addMessage(SessionMessage(content: "第一条用户消息", isUser: true))
        session.addMessage(SessionMessage(content: "AI回复不会成为标题", isUser: false))
        
        #expect(session.generateSummary() == "第一条用户消息")
        
        let longMessage = "这是一条超过二十个字符的用户消息，用于生成会话摘要"
        session.addMessage(SessionMessage(content: longMessage, isUser: true))
        
        #expect(session.generateSummary() == "\(longMessage.prefix(20))...")
    }
    
    @Test func chatSessionIntegrityAcceptsValidMessages() async throws {
        let session = ChatSession(title: "有效会话")
        let message = SessionMessage(content: "有效消息", isUser: true)
        
        session.addMessage(message)
        
        #expect(message.validateIntegrity())
        #expect(session.validateIntegrity())
    }

    @Test func chatIntegrityRejectsEmptyContentAndFutureDates() async throws {
        let emptyTitleSession = ChatSession(title: "")
        let futureSession = ChatSession(title: "未来会话")
        futureSession.creationDate = Date().addingTimeInterval(60)
        let emptyMessage = SessionMessage(content: "", isUser: true)
        let futureMessage = SessionMessage(
            content: "未来消息",
            isUser: false,
            timestamp: Date().addingTimeInterval(60)
        )
        let sessionWithEmptyMessage = ChatSession(title: "包含空消息")
        sessionWithEmptyMessage.addMessage(emptyMessage)

        #expect(!emptyTitleSession.validateIntegrity())
        #expect(!futureSession.validateIntegrity())
        #expect(!emptyMessage.validateIntegrity())
        #expect(!futureMessage.validateIntegrity())
        #expect(!sessionWithEmptyMessage.validateIntegrity())
    }

    @Test func aiResponseParserParsesDiaryAnalysisJSON() async throws {
        let result = AIResponseParser.parseDiaryAnalysis("""
        {"moods":["开心","期待"],"tags":["工作","成长"]}
        """)

        #expect(result.moods == ["开心", "期待"])
        #expect(result.tags == ["工作", "成长"])
    }

    @Test func aiResponseParserParsesDiaryAnalysisFencedJSON() async throws {
        let result = AIResponseParser.parseDiaryAnalysis("""
        下面是分析结果：
        ```json
        {
          "moods": ["平静", "满足"],
          "tags": ["生活", "复盘"]
        }
        ```
        """)

        #expect(result.moods == ["平静", "满足"])
        #expect(result.tags == ["生活", "复盘"])
    }

    @Test func aiResponseParserFallsBackForBrokenDiaryAnalysis() async throws {
        let result = AIResponseParser.parseDiaryAnalysis("今天整体不错，但这里没有结构化 JSON")
        let defaults = AIResponseParser.defaultDiaryAnalysis()

        #expect(result.moods == defaults.moods)
        #expect(result.tags == defaults.tags)
    }

    @Test func aiResponseParserParsesRecommendationsJSONInsideText() async throws {
        let result = AIResponseParser.parseRecommendations("""
        可以参考下面的结构化结果：
        {
          "recommendations": ["散步20分钟", "读一章书"],
          "todos": ["整理书桌", "记录今日复盘"]
        }
        祝你今天顺利。
        """)

        #expect(result.recommendations == ["散步20分钟", "读一章书"])
        #expect(result.todos == ["整理书桌", "记录今日复盘"])
    }

    @Test func aiResponseParserParsesRecommendationsFencedJSON() async throws {
        let result = AIResponseParser.parseRecommendations("""
        ```json
        {
          "recommendations": ["做一次拉伸", "联系朋友"],
          "todos": ["补充饮水", "规划明天"]
        }
        ```
        """)

        #expect(result.recommendations == ["做一次拉伸", "联系朋友"])
        #expect(result.todos == ["补充饮水", "规划明天"])
    }

    @Test func aiResponseParserParsesChineseRecommendationLists() async throws {
        let result = AIResponseParser.parseRecommendations("""
        推荐活动：
        1. 散步20分钟
        2. 阅读一章书
        待办事项：
        - 整理书桌
        - 记录今日复盘
        """)

        #expect(result.recommendations == ["散步20分钟", "阅读一章书"])
        #expect(result.todos == ["整理书桌", "记录今日复盘"])
    }

    @Test func aiResponseParserFallsBackForBrokenRecommendations() async throws {
        let result = AIResponseParser.parseRecommendations("完全损坏的模型输出")
        let defaults = AIResponseParser.defaultRecommendations()

        #expect(result.recommendations == defaults.recommendations)
        #expect(result.todos == defaults.todos)
    }

    @Test func openAIServiceFailsClosedWhenAPIKeyIsEmpty() async throws {
        let credentials = InMemoryCredentialStore(apiKey: nil)
        let consent = InMemoryConsentStore(isGranted: true)
        let httpClient = RecordingAIHTTPClient()
        let service = OpenAIService(
            credentialStore: credentials,
            consentStore: consent,
            httpClient: httpClient
        )

        let error = await publisherFailure(service.generateSummary(from: "测试内容"))

        guard case let .apiError(message) = try #require(error) else {
            Issue.record("Expected empty API key to produce OpenAIError.apiError")
            return
        }
        #expect(message == "请在设置中添加DeepSeek API密钥后再使用AI功能")
        #expect(httpClient.requestCount == 0)
    }

    @MainActor
    @Test func diaryViewModelUsesInjectedAIServiceForEmptyKeySummaryFailure() async throws {
        let context = try makeModelContext()
        let entry = makeDiary(title: "待总结", content: "今天完成了服务注入边界整理。")
        context.insert(entry)
        try context.save()

        let aiService = FakeOpenAIService(apiKey: "")
        let viewModel = DiaryViewModel(
            modelContext: context,
            speechService: FakeSpeechRecognitionService(),
            openAIService: aiService,
            cloudKitService: FakeCloudKitDiarySyncService()
        )
        viewModel.currentEntry = entry

        viewModel.generateAISummary()

        #expect(aiService.generateSummaryCallCount == 0)
        #expect(viewModel.pendingAIResults.isEmpty)
        #expect(viewModel.aiActionHistory.count == 1)
        #expect(viewModel.aiActionHistory.first?.isSuccess == false)
        #expect(viewModel.errorMessage == "请在设置中添加DeepSeek API密钥后再使用AI功能")
    }

    @Test func aiActionResultRecordsSuccessFailureAndPreview() async throws {
        let timestamp = try #require(makeGregorianCalendar().date(from: DateComponents(year: 2026, month: 6, day: 20)))
        let success = AIActionResult.success(
            actionType: .refine,
            applicationTarget: .transcriptionText,
            input: "第一行\n第二行内容很长",
            outputText: "润色结果",
            timestamp: timestamp,
            previewLimit: 5
        )
        let failure = AIActionResult.failure(
            actionType: .summary,
            applicationTarget: .diarySummary,
            input: "日记正文",
            message: "生成失败",
            timestamp: timestamp
        )

        #expect(success.isSuccess)
        #expect(success.canApply)
        #expect(success.matchesInput("第一行\n第二行内容很长"))
        #expect(!success.matchesInput("第一行\n第二行内容已变化"))
        #expect(success.inputPreview == "第一行 第...")
        #expect(success.outputText == "润色结果")
        #expect(success.timestamp == timestamp)
        #expect(!failure.isSuccess)
        #expect(!failure.canApply)
        #expect(failure.failureMessage == "生成失败")
    }

    @MainActor
    @Test func diaryViewModelAppliesPendingSummaryOnlyAfterConfirmation() async throws {
        let context = try makeModelContext()
        let entry = makeDiary(title: "需要摘要", content: "今天完成了项目复盘。")
        context.insert(entry)
        try context.save()
        let viewModel = DiaryViewModel(modelContext: context)
        viewModel.currentEntry = entry
        let result = AIActionResult.success(
            actionType: .summary,
            applicationTarget: .diarySummary,
            sourceEntityId: entry.id,
            input: entry.content,
            outputText: "项目复盘摘要"
        )

        viewModel.recordAIActionResult(result)

        #expect(entry.aiSummary == nil)
        #expect(viewModel.pendingAIResult == result)
        #expect(viewModel.applyAIResult(result))
        #expect(entry.aiSummary == "项目复盘摘要")
        #expect(viewModel.pendingAIResult == nil)
    }

    @MainActor
    @Test func diaryViewModelAppliesSummaryToSourceEntryAfterCurrentEntryChanges() async throws {
        let context = try makeModelContext()
        let sourceEntry = makeDiary(title: "源日记", content: "需要摘要的内容")
        let otherEntry = makeDiary(title: "当前日记", content: "不应该被写入")
        context.insert(sourceEntry)
        context.insert(otherEntry)
        try context.save()
        let viewModel = DiaryViewModel(modelContext: context)
        viewModel.diaryEntries = [sourceEntry, otherEntry]
        viewModel.currentEntry = otherEntry
        let result = AIActionResult.success(
            actionType: .summary,
            applicationTarget: .diarySummary,
            sourceEntityId: sourceEntry.id,
            input: sourceEntry.content,
            outputText: "源日记摘要"
        )

        viewModel.recordAIActionResult(result)

        #expect(viewModel.pendingAIResult(for: .diarySummary, sourceEntityId: sourceEntry.id) == result)
        #expect(viewModel.pendingAIResult(for: .diarySummary, sourceEntityId: otherEntry.id) == nil)
        #expect(viewModel.applyAIResult(result))
        #expect(sourceEntry.aiSummary == "源日记摘要")
        #expect(otherEntry.aiSummary == nil)
    }

    @MainActor
    @Test func diaryViewModelRejectsStalePendingSummaryAfterContentChanges() async throws {
        let context = try makeModelContext()
        let entry = makeDiary(title: "源日记", content: "旧正文")
        context.insert(entry)
        try context.save()
        let viewModel = DiaryViewModel(modelContext: context)
        viewModel.currentEntry = entry
        let result = AIActionResult.success(
            actionType: .summary,
            applicationTarget: .diarySummary,
            sourceEntityId: entry.id,
            input: entry.content,
            outputText: "旧摘要"
        )

        viewModel.recordAIActionResult(result)
        entry.content = "新正文"

        #expect(!viewModel.applyAIResult(result))
        #expect(entry.aiSummary == nil)
        #expect(viewModel.pendingAIResult(for: .diarySummary, sourceEntityId: entry.id) == nil)
        #expect(viewModel.errorMessage == "日记内容已变化，请重新生成AI摘要")
    }

    @MainActor
    @Test func diaryViewModelKeepsPendingAIResultsPerApplicationTarget() async throws {
        let viewModel = DiaryViewModel(modelContext: try makeModelContext())
        let firstDiaryId = UUID()
        let secondDiaryId = UUID()
        let summary = AIActionResult.success(
            actionType: .summary,
            applicationTarget: .diarySummary,
            sourceEntityId: firstDiaryId,
            input: "日记正文",
            outputText: "摘要"
        )
        let secondSummary = AIActionResult.success(
            actionType: .summary,
            applicationTarget: .diarySummary,
            sourceEntityId: secondDiaryId,
            input: "另一篇日记正文",
            outputText: "另一篇摘要"
        )
        let transcription = AIActionResult.success(
            actionType: .refine,
            applicationTarget: .transcriptionText,
            input: "原始转写",
            outputText: "润色转写"
        )

        viewModel.recordAIActionResult(summary)
        viewModel.recordAIActionResult(secondSummary)
        viewModel.recordAIActionResult(transcription)

        #expect(viewModel.pendingAIResult(for: .diarySummary, sourceEntityId: firstDiaryId) == summary)
        #expect(viewModel.pendingAIResult(for: .diarySummary, sourceEntityId: secondDiaryId) == secondSummary)
        #expect(viewModel.pendingAIResult(for: .transcriptionText) == transcription)
    }

    @MainActor
    @Test func diaryViewModelAppliesPendingTranscriptionOnlyAfterConfirmation() async throws {
        let viewModel = DiaryViewModel(modelContext: try makeModelContext())
        viewModel.transcribedText = "原始转写"
        let result = AIActionResult.success(
            actionType: .refine,
            applicationTarget: .transcriptionText,
            input: "原始转写",
            outputText: "润色后的转写"
        )

        viewModel.recordAIActionResult(result)

        #expect(viewModel.transcribedText == "原始转写")
        #expect(viewModel.pendingAIResult == result)
        #expect(viewModel.applyAIResult(result))
        #expect(viewModel.transcribedText == "润色后的转写")
        #expect(viewModel.pendingAIResult == nil)
    }

    @MainActor
    @Test func diaryViewModelAnalyzesRefinedTranscriptionAfterApply() async throws {
        let viewModel = DiaryViewModel(modelContext: try makeModelContext())
        final class AnalysisProbe {
            var content: String?
        }
        let probe = AnalysisProbe()
        viewModel.refinedContentAnalysisHandler = { content in
            probe.content = content
        }
        viewModel.transcribedText = "原始转写"
        let result = AIActionResult.success(
            actionType: .refine,
            applicationTarget: .transcriptionText,
            input: "原始转写",
            outputText: "润色后的转写"
        )

        viewModel.recordAIActionResult(result)

        #expect(probe.content == nil)
        #expect(viewModel.applyAIResult(result))
        #expect(probe.content == "润色后的转写")
    }

    @MainActor
    @Test func diaryViewModelAppliesEditorContentAIResultWhenEditorIsUnchanged() async throws {
        let viewModel = DiaryViewModel(modelContext: try makeModelContext())
        final class AnalysisProbe {
            var content: String?
        }
        let probe = AnalysisProbe()
        viewModel.refinedContentAnalysisHandler = { content in
            probe.content = content
        }
        viewModel.setTranscriptionText("编辑正文", inputSource: .editorContent)
        let result = AIActionResult.success(
            actionType: .refine,
            applicationTarget: .transcriptionText,
            inputSource: .editorContent,
            input: "编辑正文",
            outputText: "润色正文"
        )

        viewModel.recordAIActionResult(result)

        #expect(viewModel.applyAIResult(result, currentEditorContent: "编辑正文"))
        #expect(viewModel.transcribedText == "润色正文")
        #expect(viewModel.transcriptionInputSource == .defaultText)
        #expect(probe.content == "润色正文")
    }

    @MainActor
    @Test func diaryViewModelAppliesChainedResultAfterEditorContentResult() async throws {
        let viewModel = DiaryViewModel(modelContext: try makeModelContext())
        viewModel.refinedContentAnalysisHandler = { _ in }
        viewModel.setTranscriptionText("编辑正文", inputSource: .editorContent)
        let firstResult = AIActionResult.success(
            actionType: .refine,
            applicationTarget: .transcriptionText,
            inputSource: .editorContent,
            input: "编辑正文",
            outputText: "润色正文"
        )

        viewModel.recordAIActionResult(firstResult)
        #expect(viewModel.applyAIResult(firstResult, currentEditorContent: "编辑正文"))

        let chainedResult = AIActionResult.success(
            actionType: .expand,
            applicationTarget: .transcriptionText,
            input: "润色正文",
            outputText: "扩写正文"
        )
        viewModel.recordAIActionResult(chainedResult)

        #expect(viewModel.applyAIResult(chainedResult, currentEditorContent: "编辑正文"))
        #expect(viewModel.transcribedText == "扩写正文")
    }

    @MainActor
    @Test func diaryViewModelRejectsEditorContentAIResultAfterEditorChanges() async throws {
        let viewModel = DiaryViewModel(modelContext: try makeModelContext())
        viewModel.setTranscriptionText("旧正文", inputSource: .editorContent)
        let result = AIActionResult.success(
            actionType: .refine,
            applicationTarget: .transcriptionText,
            inputSource: .editorContent,
            input: "旧正文",
            outputText: "旧润色"
        )

        viewModel.recordAIActionResult(result)

        #expect(!viewModel.applyAIResult(result, currentEditorContent: "新正文"))
        #expect(viewModel.transcribedText == "旧正文")
        #expect(viewModel.pendingAIResult(for: .transcriptionText) == nil)
        #expect(viewModel.errorMessage == "当前编辑内容已变化，请重新生成AI结果")
    }

    @MainActor
    @Test func diaryViewModelClearsPendingTranscriptionResultsWhenBufferResets() async throws {
        let viewModel = DiaryViewModel(modelContext: try makeModelContext())
        let result = AIActionResult.success(
            actionType: .expand,
            applicationTarget: .transcriptionText,
            input: "旧转写",
            outputText: "旧扩写"
        )

        viewModel.recordAIActionResult(result)
        viewModel.setTranscriptionText("")

        #expect(viewModel.pendingAIResult(for: .transcriptionText) == nil)
    }

    @MainActor
    @Test func diaryViewModelClearsPendingTranscriptionResultsForNewRecording() async throws {
        let viewModel = DiaryViewModel(modelContext: try makeModelContext())
        viewModel.setTranscriptionText("编辑正文", inputSource: .editorContent)
        let result = AIActionResult.success(
            actionType: .refine,
            applicationTarget: .transcriptionText,
            inputSource: .editorContent,
            input: "编辑正文",
            outputText: "润色正文"
        )

        viewModel.recordAIActionResult(result)
        viewModel.prepareTranscriptionForNewRecording()

        #expect(viewModel.pendingAIResult(for: .transcriptionText) == nil)
        #expect(viewModel.transcriptionInputSource == .defaultText)
    }

    @MainActor
    @Test func diaryViewModelRejectsStalePendingTranscriptionAfterTextChanges() async throws {
        let viewModel = DiaryViewModel(modelContext: try makeModelContext())
        viewModel.transcribedText = "旧转写"
        let result = AIActionResult.success(
            actionType: .refine,
            applicationTarget: .transcriptionText,
            input: "旧转写",
            outputText: "旧润色"
        )

        viewModel.recordAIActionResult(result)
        viewModel.transcribedText = "新转写"

        #expect(!viewModel.applyAIResult(result))
        #expect(viewModel.transcribedText == "新转写")
        #expect(viewModel.pendingAIResult(for: .transcriptionText) == nil)
        #expect(viewModel.errorMessage == "转写内容已变化，请重新生成AI结果")
    }

    @MainActor
    @Test func diaryViewModelDoesNotPromoteFailureResultToPending() async throws {
        let viewModel = DiaryViewModel(modelContext: try makeModelContext())
        let result = AIActionResult.failure(
            actionType: .summary,
            applicationTarget: .diarySummary,
            input: "内容",
            message: "请在设置中添加DeepSeek API密钥后再使用AI功能"
        )

        viewModel.recordAIActionResult(result)

        #expect(viewModel.aiActionHistory.first == result)
        #expect(viewModel.pendingAIResult == nil)
    }

    @MainActor
    @Test func diaryViewModelClearsStalePendingResultAfterFailureForSameTarget() async throws {
        let viewModel = DiaryViewModel(modelContext: try makeModelContext())
        let success = AIActionResult.success(
            actionType: .refine,
            applicationTarget: .transcriptionText,
            input: "旧转写",
            outputText: "旧润色"
        )
        let failure = AIActionResult.failure(
            actionType: .refine,
            applicationTarget: .transcriptionText,
            input: "新转写",
            message: "网络错误"
        )

        viewModel.recordAIActionResult(success)
        viewModel.recordAIActionResult(failure)

        #expect(viewModel.pendingAIResult(for: .transcriptionText) == nil)
        #expect(viewModel.aiActionHistory.first == failure)
    }

    @MainActor
    @Test func diaryViewModelDiscardsPendingAIResultFromHistory() async throws {
        let viewModel = DiaryViewModel(modelContext: try makeModelContext())
        let result = AIActionResult.success(
            actionType: .expand,
            applicationTarget: .transcriptionText,
            input: "短句",
            outputText: "扩写后的内容"
        )

        viewModel.recordAIActionResult(result)
        viewModel.discardAIResult(result)

        #expect(viewModel.pendingAIResult == nil)
        #expect(viewModel.aiActionHistory.isEmpty)
    }

    @Test func diaryDraftComposerInsertsTranscriptionAfterExistingContent() async throws {
        let result = DiaryDraftComposer.apply(
            transcription: "今天完成了语音记录",
            to: "已有正文",
            mode: .insert
        )

        #expect(result == "已有正文\n\n今天完成了语音记录")
    }

    @Test func diaryDraftComposerReplacesContentWithTranscription() async throws {
        let result = DiaryDraftComposer.apply(
            transcription: "替换后的正文",
            to: "已有正文",
            mode: .replace
        )

        #expect(result == "替换后的正文")
    }

    @Test func diaryDraftComposerKeepsContentForEmptyTranscription() async throws {
        let result = DiaryDraftComposer.apply(
            transcription: "   \n ",
            to: "已有正文",
            mode: .replace
        )

        #expect(result == "已有正文")
    }

    @Test func moodCatalogNormalizesNumericValuesAndAcceptsChineseLabels() async throws {
        #expect(MoodCatalog.storedLabel(for: 4) == "不错")
        #expect(MoodCatalog.index(forStoredLabel: "很棒") == 5)
        #expect(MoodCatalog.index(forStoredLabel: "开心") == 5)
        #expect(MoodCatalog.canonicalStoredLabel("4") == "不错")
        #expect(MoodCatalog.canonicalStoredLabel("开心") == "开心")
        #expect(MoodCatalog.systemImage(forStoredLabel: "平静") == "face.dashed")
        #expect(MoodCatalog.canonicalStoredLabel("999") == "一般")
        #expect(MoodCatalog.canonicalStoredLabel("  ") == nil)
    }

    @MainActor
    @Test func diaryEditTranscriptionDoesNotPersistBeforeCommit() async throws {
        let context = try makeModelContext()
        let entry = makeDiary(title: "语音草稿", content: "已有正文", tags: ["原标签"], mood: "平静")
        context.insert(entry)
        try context.save()
        let viewModel = DiaryViewModel(modelContext: context)
        var draft = DiaryEditDraft(
            entryID: entry.id,
            content: entry.content,
            mood: entry.mood,
            tags: entry.tags,
            originalAudioURL: nil
        )

        viewModel.setTranscriptionText("新增转写")
        draft.content = viewModel.applyTranscription(to: draft.content, mode: .insert)

        #expect(entry.content == "已有正文")
        #expect(draft.content == "已有正文\n\n新增转写")
        #expect(viewModel.commitEditDraft(draft, forEntryID: entry.id))
        #expect(entry.content == "已有正文\n\n新增转写")
    }

    @MainActor
    @Test func diaryViewModelCommitsEditDraftWithOneSaveAndThenRemovesReplacedAudio() async throws {
        let context = try makeModelContext()
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let originalAudioURL = directory.appendingPathComponent("original.caf")
        let replacementAudioURL = directory.appendingPathComponent("replacement.caf")
        try Data([0x01]).write(to: originalAudioURL)
        try Data([0x02]).write(to: replacementAudioURL)

        let entry = makeDiary(title: "待编辑", content: "旧正文", tags: ["旧标签"], mood: "一般")
        entry.audioURL = originalAudioURL
        context.insert(entry)
        try context.save()
        var saveCallCount = 0
        let viewModel = DiaryViewModel(
            modelContext: context,
            saveModelContext: { context in
                saveCallCount += 1
                try context.save()
            }
        )
        var draft = DiaryEditDraft(
            entryID: entry.id,
            content: entry.content,
            mood: entry.mood,
            tags: entry.tags,
            originalAudioURL: entry.audioURL
        )
        draft.content = "新正文"
        draft.mood = "4"
        draft.tags = ["新标签"]
        draft.replacePendingRecording(with: replacementAudioURL)

        #expect(viewModel.commitEditDraft(draft, forEntryID: entry.id))

        #expect(saveCallCount == 1)
        #expect(entry.content == "新正文")
        #expect(entry.mood == "不错")
        #expect(entry.tags == ["新标签"])
        #expect(entry.audioURL == replacementAudioURL)
        #expect(!FileManager.default.fileExists(atPath: originalAudioURL.path))
        #expect(FileManager.default.fileExists(atPath: replacementAudioURL.path))
    }

    @MainActor
    @Test func diaryEditDraftDiscardKeepsEntryAndOriginalAudioUnchanged() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let originalAudioURL = directory.appendingPathComponent("original.caf")
        let pendingAudioURL = directory.appendingPathComponent("pending.caf")
        try Data([0x01]).write(to: originalAudioURL)
        try Data([0x02]).write(to: pendingAudioURL)

        let entry = makeDiary(title: "放弃编辑", content: "原正文", tags: ["原标签"], mood: "平静")
        entry.audioURL = originalAudioURL
        var draft = DiaryEditDraft(
            entryID: entry.id,
            content: entry.content,
            mood: entry.mood,
            tags: entry.tags,
            originalAudioURL: entry.audioURL
        )
        draft.content = "未保存正文"
        draft.mood = "很棒"
        draft.tags = ["未保存标签"]
        draft.replacePendingRecording(with: pendingAudioURL)

        let discardedAudioURL = draft.discardPendingRecording()
        DiaryViewModel.removeRecordingFile(at: discardedAudioURL)

        #expect(entry.content == "原正文")
        #expect(entry.mood == "平静")
        #expect(entry.tags == ["原标签"])
        #expect(entry.audioURL == originalAudioURL)
        #expect(FileManager.default.fileExists(atPath: originalAudioURL.path))
        #expect(!FileManager.default.fileExists(atPath: pendingAudioURL.path))
        #expect(draft.pendingReplacementAudioURL == nil)
    }

    @MainActor
    @Test func diaryEditDraftReplacementReturnsOnlySupersededPendingAudio() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let originalAudioURL = directory.appendingPathComponent("original.caf")
        let firstPendingURL = directory.appendingPathComponent("first.caf")
        let secondPendingURL = directory.appendingPathComponent("second.caf")
        try Data([0x01]).write(to: originalAudioURL)
        try Data([0x02]).write(to: firstPendingURL)
        try Data([0x03]).write(to: secondPendingURL)
        var draft = DiaryEditDraft(
            entryID: UUID(),
            content: "正文",
            mood: nil,
            tags: [],
            originalAudioURL: originalAudioURL
        )

        #expect(draft.replacePendingRecording(with: firstPendingURL) == nil)
        let supersededFirstURL = draft.replacePendingRecording(with: secondPendingURL)
        DiaryViewModel.removeRecordingFile(at: supersededFirstURL)
        #expect(supersededFirstURL == firstPendingURL)
        #expect(draft.pendingReplacementAudioURL == secondPendingURL)
        #expect(!FileManager.default.fileExists(atPath: firstPendingURL.path))
        #expect(FileManager.default.fileExists(atPath: originalAudioURL.path))
        #expect(FileManager.default.fileExists(atPath: secondPendingURL.path))

        let supersededSecondURL = draft.replacePendingRecording(with: originalAudioURL)
        DiaryViewModel.removeRecordingFile(at: supersededSecondURL)
        #expect(supersededSecondURL == secondPendingURL)
        #expect(draft.pendingReplacementAudioURL == nil)
        #expect(FileManager.default.fileExists(atPath: originalAudioURL.path))
        #expect(!FileManager.default.fileExists(atPath: secondPendingURL.path))
    }

    @MainActor
    @Test func diaryViewModelFailedDraftSaveRollsBackAndPreservesBothRecordingsForRetry() async throws {
        let context = try makeModelContext()
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let originalAudioURL = directory.appendingPathComponent("original.caf")
        let replacementAudioURL = directory.appendingPathComponent("replacement.caf")
        try Data([0x01]).write(to: originalAudioURL)
        try Data([0x02]).write(to: replacementAudioURL)

        let entry = makeDiary(title: "失败回滚", content: "旧正文", tags: ["旧标签"], mood: "一般")
        entry.audioURL = originalAudioURL
        context.insert(entry)
        try context.save()
        let originalLastModified = entry.lastModified
        let viewModel = DiaryViewModel(
            modelContext: context,
            saveModelContext: { _ in throw TestSaveError.failed }
        )
        var draft = DiaryEditDraft(
            entryID: entry.id,
            content: entry.content,
            mood: entry.mood,
            tags: entry.tags,
            originalAudioURL: entry.audioURL
        )
        draft.content = "重试正文"
        draft.mood = "5"
        draft.tags = ["重试标签"]
        draft.replacePendingRecording(with: replacementAudioURL)

        #expect(!viewModel.commitEditDraft(draft, forEntryID: entry.id))
        #expect(entry.content == "旧正文")
        #expect(entry.mood == "一般")
        #expect(entry.tags == ["旧标签"])
        #expect(entry.audioURL == originalAudioURL)
        #expect(entry.lastModified == originalLastModified)
        #expect(draft.pendingReplacementAudioURL == replacementAudioURL)
        #expect(FileManager.default.fileExists(atPath: originalAudioURL.path))
        #expect(FileManager.default.fileExists(atPath: replacementAudioURL.path))
        #expect(viewModel.errorMessage?.contains("保存日记失败") == true)

        let discardedAudioURL = draft.discardPendingRecording()
        DiaryViewModel.removeRecordingFile(at: discardedAudioURL)
        #expect(FileManager.default.fileExists(atPath: originalAudioURL.path))
        #expect(!FileManager.default.fileExists(atPath: replacementAudioURL.path))
    }

    @MainActor
    @Test func diaryViewModelRejectsMissingReplacementRecordingBeforeMutatingEntry() async throws {
        let context = try makeModelContext()
        let entry = makeDiary(title: "缺失录音", content: "原正文", tags: ["原标签"], mood: "一般")
        context.insert(entry)
        try context.save()
        let viewModel = DiaryViewModel(modelContext: context)
        var draft = DiaryEditDraft(
            entryID: entry.id,
            content: entry.content,
            mood: entry.mood,
            tags: entry.tags,
            originalAudioURL: nil
        )
        draft.content = "不应保存"
        draft.replacePendingRecording(
            with: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("caf")
        )

        #expect(!viewModel.commitEditDraft(draft, forEntryID: entry.id))
        #expect(entry.content == "原正文")
        #expect(entry.audioURL == nil)
        #expect(viewModel.errorMessage == "待保存的录音文件不存在")
    }

    @Test func recordingStateAllowsTranscriptionActionsOnlyWhenStable() async throws {
        #expect(!RecordingState.recording.allowsTranscriptionActions)
        #expect(!RecordingState.processing.allowsTranscriptionActions)
        #expect(RecordingState.idle.allowsTranscriptionActions)
        #expect(RecordingState.finished.allowsTranscriptionActions)
        #expect(RecordingState.error(NSError(domain: "test", code: 1)).allowsTranscriptionActions)
    }

    @Test func recordingStateCompletionPreservesExistingError() async throws {
        let error = NSError(domain: "test", code: 1)

        if case .error = RecordingState.error(error).afterRecognitionCompletion {
            #expect(true)
        } else {
            Issue.record("Expected recognition completion to preserve an existing recording error")
        }

        if case .finished = RecordingState.processing.afterRecognitionCompletion {
            #expect(true)
        } else {
            Issue.record("Expected non-error recognition completion to resolve as finished")
        }
    }

    @Test func onlyActiveRecordingBlocksAReplacementSession() {
        #expect(RecordingState.recording.blocksNewRecordingStart)
        #expect(!RecordingState.processing.blocksNewRecordingStart)
        #expect(!RecordingState.finished.blocksNewRecordingStart)
        #expect(!RecordingState.idle.blocksNewRecordingStart)
    }

    @Test func speechRecognitionSessionGateRejectsOverlapAndLateCallbacks() async throws {
        let gate = SpeechRecognitionSessionGate()
        let firstSessionID = UUID()
        let nextSessionID = UUID()

        #expect(gate.activate(firstSessionID))
        #expect(!gate.activate(nextSessionID))
        #expect(gate.isActive(firstSessionID))

        #expect(gate.invalidate(firstSessionID))
        #expect(!gate.isActive(firstSessionID))
        #expect(gate.activate(nextSessionID))
        #expect(!gate.isActive(firstSessionID))
        #expect(gate.isActive(nextSessionID))
    }

    @MainActor
    @Test func todoViewModelPublishesMutationsOnMainThread() async throws {
        let viewModel = TodoViewModel(
            modelContext: try makeModelContext(),
            notificationScheduler: FakeTodoNotificationScheduler(),
            systemReminderWriter: FakeSystemReminderWriter(),
            reminderModeStore: FakeTodoReminderModeStore(mode: .off)
        )
        var mutationWasPublishedOnMainThread = false
        let cancellable = viewModel.$todoItems
            .dropFirst()
            .sink { _ in
                mutationWasPublishedOnMainThread = Thread.isMainThread
            }

        #expect(viewModel.addTodoItem(title: "Main actor publication"))
        #expect(mutationWasPublishedOnMainThread)
        withExtendedLifetime(cancellable) {}
    }

    @MainActor
    @Test func diaryViewModelCancellationClearsSpeechSessionState() async throws {
        let speechService = FakeSpeechRecognitionService()
        speechService.publishTranscription("未保存转写")
        let viewModel = DiaryViewModel(
            modelContext: try makeModelContext(),
            speechService: speechService
        )

        #expect(viewModel.transcribedText == "未保存转写")
        viewModel.cancelVoiceRecording()

        #expect(speechService.cancelRecordingCallCount == 1)
        #expect(viewModel.transcribedText.isEmpty)
    }

    @MainActor
    @Test func diaryRecordingCleanupRemovesPreviousFileWithoutDeletingReplacement() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("EasyNoteTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let previousURL = directory.appendingPathComponent("previous.caf")
        let replacementURL = directory.appendingPathComponent("replacement.caf")
        try Data([0x01]).write(to: previousURL)
        try Data([0x02]).write(to: replacementURL)

        DiaryViewModel.removeReplacedRecordingFile(previous: previousURL, replacement: replacementURL)

        #expect(!FileManager.default.fileExists(atPath: previousURL.path))
        #expect(FileManager.default.fileExists(atPath: replacementURL.path))
    }

    @MainActor
    @Test func diaryRecordingCleanupKeepsFileWhenReplacementMatchesPrevious() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("EasyNoteTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let recordingURL = directory.appendingPathComponent("recording.caf")
        try Data([0x03]).write(to: recordingURL)

        DiaryViewModel.removeReplacedRecordingFile(previous: recordingURL, replacement: recordingURL)

        #expect(FileManager.default.fileExists(atPath: recordingURL.path))
    }

    @MainActor
    @Test func diaryRecordingCleanupRemovesLegacyM4AFile() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("EasyNoteTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let legacyRecordingURL = directory.appendingPathComponent("recording_legacy.m4a")
        try Data([0x04]).write(to: legacyRecordingURL)

        DiaryViewModel.removeRecordingFile(at: legacyRecordingURL)

        #expect(!FileManager.default.fileExists(atPath: legacyRecordingURL.path))
    }

    @MainActor
    @Test func diaryRecordingDraftCaptureIncludesActiveAndFinishedStates() async throws {
        let error = NSError(domain: "test", code: 1)

        #expect(DiaryViewModel.shouldCaptureVoiceRecordingDraft(isRecording: true, recordingState: .recording))
        #expect(DiaryViewModel.shouldCaptureVoiceRecordingDraft(isRecording: false, recordingState: .finished))
        #expect(!DiaryViewModel.shouldCaptureVoiceRecordingDraft(isRecording: false, recordingState: .idle))
        #expect(!DiaryViewModel.shouldCaptureVoiceRecordingDraft(isRecording: false, recordingState: .processing))
        #expect(!DiaryViewModel.shouldCaptureVoiceRecordingDraft(isRecording: false, recordingState: .error(error)))
    }

    @Test func diaryEntryQuerySearchesTitleContentAndTags() async throws {
        let entries = [
            makeDiary(title: "工作复盘", content: "今天推进了项目", tags: ["工作"]),
            makeDiary(title: "周末", content: "去了公园散步", tags: ["生活", "户外"])
        ]

        #expect(DiaryEntryQuery(searchText: "工作").apply(to: entries).map(\.title) == ["工作复盘"])
        #expect(DiaryEntryQuery(searchText: "公园").apply(to: entries).map(\.title) == ["周末"])
        #expect(DiaryEntryQuery(searchText: "户外").apply(to: entries).map(\.title) == ["周末"])
    }

    @Test func diaryEntryQueryFiltersTagMoodFavoriteAndDateRange() async throws {
        let calendar = Calendar.current
        let june10 = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 10, hour: 9)))
        let june11 = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 11, hour: 12)))
        let june12 = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 12, hour: 18)))
        let entries = [
            makeDiary(title: "工作", tags: ["工作"], mood: "4", creationDate: june10, isFavorite: true),
            makeDiary(title: "生活", tags: ["生活"], mood: "3", creationDate: june11),
            makeDiary(title: "旅行", tags: ["生活", "旅行"], mood: "4", creationDate: june12, isFavorite: true)
        ]

        #expect(DiaryEntryQuery(selectedTag: "旅行").apply(to: entries).map(\.title) == ["旅行"])
        #expect(DiaryEntryQuery(selectedMood: "4").apply(to: entries).map(\.title) == ["旅行", "工作"])
        #expect(DiaryEntryQuery(favoriteOnly: true).apply(to: entries).map(\.title) == ["旅行", "工作"])
        #expect(DiaryEntryQuery(startDate: june11, endDate: june11).apply(to: entries).map(\.title) == ["生活"])
    }

    @Test func diaryEntryQueryIncludesSubsecondEntriesOnEndDate() async throws {
        let calendar = Calendar.current
        let selectedDay = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 11, hour: 12)))
        let lastFractionalSecond = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 6,
            day: 11,
            hour: 23,
            minute: 59,
            second: 59,
            nanosecond: 500_000_000
        )))
        let nextMidnight = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 12)))
        let entries = [
            makeDiary(title: "次日", creationDate: nextMidnight),
            makeDiary(title: "当天最后一秒", creationDate: lastFractionalSecond)
        ]

        #expect(DiaryEntryQuery(startDate: selectedDay, endDate: selectedDay).apply(to: entries).map(\.title) == ["当天最后一秒"])
    }

    @Test func diaryEntryQueryCombinesSearchAndFilters() async throws {
        let entries = [
            makeDiary(title: "项目推进", content: "完成接口设计", tags: ["工作"], mood: "4", isFavorite: true),
            makeDiary(title: "项目阻塞", content: "等待反馈", tags: ["工作"], mood: "2"),
            makeDiary(title: "生活记录", content: "整理房间", tags: ["生活"], mood: "4", isFavorite: true)
        ]
        let query = DiaryEntryQuery(
            searchText: "项目",
            selectedTag: "工作",
            selectedMood: "4",
            favoriteOnly: true
        )

        #expect(query.apply(to: entries).map(\.title) == ["项目推进"])
    }

    @Test func diaryEntryQuerySortsAndEmptyQueryReturnsAllEntries() async throws {
        let calendar = Calendar.current
        let earlier = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 10)))
        let later = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 12)))
        let entries = [
            makeDiary(title: "Beta", creationDate: earlier),
            makeDiary(title: "alpha", creationDate: later)
        ]

        #expect(DiaryEntryQuery().apply(to: entries).map(\.title) == ["alpha", "Beta"])
        #expect(DiaryEntryQuery(sortOption: .dateAsc).apply(to: entries).map(\.title) == ["Beta", "alpha"])
        #expect(DiaryEntryQuery(sortOption: .titleAsc).apply(to: entries).map(\.title) == ["alpha", "Beta"])
        #expect(DiaryEntryQuery(sortOption: .titleDesc).apply(to: entries).map(\.title) == ["Beta", "alpha"])
    }

    @Test func diaryReviewProjectionAggregatesMonthlyCountsFavoritesMoodsAndTags() async throws {
        let calendar = makeGregorianCalendar()
        let june1 = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 9)))
        let june2 = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 2, hour: 9)))
        let may31 = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 31, hour: 9)))
        let entries = [
            makeDiary(title: "六月工作", tags: ["work", "review"], mood: "4", creationDate: june1, isFavorite: true),
            makeDiary(title: "六月生活", tags: ["life", "review"], mood: "3", creationDate: june2),
            makeDiary(title: "五月记录", tags: ["work"], mood: "4", creationDate: may31, isFavorite: true)
        ]

        let projection = DiaryReviewProjection.build(from: entries, calendar: calendar, now: june2)
        let juneSummary = try #require(projection.monthlySummaries.first)

        #expect(projection.totalEntryCount == 3)
        #expect(projection.totalFavoriteCount == 2)
        #expect(projection.totalDistinctTagCount == 3)
        #expect(calendar.component(.month, from: juneSummary.monthStart) == 6)
        #expect(juneSummary.entryCount == 2)
        #expect(juneSummary.favoriteCount == 1)
        let juneMoodCounts = Dictionary(uniqueKeysWithValues: juneSummary.moodDistribution.map { ($0.mood, $0.count) })
        #expect(juneMoodCounts["一般"] == 1)
        #expect(juneMoodCounts["不错"] == 1)
        #expect(juneSummary.topTags == [
            DiaryReviewProjection.TagCount(tag: "review", count: 2),
            DiaryReviewProjection.TagCount(tag: "life", count: 1),
            DiaryReviewProjection.TagCount(tag: "work", count: 1)
        ])
    }

    @Test func diaryReviewProjectionSortsTopTagsByCountThenLocalizedName() async throws {
        let date = try #require(makeGregorianCalendar().date(from: DateComponents(year: 2026, month: 6, day: 10)))
        let entries = [
            makeDiary(title: "A", tags: ["beta", "alpha"], creationDate: date),
            makeDiary(title: "B", tags: ["gamma", "beta"], creationDate: date),
            makeDiary(title: "C", tags: ["alpha", "gamma"], creationDate: date),
            makeDiary(title: "D", tags: ["gamma"], creationDate: date)
        ]

        let projection = DiaryReviewProjection.build(from: entries, calendar: makeGregorianCalendar(), now: date, topLimit: 2)

        #expect(projection.overallTopTags == [
            DiaryReviewProjection.TagCount(tag: "gamma", count: 3),
            DiaryReviewProjection.TagCount(tag: "alpha", count: 2)
        ])
    }

    @Test func diaryReviewProjectionTracksDistinctTagsBeyondTopLimit() async throws {
        let calendar = makeGregorianCalendar()
        let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 10)))
        let entries = [
            makeDiary(title: "A", tags: ["alpha"], creationDate: date),
            makeDiary(title: "B", tags: ["beta"], creationDate: date),
            makeDiary(title: "C", tags: ["gamma"], creationDate: date),
            makeDiary(title: "D", tags: ["delta"], creationDate: date),
            makeDiary(title: "E", tags: ["epsilon"], creationDate: date),
            makeDiary(title: "F", tags: ["zeta"], creationDate: date)
        ]

        let projection = DiaryReviewProjection.build(from: entries, calendar: calendar, now: date, topLimit: 2)

        #expect(projection.totalDistinctTagCount == 6)
        #expect(projection.overallTopTags.count == 2)
    }

    @Test func diaryReviewProjectionCountsMoodDistributionAndRecentFavorites() async throws {
        let calendar = makeGregorianCalendar()
        let earlier = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 10)))
        let later = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 12)))
        let entries = [
            makeDiary(title: "旧收藏", mood: "5", creationDate: earlier, isFavorite: true),
            makeDiary(title: "新收藏", mood: "4", creationDate: later, isFavorite: true),
            makeDiary(title: "普通", mood: "5", creationDate: later)
        ]

        let projection = DiaryReviewProjection.build(from: entries, calendar: calendar, now: later)

        #expect(projection.overallMoodDistribution == [
            DiaryReviewProjection.MoodCount(mood: "很棒", count: 2),
            DiaryReviewProjection.MoodCount(mood: "不错", count: 1)
        ])
        #expect(projection.recentFavorites.map(\.title) == ["新收藏", "旧收藏"])
    }

    @Test func diaryReviewProjectionNormalizesNumericAndLabelMoods() async throws {
        let calendar = makeGregorianCalendar()
        let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 10)))
        let entries = [
            makeDiary(title: "数字心情", mood: "4", creationDate: date),
            makeDiary(title: "标签心情", mood: "不错", creationDate: date),
            makeDiary(title: "带空格数字", mood: " 4 ", creationDate: date),
            makeDiary(title: "自定义心情", mood: "专注", creationDate: date)
        ]

        let projection = DiaryReviewProjection.build(from: entries, calendar: calendar, now: date)

        #expect(projection.overallMoodDistribution == [
            DiaryReviewProjection.MoodCount(mood: "不错", count: 3),
            DiaryReviewProjection.MoodCount(mood: "专注", count: 1)
        ])
    }

    @Test func diaryReviewProjectionReturnsEmptyProjectionForNoEntries() async throws {
        let calendar = makeGregorianCalendar()
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 12)))

        let projection = DiaryReviewProjection.build(from: [], calendar: calendar, now: now)

        #expect(projection.totalEntryCount == 0)
        #expect(projection.totalFavoriteCount == 0)
        #expect(projection.totalDistinctTagCount == 0)
        #expect(projection.monthlySummaries.isEmpty)
        #expect(projection.overallTopTags.isEmpty)
        #expect(projection.overallMoodDistribution.isEmpty)
        #expect(projection.recentFavorites.isEmpty)
        #expect(projection.windowSummaries.allSatisfy { $0.entryCount == 0 && $0.favoriteCount == 0 })
    }

    @Test func diaryReviewProjectionWindowsIncludeTodayAndExcludeOutsideRange() async throws {
        let calendar = makeGregorianCalendar()
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 12, hour: 12)))
        let today = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 12, hour: 23, minute: 59)))
        let sixDaysAgo = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 6, hour: 8)))
        let sevenDaysAgo = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 5, hour: 8)))
        let may31 = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 31, hour: 23)))
        let entries = [
            makeDiary(title: "今天", creationDate: today),
            makeDiary(title: "六天前", creationDate: sixDaysAgo),
            makeDiary(title: "七天前", creationDate: sevenDaysAgo),
            makeDiary(title: "五月末", creationDate: may31)
        ]

        #expect(DiaryReviewProjection.entries(for: .recent7Days, in: entries, calendar: calendar, now: now).map(\.title) == ["今天", "六天前"])
        #expect(DiaryReviewProjection.entries(for: .recent30Days, in: entries, calendar: calendar, now: now).map(\.title) == ["今天", "六天前", "七天前", "五月末"])
        #expect(DiaryReviewProjection.entries(for: .currentMonth, in: entries, calendar: calendar, now: now).map(\.title) == ["今天", "六天前", "七天前"])
    }

    @Test func backupV1RoundTripsThroughJSON() async throws {
        let service = BackupService()
        let exportedAt = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 17, hour: 10)))
        let diaryID = UUID()
        let audioID = UUID()
        let backup = EasyNoteBackupV1(
            version: BackupService.supportedVersion,
            exportedAt: exportedAt,
            diaryEntries: [
                BackupDiaryEntry(
                    id: diaryID,
                    title: "语音日记",
                    content: "今天记录了一段语音",
                    mood: "4",
                    tags: ["生活"],
                    creationDate: exportedAt,
                    lastModified: exportedAt,
                    isFavorite: true,
                    aiSummary: "摘要",
                    audioAssetId: audioID
                )
            ],
            todoItems: [],
            chatSessions: [],
            sessionMessages: [],
            audioAssets: [
                BackupAudioAsset(
                    id: audioID,
                    originalFilename: "recording.caf",
                    pathExtension: "caf",
                    byteCount: 3,
                    data: Data([0x01, 0x02, 0x03])
                )
            ]
        )

        let data = try await service.encodeBackup(backup)
        let decoded = try await service.decodeAndValidateBackup(from: data)

        #expect(decoded == backup)
    }

    @Test func backupRoundTripPreservesFractionalSecondDates() async throws {
        let service = BackupService()
        let date = Date(timeIntervalSince1970: 1_781_694_000.456)
        let diaryID = UUID()
        let backup = EasyNoteBackupV1(
            version: BackupService.supportedVersion,
            exportedAt: date,
            diaryEntries: [
                BackupDiaryEntry(
                    id: diaryID,
                    title: "精确时间",
                    content: "",
                    mood: nil,
                    tags: [],
                    creationDate: date,
                    lastModified: date,
                    isFavorite: false,
                    aiSummary: nil,
                    audioAssetId: nil
                )
            ],
            todoItems: [
                BackupTodoItem(
                    id: UUID(),
                    title: "同秒待办",
                    isCompleted: false,
                    priority: .medium,
                    deadline: date,
                    notes: nil,
                    isRecurring: false,
                    recurringInterval: nil,
                    creationDate: date
                )
            ],
            chatSessions: [],
            sessionMessages: [
                BackupSessionMessage(
                    id: UUID(),
                    content: "同秒消息",
                    isUser: true,
                    timestamp: date,
                    relatedEntryIds: []
                )
            ],
            audioAssets: []
        )

        let data = try await service.encodeBackup(backup)
        let decoded = try await service.decodeAndValidateBackup(from: data)

        #expect(abs(decoded.exportedAt.timeIntervalSince1970 - date.timeIntervalSince1970) < 0.001)
        #expect(abs((decoded.diaryEntries.first?.creationDate.timeIntervalSince1970 ?? 0) - date.timeIntervalSince1970) < 0.001)
        #expect(abs((decoded.todoItems.first?.deadline?.timeIntervalSince1970 ?? 0) - date.timeIntervalSince1970) < 0.001)
        #expect(abs((decoded.sessionMessages.first?.timestamp.timeIntervalSince1970 ?? 0) - date.timeIntervalSince1970) < 0.001)
    }

    @Test func backupExportIncludesCoreModelsAndAudioAsset() async throws {
        let context = try makeModelContext()
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let audioURL = directory.appendingPathComponent("recording.caf")
        try Data([0x0A, 0x0B]).write(to: audioURL)

        let diary = makeDiary(title: "语音日记", content: "正文", tags: ["语音"], isFavorite: true)
        diary.audioURL = audioURL
        let todo = makeTodo(title: "备份待办", deadline: Date())
        let message = SessionMessage(content: "用户消息", isUser: true)
        let session = ChatSession(title: "备份会话")
        session.addMessage(message)

        context.insert(diary)
        context.insert(todo)
        context.insert(message)
        context.insert(session)
        try context.save()

        let backup = try await BackupService(documentsDirectory: directory).exportBackup(from: context)

        #expect(backup.diaryEntries.map(\.title) == ["语音日记"])
        #expect(backup.todoItems.map(\.title) == ["备份待办"])
        #expect(backup.chatSessions.map(\.title) == ["备份会话"])
        #expect(backup.sessionMessages.map(\.content) == ["用户消息"])
        #expect(backup.audioAssets.count == 1)
        #expect(backup.audioAssets.first?.data == Data([0x0A, 0x0B]))
        #expect(backup.diaryEntries.first?.audioAssetId == backup.audioAssets.first?.id)
    }

    @Test func backupExportExcludesOrphanedChatMessages() async throws {
        let context = try makeModelContext()
        let visibleMessage = SessionMessage(content: "可见消息", isUser: true)
        let orphanedMessage = SessionMessage(content: "孤立消息", isUser: false)
        let session = ChatSession(title: "可见会话")
        session.addMessage(visibleMessage)

        context.insert(visibleMessage)
        context.insert(orphanedMessage)
        context.insert(session)
        try context.save()

        let backup = try await BackupService().exportBackup(from: context)

        #expect(backup.chatSessions.map(\.messageIds) == [[visibleMessage.id]])
        #expect(backup.sessionMessages.map(\.content) == ["可见消息"])
    }

    @Test func backupExportNormalizesLegacySharedMessageIDs() throws {
        let sharedMessageID = UUID()
        let duplicateMessageID = UUID()

        let normalizedIDs = BackupService.normalizedMessageIDs(
            for: [[sharedMessageID], [sharedMessageID]],
            makeDuplicateID: { duplicateMessageID }
        )

        #expect(normalizedIDs == [[sharedMessageID], [duplicateMessageID]])
        #expect(Set(normalizedIDs.flatMap { $0 }).count == 2)
    }

    @Test func backupExportSkipsMissingAudioWithoutDroppingDiary() async throws {
        let context = try makeModelContext()
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let diary = makeDiary(title: "缺失录音")
        diary.audioURL = directory.appendingPathComponent("missing.caf")
        context.insert(diary)
        try context.save()

        let backup = try await BackupService(documentsDirectory: directory).exportBackup(from: context)

        #expect(backup.diaryEntries.map(\.title) == ["缺失录音"])
        #expect(backup.diaryEntries.first?.audioAssetId == nil)
        #expect(backup.audioAssets.isEmpty)
    }

    @Test func backupImportRejectsUnsupportedVersionWithoutWriting() async throws {
        let context = try makeModelContext()
        let existing = makeDiary(title: "本地日记")
        context.insert(existing)
        try context.save()

        let backup = EasyNoteBackupV1(
            version: 99,
            exportedAt: Date(),
            diaryEntries: [
                BackupDiaryEntry(
                    id: UUID(),
                    title: "不应导入",
                    content: "",
                    mood: nil,
                    tags: [],
                    creationDate: Date(),
                    lastModified: Date(),
                    isFavorite: false,
                    aiSummary: nil,
                    audioAssetId: nil
                )
            ],
            todoItems: [],
            chatSessions: [],
            sessionMessages: [],
            audioAssets: []
        )

        do {
            _ = try await BackupService().importBackup(backup, into: context)
            Issue.record("Expected unsupported backup version to fail")
        } catch BackupServiceError.unsupportedVersion(99) {
            #expect(true)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        let entries = try context.fetch(FetchDescriptor<DiaryEntry>())
        #expect(entries.map(\.title) == ["本地日记"])
    }

    @Test func backupImportDataRejectsInvalidBase64WithoutWriting() async throws {
        let context = try makeModelContext()
        let existing = makeTodo(title: "本地待办")
        context.insert(existing)
        try context.save()

        let assetID = UUID().uuidString
        let invalidJSON = """
        {
          "audioAssets": [
            {
              "byteCount": 3,
              "data": "not-base64",
              "id": "\(assetID)",
              "originalFilename": "recording.caf",
              "pathExtension": "caf"
            }
          ],
          "chatSessions": [],
          "diaryEntries": [],
          "exportedAt": "2026-06-17T10:00:00Z",
          "sessionMessages": [],
          "todoItems": [],
          "version": 1
        }
        """

        do {
            _ = try await BackupService().importBackupData(Data(invalidJSON.utf8), into: context)
            Issue.record("Expected invalid base64 to fail")
        } catch {
            #expect(true)
        }

        let todos = try context.fetch(FetchDescriptor<TodoItem>())
        #expect(todos.map(\.title) == ["本地待办"])
    }

    @Test func backupImportNormalizesLegacyMessagesSharedAcrossSessions() async throws {
        let context = try makeModelContext()
        let messageID = UUID()
        let backup = EasyNoteBackupV1(
            version: 1,
            exportedAt: Date(),
            diaryEntries: [],
            todoItems: [],
            chatSessions: [
                BackupChatSession(
                    id: UUID(),
                    title: "第一会话",
                    creationDate: Date(),
                    lastModifiedDate: Date(),
                    messageIds: [messageID]
                ),
                BackupChatSession(
                    id: UUID(),
                    title: "第二会话",
                    creationDate: Date(),
                    lastModifiedDate: Date(),
                    messageIds: [messageID]
                )
            ],
            sessionMessages: [
                BackupSessionMessage(
                    id: messageID,
                    content: "不能共享的消息",
                    isUser: true,
                    timestamp: Date(),
                    relatedEntryIds: []
                )
            ],
            audioAssets: []
        )

        _ = try await BackupService().importBackup(backup, into: context)

        let sessions = try context.fetch(FetchDescriptor<ChatSession>())
        let messages = try context.fetch(FetchDescriptor<SessionMessage>())
        #expect(sessions.count == 2)
        #expect(messages.count == 2)
        #expect(Set(sessions.flatMap { $0.messages.map(\.id) }).count == 2)
        #expect(messages.allSatisfy { $0.content == "不能共享的消息" })
    }

    @Test func backupImportUpsertsSameIDAndPreservesUnmentionedLocalRecords() async throws {
        let context = try makeModelContext()
        let diaryID = UUID()
        let localDiary = DiaryEntry(id: diaryID, title: "旧标题")
        let localTodo = makeTodo(title: "保留的本地待办")
        context.insert(localDiary)
        context.insert(localTodo)
        try context.save()

        let backupDate = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 17, hour: 10)))
        let importedTodoID = UUID()
        let backup = EasyNoteBackupV1(
            version: BackupService.supportedVersion,
            exportedAt: backupDate,
            diaryEntries: [
                BackupDiaryEntry(
                    id: diaryID,
                    title: "新标题",
                    content: "导入正文",
                    mood: "5",
                    tags: ["导入"],
                    creationDate: backupDate,
                    lastModified: backupDate,
                    isFavorite: true,
                    aiSummary: "导入摘要",
                    audioAssetId: nil
                )
            ],
            todoItems: [
                BackupTodoItem(
                    id: importedTodoID,
                    title: "导入待办",
                    isCompleted: true,
                    priority: .high,
                    deadline: nil,
                    notes: "导入备注",
                    isRecurring: false,
                    recurringInterval: nil,
                    creationDate: backupDate
                )
            ],
            chatSessions: [],
            sessionMessages: [],
            audioAssets: []
        )

        _ = try await BackupService().importBackup(backup, into: context)

        let diaries = try context.fetch(FetchDescriptor<DiaryEntry>())
        let todos = try context.fetch(FetchDescriptor<TodoItem>())

        #expect(diaries.count == 1)
        #expect(diaries.first?.title == "新标题")
        #expect(diaries.first?.content == "导入正文")
        #expect(Set(todos.map(\.title)) == Set(["保留的本地待办", "导入待办"]))
    }

    @Test func backupImportRestoresAudioAssetToLocalFile() async throws {
        let context = try makeModelContext()
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let audioID = UUID()
        let diaryID = UUID()
        let backupDate = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 17, hour: 10)))
        let backup = EasyNoteBackupV1(
            version: BackupService.supportedVersion,
            exportedAt: backupDate,
            diaryEntries: [
                BackupDiaryEntry(
                    id: diaryID,
                    title: "恢复录音",
                    content: "",
                    mood: nil,
                    tags: [],
                    creationDate: backupDate,
                    lastModified: backupDate,
                    isFavorite: false,
                    aiSummary: nil,
                    audioAssetId: audioID
                )
            ],
            todoItems: [],
            chatSessions: [],
            sessionMessages: [],
            audioAssets: [
                BackupAudioAsset(
                    id: audioID,
                    originalFilename: "recording.caf",
                    pathExtension: "caf",
                    byteCount: 3,
                    data: Data([0x07, 0x08, 0x09])
                )
            ]
        )

        _ = try await BackupService(documentsDirectory: directory).importBackup(backup, into: context)

        let diary = try #require(try context.fetch(FetchDescriptor<DiaryEntry>()).first)
        let restoredURL = try #require(diary.audioURL)

        #expect(restoredURL.lastPathComponent == "restored_recording_\(audioID.uuidString).caf")
        #expect(FileManager.default.fileExists(atPath: restoredURL.path))
        #expect(try Data(contentsOf: restoredURL) == Data([0x07, 0x08, 0x09]))
    }

    @MainActor
    @Test func backupImportOverwritesDeterministicRestoredAudioWhenReimporting() async throws {
        let context = try makeModelContext()
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let audioID = UUID()
        let existingURL = directory.appendingPathComponent("restored_recording_\(audioID.uuidString).caf")
        try Data([0x01]).write(to: existingURL)

        let backupDate = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 17, hour: 10)))
        let backup = EasyNoteBackupV1(
            version: BackupService.supportedVersion,
            exportedAt: backupDate,
            diaryEntries: [
                BackupDiaryEntry(
                    id: UUID(),
                    title: "重复导入录音",
                    content: "",
                    mood: nil,
                    tags: [],
                    creationDate: backupDate,
                    lastModified: backupDate,
                    isFavorite: false,
                    aiSummary: nil,
                    audioAssetId: audioID
                )
            ],
            todoItems: [],
            chatSessions: [],
            sessionMessages: [],
            audioAssets: [
                BackupAudioAsset(
                    id: audioID,
                    originalFilename: "recording.caf",
                    pathExtension: "caf",
                    byteCount: 1,
                    data: Data([0x02])
                )
            ]
        )

        _ = try await BackupService(documentsDirectory: directory).importBackup(backup, into: context)
        let diary = try #require(try context.fetch(FetchDescriptor<DiaryEntry>()).first)
        let newURL = try #require(diary.audioURL)

        #expect(newURL == existingURL)
        #expect(FileManager.default.fileExists(atPath: newURL.path))
        #expect(try Data(contentsOf: newURL) == Data([0x02]))
        #expect(try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("restored_recording_\(audioID.uuidString)") }
            .count == 1)
    }

    @Test func backupImportAllowsBlankSessionTitlesAlreadyCreatedByApp() async throws {
        let context = try makeModelContext()
        let backupDate = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 17, hour: 10)))
        let backup = EasyNoteBackupV1(
            version: BackupService.supportedVersion,
            exportedAt: backupDate,
            diaryEntries: [],
            todoItems: [],
            chatSessions: [
                BackupChatSession(
                    id: UUID(),
                    title: "   ",
                    creationDate: backupDate,
                    lastModifiedDate: backupDate,
                    messageIds: []
                )
            ],
            sessionMessages: [],
            audioAssets: []
        )

        _ = try await BackupService().importBackup(backup, into: context)

        let session = try #require(try context.fetch(FetchDescriptor<ChatSession>()).first)
        #expect(session.title == "   ")
    }

    @Test func backupExportAllowsWhitespaceDiaryTitlesAlreadyCreatedByApp() async throws {
        let context = try makeModelContext()
        let diary = makeDiary(title: "   ")
        context.insert(diary)
        try context.save()

        let backup = try await BackupService().exportBackup(from: context)

        #expect(backup.diaryEntries.map(\.title) == ["   "])
    }

    @Test func backupImportPreservesLocalMessagesMissingFromOlderBackup() async throws {
        let context = try makeModelContext()
        let calendar = Calendar.current
        let earlier = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 17, hour: 10)))
        let later = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 17, hour: 10, second: 1)))
        let sessionID = UUID()
        let importedMessageID = UUID()
        let localMessage = SessionMessage(id: UUID(), content: "本地新增消息", isUser: false, timestamp: later)
        let session = ChatSession(id: sessionID, title: "会话")
        session.addMessage(localMessage)
        session.lastModifiedDate = later
        context.insert(localMessage)
        context.insert(session)
        try context.save()

        let backup = EasyNoteBackupV1(
            version: BackupService.supportedVersion,
            exportedAt: earlier,
            diaryEntries: [],
            todoItems: [],
            chatSessions: [
                BackupChatSession(
                    id: sessionID,
                    title: "会话",
                    creationDate: earlier,
                    lastModifiedDate: earlier,
                    messageIds: [importedMessageID]
                )
            ],
            sessionMessages: [
                BackupSessionMessage(
                    id: importedMessageID,
                    content: "备份消息",
                    isUser: true,
                    timestamp: earlier,
                    relatedEntryIds: []
                )
            ],
            audioAssets: []
        )

        _ = try await BackupService().importBackup(backup, into: context)

        let importedSession = try #require(try context.fetch(FetchDescriptor<ChatSession>()).first)
        #expect(importedSession.messages.count == 2)
        #expect(Set(importedSession.messages.map(\.content)) == Set(["备份消息", "本地新增消息"]))
        #expect(importedSession.lastModifiedDate == later)
    }

    @Test func cloudKitPreflightBlocksCurrentLocalFirstConfiguration() async throws {
        let report = CloudKitSyncPreflight.evaluate(.currentProject)

        #expect(report.isReadyForRealSync == false)
        #expect(report.overallSeverity == .blocked)
        #expect(report.check(withID: "container-id")?.severity == .passed)
        #expect(report.check(withID: "swiftdata-boundary")?.severity == .passed)
        #expect(report.check(withID: "icloud-entitlement")?.severity == .blocked)
        #expect(report.check(withID: "schema-deployment")?.severity == .blocked)
        #expect(report.check(withID: "record-identity")?.severity == .blocked)
        #expect(report.check(withID: "manual-validation")?.severity == .blocked)
    }

    @Test func settingsDependenciesPreserveInjectedCoordinationBoundaries() async throws {
        let scheduler = FakeTodoNotificationScheduler()
        let writer = FakeSystemReminderWriter()
        let reminderModeStore = FakeTodoReminderModeStore(mode: .systemReminderAgent)
        let report = CloudKitSyncPreflight.evaluate(.currentProject)

        let dependencies = SettingsDependencies(
            backupService: BackupService(),
            todoNotificationScheduler: scheduler,
            systemReminderAgent: SystemReminderAgent(),
            systemReminderWriter: writer,
            reminderModeStore: reminderModeStore,
            cloudKitPreflightReport: report
        )

        #expect(dependencies.backupService is BackupService)
        #expect(dependencies.todoNotificationScheduler === scheduler)
        #expect(dependencies.systemReminderAgent is SystemReminderAgent)
        #expect(dependencies.systemReminderWriter === writer)
        #expect(dependencies.reminderModeStore === reminderModeStore)
        #expect(dependencies.cloudKitPreflightReport == report)
    }

    @Test func cloudKitPreflightPassesServiceManagedReadyConfiguration() async throws {
        let configuration = CloudKitSyncPreflight.Configuration(
            expectedContainerIdentifier: CloudKitSyncPreflight.defaultContainerIdentifier,
            serviceContainerIdentifier: CloudKitSyncPreflight.defaultContainerIdentifier,
            entitlementContainerIdentifiers: [CloudKitSyncPreflight.defaultContainerIdentifier],
            hasCloudKitServiceEntitlement: true,
            debugSimulationMode: false,
            swiftDataAutomaticSyncEnabled: false,
            schemaIsDeployed: true,
            conflictPolicyIsDocumented: true,
            recordIdentityRoundTripIsImplemented: true,
            manualValidationIsComplete: true
        )

        let report = CloudKitSyncPreflight.evaluate(configuration)

        #expect(report.isReadyForRealSync)
        #expect(report.overallSeverity == .passed)
        #expect(report.checks.allSatisfy { $0.severity == .passed })
    }

    @Test func cloudKitPreflightBlocksMismatchedContainer() async throws {
        let configuration = CloudKitSyncPreflight.Configuration(
            expectedContainerIdentifier: CloudKitSyncPreflight.defaultContainerIdentifier,
            serviceContainerIdentifier: "iCloud.io.github.zzqDeco.OtherApp",
            entitlementContainerIdentifiers: [CloudKitSyncPreflight.defaultContainerIdentifier],
            hasCloudKitServiceEntitlement: true,
            debugSimulationMode: false,
            swiftDataAutomaticSyncEnabled: false,
            schemaIsDeployed: true,
            conflictPolicyIsDocumented: true,
            recordIdentityRoundTripIsImplemented: true,
            manualValidationIsComplete: true
        )

        let report = CloudKitSyncPreflight.evaluate(configuration)

        #expect(report.isReadyForRealSync == false)
        #expect(report.check(withID: "container-id")?.severity == .blocked)
    }

    private func makeDiary(
        title: String,
        content: String = "",
        tags: [String] = [],
        mood: String? = nil,
        creationDate: Date = Date(),
        isFavorite: Bool = false
    ) -> DiaryEntry {
        let entry = DiaryEntry(title: title, content: content, mood: mood, tags: tags, isFavorite: isFavorite)
        entry.creationDate = creationDate
        entry.lastModified = creationDate
        return entry
    }

    private func makeTodo(
        title: String,
        isCompleted: Bool = false,
        priority: TodoItem.PriorityLevel = .medium,
        deadline: Date? = nil,
        notes: String? = nil,
        isRecurring: Bool = false,
        recurringInterval: String? = nil
    ) -> TodoItem {
        TodoItem(
            title: title,
            isCompleted: isCompleted,
            priority: priority,
            deadline: deadline,
            notes: notes,
            isRecurring: isRecurring,
            recurringInterval: recurringInterval
        )
    }

    private func makeModelContext() throws -> ModelContext {
        let schema = Schema([
            DiaryEntry.self,
            TodoItem.self,
            ChatSession.self,
            SessionMessage.self
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("EasyNoteTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeGregorianCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func publisherFailure<Output>(_ publisher: AnyPublisher<Output, OpenAIError>) async -> OpenAIError? {
        let box = CancellableBox()

        return await withCheckedContinuation { continuation in
            box.cancellable = publisher.sink(
                receiveCompletion: { completion in
                    defer { box.cancellable = nil }
                    switch completion {
                    case .failure(let error):
                        continuation.resume(returning: error)
                    case .finished:
                        continuation.resume(returning: nil)
                    }
                },
                receiveValue: { _ in }
            )
        }
    }

    private final class CancellableBox {
        var cancellable: AnyCancellable?
    }

    private final class FakeTodoNotificationScheduler: TodoNotificationSchedulingProviding, @unchecked Sendable {
        private let authorizationStatusSubject = CurrentValueSubject<TodoNotificationAuthorizationStatus, Never>(.authorized)
        private(set) var synchronizedTodos: [TodoItem] = []
        private(set) var reconciledTodoIDs: [[UUID]] = []
        private(set) var canceledTodoIDs: [UUID] = []
        private(set) var didCancelAll = false
        var requestAuthorizationResult = true
        var reconcileError: Error?

        var authorizationStatusPublisher: AnyPublisher<TodoNotificationAuthorizationStatus, Never> {
            authorizationStatusSubject.eraseToAnyPublisher()
        }

        func refreshAuthorizationStatus() async -> TodoNotificationAuthorizationStatus {
            .authorized
        }

        func requestAuthorization() async throws {
            if !requestAuthorizationResult {
                throw TodoNotificationError.authorizationDenied
            }
        }

        func synchronizeNotification(for todo: TodoItem) async throws {
            synchronizedTodos.append(todo)
        }

        func reconcileNotifications(for todos: [TodoItem]) async throws {
            reconciledTodoIDs.append(todos.map(\.id))
            if let reconcileError {
                throw reconcileError
            }
        }

        func cancelNotification(forTodoID id: UUID) async {
            canceledTodoIDs.append(id)
        }

        func cancelAllTodoNotifications() async {
            didCancelAll = true
        }

        func reset() {
            synchronizedTodos = []
            reconciledTodoIDs = []
            canceledTodoIDs = []
            didCancelAll = false
            reconcileError = nil
        }
    }

    private final class FakeSystemReminderWriter: SystemReminderWritingProviding, @unchecked Sendable {
        private let authorizationStatusSubject = CurrentValueSubject<SystemReminderAuthorizationStatus, Never>(.fullAccess)
        private(set) var appliedProposals: [SystemReminderProposal] = []
        private(set) var completedTodoIDs: [UUID] = []
        private(set) var removedTodoIDs: [UUID] = []
        var applyResult: Result<SystemReminderWriteResult, SystemReminderError> = .success(.created)
        var completeResult: Result<Void, SystemReminderError> = .success(())
        var removeResult: Result<Void, SystemReminderError> = .success(())

        var authorizationStatusPublisher: AnyPublisher<SystemReminderAuthorizationStatus, Never> {
            authorizationStatusSubject.eraseToAnyPublisher()
        }

        func refreshAuthorizationStatus() async -> SystemReminderAuthorizationStatus {
            .fullAccess
        }

        func requestAuthorization() async throws {}

        func applyProposal(_ proposal: SystemReminderProposal) async throws -> SystemReminderWriteResult {
            appliedProposals.append(proposal)
            return try applyResult.get()
        }

        func completeReminder(forTodoID id: UUID) async throws {
            completedTodoIDs.append(id)
            try completeResult.get()
        }

        func removeReminder(forTodoID id: UUID) async throws {
            removedTodoIDs.append(id)
            try removeResult.get()
        }

        func reset() {
            appliedProposals = []
            completedTodoIDs = []
            removedTodoIDs = []
            applyResult = .success(.created)
            completeResult = .success(())
            removeResult = .success(())
        }
    }

    private final class FakeTodoReminderModeStore: TodoReminderModeProviding {
        var currentMode: TodoReminderMode
        var systemRemindersMayExist: Bool

        init(mode: TodoReminderMode, systemRemindersMayExist: Bool = false) {
            self.currentMode = mode
            self.systemRemindersMayExist = systemRemindersMayExist
        }
    }

    private enum TestSaveError: Error {
        case failed
    }

    private final class FakeOpenAIService: OpenAIServiceProviding {
        var apiKey: String
        private let processingSubject = CurrentValueSubject<Bool, Never>(false)
        private(set) var generateSummaryCallCount = 0

        init(apiKey: String) {
            self.apiKey = apiKey
        }

        var isProcessingPublisher: AnyPublisher<Bool, Never> {
            processingSubject.eraseToAnyPublisher()
        }

        func generateSummary(from text: String) -> AnyPublisher<String, OpenAIError> {
            generateSummaryCallCount += 1
            return Just("fake summary")
                .setFailureType(to: OpenAIError.self)
                .eraseToAnyPublisher()
        }

        func refineTranscription(text: String) -> AnyPublisher<String, OpenAIError> {
            Just(text)
                .setFailureType(to: OpenAIError.self)
                .eraseToAnyPublisher()
        }

        func analyzeDiaryContent(text: String) -> AnyPublisher<(moods: [String], tags: [String]), OpenAIError> {
            Just((moods: ["平静"], tags: ["测试"]))
                .setFailureType(to: OpenAIError.self)
                .eraseToAnyPublisher()
        }

        func expandText(text: String) -> AnyPublisher<String, OpenAIError> {
            Just(text)
                .setFailureType(to: OpenAIError.self)
                .eraseToAnyPublisher()
        }

        func summarizeText(text: String) -> AnyPublisher<String, OpenAIError> {
            Just(text)
                .setFailureType(to: OpenAIError.self)
                .eraseToAnyPublisher()
        }

        func chat(prompt: String) async throws -> String {
            "fake response"
        }

        func generateRecommendations(from diaryContent: String) -> AnyPublisher<(recommendations: [String], todos: [String]), OpenAIError> {
            Just((recommendations: ["散步"], todos: ["复盘"]))
                .setFailureType(to: OpenAIError.self)
                .eraseToAnyPublisher()
        }
    }

    private final class FakeSpeechRecognitionService: SpeechRecognitionProviding {
        private let transcribedTextSubject = CurrentValueSubject<String, Never>("")
        private let recordingStateSubject = CurrentValueSubject<RecordingState, Never>(.idle)
        private let isRecordingSubject = CurrentValueSubject<Bool, Never>(false)
        private let speechPermissionSubject = CurrentValueSubject<SpeechPermissionStatus, Never>(.authorized)
        private let microphonePermissionSubject = CurrentValueSubject<MicrophonePermissionStatus, Never>(.granted)
        private(set) var cancelRecordingCallCount = 0

        var transcribedTextPublisher: AnyPublisher<String, Never> {
            transcribedTextSubject.eraseToAnyPublisher()
        }

        var recordingStatePublisher: AnyPublisher<RecordingState, Never> {
            recordingStateSubject.eraseToAnyPublisher()
        }

        var isRecordingPublisher: AnyPublisher<Bool, Never> {
            isRecordingSubject.eraseToAnyPublisher()
        }

        var speechPermissionStatusPublisher: AnyPublisher<SpeechPermissionStatus, Never> {
            speechPermissionSubject.eraseToAnyPublisher()
        }

        var microphonePermissionStatusPublisher: AnyPublisher<MicrophonePermissionStatus, Never> {
            microphonePermissionSubject.eraseToAnyPublisher()
        }

        func requestPermissions(completion: ((Bool) -> Void)?) {
            completion?(true)
        }

        func startRecording() throws {}

        func stopRecording() throws {}

        func cancelRecording() {
            cancelRecordingCallCount += 1
            transcribedTextSubject.send("")
            recordingStateSubject.send(.idle)
            isRecordingSubject.send(false)
        }

        func saveRecordingWithTranscription() -> (audioURL: URL?, transcription: String) {
            (nil, transcribedTextSubject.value)
        }

        func publishTranscription(_ text: String) {
            transcribedTextSubject.send(text)
        }
    }

    private final class FakeCloudKitDiarySyncService: CloudKitDiarySyncProviding {
        func syncDiaryEntries(entries: [DiaryEntry]) -> AnyPublisher<Void, Error> {
            Just(())
                .setFailureType(to: Error.self)
                .eraseToAnyPublisher()
        }

        func fetchDiaryEntries() -> AnyPublisher<[DiaryEntry], Error> {
            Just([])
                .setFailureType(to: Error.self)
                .eraseToAnyPublisher()
        }
    }

}
