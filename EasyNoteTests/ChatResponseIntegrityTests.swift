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

    @Test func localDiarySearchPreservesStopWordsInsideRealTerms() {
        let entry = makeDiarySnapshot(title: "中国旅行与请假安排", content: "参观博物馆")

        #expect(LocalDiaryQueryAnalyzer.matchingEntries(for: "中国", in: [entry]).map(\.id) == [entry.id])
        #expect(LocalDiaryQueryAnalyzer.matchingEntries(for: "请假", in: [entry]).map(\.id) == [entry.id])
        #expect(LocalDiaryQueryAnalyzer.matchingEntries(
            for: "请帮我查找关于中国的日记",
            in: [entry]
        ).map(\.id) == [entry.id])
    }

    @Test func localDiarySearchStripsNotebookCommandSuffixes() {
        let project = makeDiarySnapshot(title: "项目", content: "完成第一阶段")
        let unrelated = makeDiarySnapshot(title: "旅行", content: "去了杭州")

        #expect(LocalDiaryQueryAnalyzer.matchingEntries(
            for: "查找包含项目的笔记",
            in: [unrelated, project]
        ).map(\.id) == [project.id])
    }

    @Test func localRecentSummaryAppliesTopicBeforeDateWindow() {
        let project = makeDiarySnapshot(
            title: "项目复盘",
            content: "完成第一阶段",
            creationDate: Date(timeIntervalSince1970: 100)
        )
        let unrelated = makeDiarySnapshot(
            title: "旅行",
            content: "去了杭州",
            creationDate: Date(timeIntervalSince1970: 200)
        )

        let result = LocalDiaryQueryAnalyzer.analyze(
            query: "最近关于项目的日记",
            entries: [unrelated, project]
        )

        #expect(result?.relatedEntryIDs == [project.id])
        #expect(result?.message.contains("项目复盘") == true)
        #expect(result?.message.contains("旅行") == false)
    }

    @Test func localRecentSummaryStripsConnectorAfterCommandPrefix() {
        let project = makeDiarySnapshot(title: "项目复盘", content: "完成第一阶段")
        let unrelated = makeDiarySnapshot(title: "旅行", content: "去了杭州")

        let result = LocalDiaryQueryAnalyzer.analyze(
            query: "最近的项目日记",
            entries: [unrelated, project]
        )

        #expect(result?.relatedEntryIDs == [project.id])
        #expect(result?.message.contains("项目复盘") == true)
        #expect(result?.message.contains("旅行") == false)
    }

    @Test func localMoodSummaryAppliesTopicBeforeCounting() {
        let project = makeDiarySnapshot(title: "项目复盘", content: "完成第一阶段", mood: "满足")
        let unrelated = makeDiarySnapshot(title: "旅行", content: "遇到延误", mood: "焦虑")

        let result = LocalDiaryQueryAnalyzer.analyze(
            query: "项目相关的心情",
            entries: [unrelated, project]
        )

        #expect(result?.relatedEntryIDs == [project.id])
        #expect(result?.message.contains("满足：1 条记录") == true)
        #expect(result?.message.contains("焦虑") == false)
    }

    @Test func localMoodSummaryMatchesMoodMetadata() {
        let happy = makeDiarySnapshot(title: "周末", content: "去公园散步", mood: "开心")
        let calm = makeDiarySnapshot(title: "读书", content: "读完一章", mood: "平静")

        let result = LocalDiaryQueryAnalyzer.analyze(
            query: "开心的心情",
            entries: [calm, happy]
        )

        #expect(result?.relatedEntryIDs == [happy.id])
        #expect(result?.message.contains("开心：1 条记录") == true)
        #expect(result?.message.contains("平静") == false)
    }

    @Test func builtInBroadSummaryPromptsRemainUnscoped() {
        let first = makeDiarySnapshot(
            title: "项目复盘",
            content: "完成第一阶段",
            mood: "满足",
            creationDate: Date(timeIntervalSince1970: 100)
        )
        let second = makeDiarySnapshot(
            title: "旅行",
            content: "去了杭州",
            mood: "开心",
            creationDate: Date(timeIntervalSince1970: 200)
        )

        let recent = LocalDiaryQueryAnalyzer.analyze(
            query: "最近写了哪些日记？",
            entries: [first, second]
        )
        let moods = LocalDiaryQueryAnalyzer.analyze(
            query: "我的笔记中提到过哪些心情？",
            entries: [first, second]
        )

        #expect(recent?.relatedEntryIDs == [second.id, first.id])
        #expect(Set(moods?.relatedEntryIDs ?? []) == Set([first.id, second.id]))
        #expect(moods?.message.contains("满足：1 条记录") == true)
        #expect(moods?.message.contains("开心：1 条记录") == true)
    }

    @Test func naturalBroadMoodPromptsRemainUnscoped() {
        let first = makeDiarySnapshot(title: "项目复盘", content: "完成第一阶段", mood: "满足")
        let second = makeDiarySnapshot(title: "旅行", content: "去了杭州", mood: "开心")

        for query in ["我最近心情如何", "我的心情怎么样"] {
            let result = LocalDiaryQueryAnalyzer.analyze(query: query, entries: [first, second])

            #expect(Set(result?.relatedEntryIDs ?? []) == Set([first.id, second.id]))
            #expect(result?.message.contains("满足：1 条记录") == true)
            #expect(result?.message.contains("开心：1 条记录") == true)
        }
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

    @Test func switchingSessionsPreservesRetryableFailure() async throws {
        let context = try makeModelContext()
        let viewModel = ChatSessionViewModel(modelContext: context)
        let firstSession = try #require(viewModel.currentSession)
        let provider = ImmediateChatProvider(result: .failure(ChatProviderTestError.failed))

        #expect(viewModel.submitChatRequest(
            makeRequestContext(sessionID: firstSession.id, query: "无本地匹配"),
            provider: provider
        ))
        await viewModel.waitForPendingChatRequests()
        let failure = try #require(viewModel.chatRequestFailure(forSessionID: firstSession.id))

        let secondSession = try #require(viewModel.createNewSession(title: "第二会话"))
        viewModel.switchToSession(firstSession)
        viewModel.switchToSession(secondSession)

        #expect(viewModel.chatRequestFailure(forSessionID: firstSession.id) == failure)
    }

    @Test func cancellingRetryBySwitchingSessionsPreservesFailure() async throws {
        let context = try makeModelContext()
        let viewModel = ChatSessionViewModel(modelContext: context)
        let firstSession = try #require(viewModel.currentSession)
        let failingProvider = ImmediateChatProvider(result: .failure(ChatProviderTestError.failed))

        #expect(viewModel.submitChatRequest(
            makeRequestContext(sessionID: firstSession.id, query: "无本地匹配"),
            provider: failingProvider
        ))
        await viewModel.waitForPendingChatRequests()
        _ = try #require(viewModel.chatRequestFailure(forSessionID: firstSession.id))

        let retryProvider = ControllableChatProvider()
        #expect(viewModel.retryFailedChatRequest(forSessionID: firstSession.id, provider: retryProvider))
        await retryProvider.waitUntilRequestStarted()
        let secondSession = try #require(viewModel.createNewSession(title: "第二会话"))
        retryProvider.resumeNext(with: .success("取消后的回复"))
        await settleTasks()

        let retainedFailure = try #require(viewModel.chatRequestFailure(forSessionID: firstSession.id))
        #expect(retainedFailure.context.userQuery == "无本地匹配")
        #expect(retainedFailure.userMessageWasSaved)
        #expect(firstSession.messages.map(\.content) == ["无本地匹配"])
        #expect(viewModel.currentSession?.id == secondSession.id)
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

    @Test func failedSessionDeletionKeepsInFlightRequest() async throws {
        let context = try makeModelContext()
        var shouldFailSave = false
        let viewModel = ChatSessionViewModel(
            modelContext: context,
            saveAction: { modelContext in
                if shouldFailSave { throw ChatProviderTestError.failed }
                try modelContext.save()
            }
        )
        let session = try #require(viewModel.currentSession)
        let provider = ControllableChatProvider()

        #expect(viewModel.submitChatRequest(
            makeRequestContext(sessionID: session.id, query: "项目"),
            provider: provider
        ))
        await provider.waitUntilRequestStarted()
        shouldFailSave = true
        #expect(!viewModel.deleteSession(session))
        #expect(viewModel.isProcessingChatRequest(forSessionID: session.id))

        shouldFailSave = false
        provider.resumeNext(with: .success("继续完成的回复"))
        await viewModel.waitForPendingChatRequests()

        #expect(viewModel.session(withID: session.id) != nil)
        #expect(session.messages.map(\.content) == ["项目", "继续完成的回复"])
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
        var shouldFailSave = true
        let viewModel = ChatSessionViewModel(modelContext: context) { modelContext in
            if shouldFailSave { throw ChatProviderTestError.failed }
            try modelContext.save()
        }
        let provider = ImmediateChatProvider(result: .success("不应生成"))
        let request = makeRequestContext(sessionID: existingSession.id, query: "保存失败")

        #expect(!viewModel.submitChatRequest(request, provider: provider))
        #expect(provider.callCount == 0)
        #expect(viewModel.chatRequestFailure(forSessionID: existingSession.id)?.message.contains("保存会话失败") == true)
        #expect(existingSession.messages.isEmpty)

        shouldFailSave = false
        #expect(viewModel.retryFailedChatRequest(forSessionID: existingSession.id, provider: provider))
        await viewModel.waitForPendingChatRequests()

        #expect(provider.callCount == 1)
        #expect(existingSession.messages.map(\.content) == ["保存失败", "不应生成"])
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

    private func makeDiarySnapshot(
        title: String,
        content: String,
        mood: String? = nil,
        tags: [String] = [],
        creationDate: Date = Date(timeIntervalSince1970: 100)
    ) -> ChatDiaryEntrySnapshot {
        ChatDiaryEntrySnapshot(
            id: UUID(),
            title: title,
            content: content,
            mood: mood,
            tags: tags,
            creationDate: creationDate
        )
    }

    private func settleTasks() async {
        try? await Task.sleep(nanoseconds: 50_000_000)
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
    private var requestStartWaiters: [CheckedContinuation<Void, Never>] = []

    func chat(prompt: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            continuations.append(continuation)
            let waiters = requestStartWaiters
            requestStartWaiters.removeAll()
            lock.unlock()
            waiters.forEach { $0.resume() }
        }
    }

    func resumeNext(with result: Result<String, Error>) {
        lock.lock()
        let continuation = continuations.isEmpty ? nil : continuations.removeFirst()
        lock.unlock()
        continuation?.resume(with: result)
    }

    func waitUntilRequestStarted() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if continuations.isEmpty {
                requestStartWaiters.append(continuation)
                lock.unlock()
            } else {
                lock.unlock()
                continuation.resume()
            }
        }
    }
}
