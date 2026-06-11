//
//  EasyNoteTests.swift
//  EasyNoteTests
//
//  Created by 赵子谦 on 2025/3/1.
//

import Testing
import Foundation
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

}
