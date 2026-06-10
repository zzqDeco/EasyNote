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

}
