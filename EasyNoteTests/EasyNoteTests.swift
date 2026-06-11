//
//  EasyNoteTests.swift
//  EasyNoteTests
//
//  Created by 赵子谦 on 2025/3/1.
//

import Testing
import Foundation
import Combine
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
        let defaults = UserDefaults.standard
        let previousKey = defaults.string(forKey: "openai_api_key")
        defaults.removeObject(forKey: "openai_api_key")
        defer {
            if let previousKey {
                defaults.set(previousKey, forKey: "openai_api_key")
            } else {
                defaults.removeObject(forKey: "openai_api_key")
            }
        }

        let error = await publisherFailure(OpenAIService().generateSummary(from: "测试内容"))

        guard case let .apiError(message) = try #require(error) else {
            Issue.record("Expected empty API key to produce OpenAIError.apiError")
            return
        }
        #expect(message == "请在设置中添加DeepSeek API密钥后再使用AI功能")
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

}
