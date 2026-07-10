import Foundation
import SwiftData
import Testing
@testable import EasyNote

@MainActor
struct ChatResponseIntegrityTests {
    @Test func providerFailureUsesOnlyMatchingLocalDiaryFacts() async throws {
        let entryID = UUID()
        let context = makeRequestContext(
            query: "项目",
            entries: [
                ChatDiaryEntrySnapshot(
                    id: entryID,
                    title: "项目记录",
                    content: "完成第一阶段",
                    mood: "不错",
                    tags: ["工作"],
                    creationDate: Date(timeIntervalSince1970: 100)
                )
            ]
        )
        let provider = ImmediateChatProvider(result: .failure(ChatProviderTestError.failed))

        let outcome = await ChatResponseGenerator.generate(context: context, provider: provider)

        guard case .local(let result) = outcome else {
            Issue.record("Expected a fact-based local fallback")
            return
        }
        #expect(result.relatedEntryIDs == [entryID])
        #expect(result.message.contains("本地结果"))
        #expect(result.message.contains("项目记录"))
        #expect(result.message.contains("完成第一阶段"))
        #expect(!result.message.contains("家人或朋友"))
    }

    @Test func providerFailureWithoutMatchingFactsReturnsRetryableFailure() async throws {
        let context = makeRequestContext(
            query: "不存在的主题",
            entries: [makeDiarySnapshot(title: "旅行", content: "去了杭州")]
        )
        let provider = ImmediateChatProvider(result: .failure(ChatProviderTestError.failed))

        let outcome = await ChatResponseGenerator.generate(context: context, provider: provider)

        guard case .failure(let message) = outcome else {
            Issue.record("Expected a visible failure without fabricated content")
            return
        }
        #expect(message.contains("没有找到"))
    }

    @Test func emptyKeyFailsClosedWithoutCallingProvider() async throws {
        let provider = ImmediateChatProvider(apiKey: "", result: .success("不应调用"))
        let outcome = await ChatResponseGenerator.generate(
            context: makeRequestContext(query: "最近"),
            provider: provider
        )

        guard case .failure(let message) = outcome else {
            Issue.record("Expected missing-key failure")
            return
        }
        #expect(message.contains("API 密钥"))
        #expect(provider.callCount == 0)
    }

    @Test func responseIsPersistedToCapturedSessionRatherThanCurrentSession() async throws {
        let context = try makeModelContext()
        let viewModel = ChatSessionViewModel(modelContext: context)
        let firstSession = try #require(viewModel.currentSession)
        let secondSession = try #require(viewModel.createNewSession(title: "第二会话"))
        viewModel.switchToSession(firstSession)
        let provider = ControllableChatProvider()
        let request = makeRequestContext(sessionID: firstSession.id, query: "项目")

        #expect(viewModel.submitChatRequest(request, provider: provider))
        await provider.waitUntilRequestStarted()
        viewModel.currentSession = secondSession
        provider.resumeNext(with: .success("第一会话回复"))
        await viewModel.waitForPendingChatRequests()

        #expect(firstSession.messages.map(\.content) == ["项目", "第一会话回复"])
        #expect(secondSession.messages.isEmpty)
    }

    @Test func switchingSessionCancelsStaleResponse() async throws {
        let context = try makeModelContext()
        let viewModel = ChatSessionViewModel(modelContext: context)
        let firstSession = try #require(viewModel.currentSession)
        let secondSession = try #require(viewModel.createNewSession(title: "第二会话"))
        viewModel.switchToSession(firstSession)
        let provider = ControllableChatProvider()
        let request = makeRequestContext(sessionID: firstSession.id, query: "项目")

        #expect(viewModel.submitChatRequest(request, provider: provider))
        await provider.waitUntilRequestStarted()
        viewModel.switchToSession(secondSession)
        provider.resumeNext(with: .success("过期回复"))
        await settleTasks()

        #expect(firstSession.messages.map(\.content) == ["项目"])
        #expect(secondSession.messages.isEmpty)
        #expect(!viewModel.isProcessingChatRequest(forSessionID: firstSession.id))
    }

    @Test func deletingSessionCancelsStaleResponse() async throws {
        let context = try makeModelContext()
        let viewModel = ChatSessionViewModel(modelContext: context)
        let session = try #require(viewModel.currentSession)
        let provider = ControllableChatProvider()
        let request = makeRequestContext(sessionID: session.id, query: "项目")

        #expect(viewModel.submitChatRequest(request, provider: provider))
        await provider.waitUntilRequestStarted()
        #expect(viewModel.deleteSession(session))
        provider.resumeNext(with: .success("删除后的回复"))
        await settleTasks()

        #expect(viewModel.session(withID: session.id) == nil)
        #expect(!viewModel.isProcessingChatRequest(forSessionID: session.id))
    }

    @Test func concurrentRequestsRemainBoundToTheirOwnSessions() async throws {
        let context = try makeModelContext()
        let viewModel = ChatSessionViewModel(modelContext: context)
        let firstSession = try #require(viewModel.currentSession)
        let secondSession = try #require(viewModel.createNewSession(title: "第二会话"))
        let firstProvider = ControllableChatProvider()
        let secondProvider = ControllableChatProvider()

        #expect(viewModel.submitChatRequest(
            makeRequestContext(sessionID: firstSession.id, query: "第一"),
            provider: firstProvider
        ))
        #expect(viewModel.submitChatRequest(
            makeRequestContext(sessionID: secondSession.id, query: "第二"),
            provider: secondProvider
        ))

        await firstProvider.waitUntilRequestStarted()
        await secondProvider.waitUntilRequestStarted()
        secondProvider.resumeNext(with: .success("第二回复"))
        firstProvider.resumeNext(with: .success("第一回复"))
        await viewModel.waitForPendingChatRequests()

        #expect(firstSession.messages.map(\.content) == ["第一", "第一回复"])
        #expect(secondSession.messages.map(\.content) == ["第二", "第二回复"])
    }

    @Test func failedUserMessageSaveDoesNotStartProviderRequest() async throws {
        let context = try makeModelContext()
        let existingSession = ChatSession(title: "已有会话")
        context.insert(existingSession)
        try context.save()
        let viewModel = ChatSessionViewModel(
            modelContext: context,
            saveAction: { _ in throw ChatProviderTestError.failed }
        )
        let provider = ImmediateChatProvider(result: .success("不应生成"))
        let request = makeRequestContext(sessionID: existingSession.id, query: "保存失败")

        #expect(!viewModel.submitChatRequest(request, provider: provider))
        #expect(provider.callCount == 0)
        #expect(viewModel.chatRequestFailure(forSessionID: existingSession.id)?.message.contains("保存会话失败") == true)
        #expect(existingSession.messages.isEmpty)
    }

    @Test func loadedSessionMessagesAreNormalizedChronologically() async throws {
        let context = try makeModelContext()
        let session = ChatSession(title: "乱序会话")
        let later = SessionMessage(
            content: "稍后",
            isUser: false,
            timestamp: Date(timeIntervalSince1970: 200)
        )
        let earlier = SessionMessage(
            content: "较早",
            isUser: true,
            timestamp: Date(timeIntervalSince1970: 100)
        )
        context.insert(session)
        context.insert(later)
        context.insert(earlier)
        session.messages = [later, earlier]
        try context.save()

        _ = ChatSessionViewModel(modelContext: context)

        #expect(session.messages.map(\.content) == ["较早", "稍后"])
    }

    private func makeModelContext() throws -> ModelContext {
        let schema = Schema([DiaryEntry.self, TodoItem.self, ChatSession.self, SessionMessage.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    private func makeRequestContext(
        sessionID: UUID = UUID(),
        query: String,
        entries: [ChatDiaryEntrySnapshot] = []
    ) -> ChatRequestContext {
        ChatRequestContext(
            requestID: UUID(),
            sessionID: sessionID,
            userQuery: query,
            relatedEntryIDs: LocalDiaryQueryAnalyzer.matchingEntries(for: query, in: entries).map(\.id),
            conversationHistory: [],
            diaryEntries: entries
        )
    }

    private func makeDiarySnapshot(title: String, content: String) -> ChatDiaryEntrySnapshot {
        ChatDiaryEntrySnapshot(
            id: UUID(),
            title: title,
            content: content,
            mood: nil,
            tags: [],
            creationDate: Date(timeIntervalSince1970: 100)
        )
    }

    private func settleTasks() async {
        for _ in 0..<10 {
            await Task.yield()
        }
    }
}

private enum ChatProviderTestError: Error {
    case failed
}

private final class ImmediateChatProvider: ChatResponseProviding {
    var apiKey: String
    private let result: Result<String, Error>
    private(set) var callCount = 0

    init(apiKey: String = "test-key", result: Result<String, Error>) {
        self.apiKey = apiKey
        self.result = result
    }

    func chat(prompt: String) async throws -> String {
        callCount += 1
        return try result.get()
    }
}

private final class ControllableChatProvider: ChatResponseProviding, @unchecked Sendable {
    var apiKey = "test-key"
    private let lock = NSLock()
    private var continuations: [CheckedContinuation<String, Error>] = []

    func chat(prompt: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            continuations.append(continuation)
            lock.unlock()
        }
    }

    func resumeNext(with result: Result<String, Error>) {
        lock.lock()
        let continuation = continuations.isEmpty ? nil : continuations.removeFirst()
        lock.unlock()
        continuation?.resume(with: result)
    }

    func waitUntilRequestStarted() async {
        for _ in 0..<100 {
            if hasPendingRequest {
                return
            }
            await Task.yield()
        }
        Issue.record("Chat provider request did not start")
    }

    private var hasPendingRequest: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !continuations.isEmpty
    }
}
