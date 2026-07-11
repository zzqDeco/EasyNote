import Foundation
import SwiftData
import Combine
import SwiftUI

@MainActor
final class ChatSessionViewModel: ObservableObject {
    // 模型上下文
    private var modelContext: ModelContext
    
    // 会话数据
    @Published var sessions: [ChatSession] = []
    @Published var currentSession: ChatSession?
    @Published var isLoadingMessages = false
    @Published var errorMessage: String?
    @Published private(set) var pendingChatSessionIDs: Set<UUID> = []
    @Published private(set) var chatRequestFailures: [UUID: ChatRequestFailure] = [:]
    private var cancellables = Set<AnyCancellable>()
    private var chatRequestTasks: [UUID: Task<Void, Never>] = [:]
    private var chatRequestSessions: [UUID: UUID] = [:]
    private let saveAction: (ModelContext) throws -> Void
    
    // MARK: - 初始化方法
    
    init(
        modelContext: ModelContext?,
        saveAction: @escaping (ModelContext) throws -> Void = { try $0.save() }
    ) {
        self.saveAction = saveAction
        if let context = modelContext {
            self.modelContext = context
        } else {
            // 如果没有提供ModelContext，创建一个内存中的临时ModelContext
            do {
                let schema = Schema([ChatSession.self, SessionMessage.self])
                let config = ModelConfiguration(isStoredInMemoryOnly: true)
                let container = try ModelContainer(for: schema, configurations: [config])
                self.modelContext = ModelContext(container)
            } catch {
                fatalError("无法创建ModelContext，应用程序无法继续: \(error)")
            }
        }
        // 加载所有会话
        loadSessions()

        NotificationCenter.default.publisher(for: .easyNoteBackupDidImport)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.loadSessions()
                }
            }
            .store(in: &cancellables)
    }

    deinit {
        chatRequestTasks.values.forEach { $0.cancel() }
    }

    func waitForPendingChatRequests() async {
        let tasks = Array(chatRequestTasks.values)
        for task in tasks {
            await task.value
        }
    }
    
    // MARK: - 会话管理
    
    // 加载所有会话
    func loadSessions() {
        isLoadingMessages = true
        
        do {
            let descriptor = FetchDescriptor<ChatSession>(sortBy: [SortDescriptor(\.lastModifiedDate, order: .reverse)])
            let fetchedSessions = try modelContext.fetch(descriptor)
            fetchedSessions.forEach(normalizeMessageOrder)
            
            sessions = fetchedSessions

            if sessions.isEmpty {
                _ = createNewSession()
            } else if currentSession == nil {
                currentSession = sessions.first
            }
            isLoadingMessages = false
        } catch {
            errorMessage = "加载会话失败: \(error.localizedDescription)"
            isLoadingMessages = false

            if sessions.isEmpty {
                _ = createNewSession()
            }
        }
    }
    
    // 创建新会话
    @discardableResult
    func createNewSession(title: String = "新会话") -> ChatSession? {
        let newSession = ChatSession(title: title)
        
        // 确保添加前没有相同ID的会话
        if let existingIndex = sessions.firstIndex(where: { $0.id == newSession.id }) {
            sessions.remove(at: existingIndex)
        }
        
        // 插入到数据库
        modelContext.insert(newSession)
        
        // 立即保存更改
        guard saveContext() else {
            return nil
        }
        
        if let previousSessionID = currentSession?.id,
           previousSessionID != newSession.id {
            cancelChatRequests(forSessionID: previousSessionID)
        }
        sessions.insert(newSession, at: 0)
        currentSession = newSession
        
        return newSession
    }
    
    // 切换到指定会话
    func switchToSession(_ session: ChatSession) {
        guard currentSession?.id != session.id else { return }
        if let previousSessionID = currentSession?.id {
            cancelChatRequests(forSessionID: previousSessionID)
        }
        currentSession = session
    }
    
    func session(withID id: UUID) -> ChatSession? {
        sessions.first { $0.id == id }
    }

    @discardableResult
    func addMessage(
        toSessionID sessionID: UUID,
        content: String,
        isUser: Bool,
        relatedEntryIDs: [UUID] = []
    ) -> SessionMessage? {
        guard let session = session(withID: sessionID) else {
            errorMessage = "目标会话不存在"
            return nil
        }

        let message = SessionMessage(
            content: content,
            isUser: isUser,
            relatedEntryIds: relatedEntryIDs.map(\.uuidString)
        )
        let previousMessages = session.messages
        let previousTitle = session.title
        let previousModifiedDate = session.lastModifiedDate
        modelContext.insert(message)
        session.addMessage(message)

        if session.title == "新会话" && isUser {
            session.title = session.generateSummary()
        }

        guard saveContext(onFailure: {
            session.messages = previousMessages
            session.title = previousTitle
            session.lastModifiedDate = previousModifiedDate
        }) else { return nil }
        sessions.forEach(normalizeMessageOrder)
        return message
    }

    @discardableResult
    func addMessageToCurrentSession(
        content: String,
        isUser: Bool,
        relatedEntryIds: [String] = []
    ) -> SessionMessage? {
        guard let sessionID = currentSession?.id else {
            errorMessage = "没有活动的会话"
            return nil
        }
        return addMessage(
            toSessionID: sessionID,
            content: content,
            isUser: isUser,
            relatedEntryIDs: relatedEntryIds.compactMap(UUID.init(uuidString:))
        )
    }

    @discardableResult
    func submitChatRequest(
        _ context: ChatRequestContext,
        provider: any ChatResponseProviding
    ) -> Bool {
        guard session(withID: context.sessionID) != nil else {
            chatRequestFailures[context.sessionID] = ChatRequestFailure(
                context: context,
                message: "目标会话不存在，无法发送消息。",
                userMessageWasSaved: false
            )
            return false
        }

        cancelChatRequests(forSessionID: context.sessionID)
        chatRequestFailures[context.sessionID] = nil

        guard addMessage(
            toSessionID: context.sessionID,
            content: context.userQuery,
            isUser: true,
            relatedEntryIDs: context.relatedEntryIDs
        ) != nil else {
            chatRequestFailures[context.sessionID] = ChatRequestFailure(
                context: context,
                message: errorMessage ?? "保存用户消息失败，请重试。",
                userMessageWasSaved: false
            )
            return false
        }

        startResponseRequest(context, provider: provider)
        return true
    }

    @discardableResult
    func retryFailedChatRequest(
        forSessionID sessionID: UUID,
        provider: any ChatResponseProviding
    ) -> Bool {
        guard let failure = chatRequestFailures[sessionID],
              session(withID: failure.context.sessionID) != nil else {
            return false
        }

        let retryContext = failure.context.retrying()
        cancelChatRequests(forSessionID: retryContext.sessionID)

        if !failure.userMessageWasSaved,
           addMessage(
               toSessionID: retryContext.sessionID,
               content: retryContext.userQuery,
               isUser: true,
               relatedEntryIDs: retryContext.relatedEntryIDs
           ) == nil {
            chatRequestFailures[sessionID] = ChatRequestFailure(
                context: retryContext,
                message: errorMessage ?? "保存用户消息失败，请重试。",
                userMessageWasSaved: false
            )
            return false
        }

        chatRequestFailures[sessionID] = ChatRequestFailure(
            context: retryContext,
            message: failure.message,
            userMessageWasSaved: true
        )
        startResponseRequest(retryContext, provider: provider)
        return true
    }

    func isProcessingChatRequest(forSessionID sessionID: UUID) -> Bool {
        pendingChatSessionIDs.contains(sessionID)
    }

    func chatRequestFailure(forSessionID sessionID: UUID) -> ChatRequestFailure? {
        chatRequestFailures[sessionID]
    }

    func cancelChatRequests(forSessionID sessionID: UUID) {
        let requestIDs = chatRequestSessions.compactMap { requestID, pendingSessionID in
            pendingSessionID == sessionID ? requestID : nil
        }
        for requestID in requestIDs {
            chatRequestTasks.removeValue(forKey: requestID)?.cancel()
            chatRequestSessions.removeValue(forKey: requestID)
        }
        pendingChatSessionIDs.remove(sessionID)
    }

    private func startResponseRequest(
        _ context: ChatRequestContext,
        provider: any ChatResponseProviding
    ) {
        pendingChatSessionIDs.insert(context.sessionID)
        chatRequestSessions[context.requestID] = context.sessionID

        chatRequestTasks[context.requestID] = Task { [weak self] in
            let outcome = await ChatResponseGenerator.generate(context: context, provider: provider)
            guard !Task.isCancelled else { return }
            self?.completeResponseRequest(context, outcome: outcome)
        }
    }

    private func completeResponseRequest(
        _ context: ChatRequestContext,
        outcome: ChatResponseOutcome
    ) {
        guard chatRequestSessions[context.requestID] == context.sessionID,
              !Task.isCancelled,
              session(withID: context.sessionID) != nil else {
            return
        }

        defer { finishResponseRequest(context) }

        switch outcome {
        case .provider(let message, let relatedEntryIDs):
            persistAssistantMessage(message, relatedEntryIDs: relatedEntryIDs, context: context)
        case .local(let result):
            persistAssistantMessage(result.message, relatedEntryIDs: result.relatedEntryIDs, context: context)
        case .failure(let message):
            chatRequestFailures[context.sessionID] = ChatRequestFailure(context: context, message: message)
        case .cancelled:
            break
        }
    }

    private func persistAssistantMessage(
        _ message: String,
        relatedEntryIDs: [UUID],
        context: ChatRequestContext
    ) {
        guard addMessage(
            toSessionID: context.sessionID,
            content: message,
            isUser: false,
            relatedEntryIDs: relatedEntryIDs
        ) != nil else {
            chatRequestFailures[context.sessionID] = ChatRequestFailure(
                context: context,
                message: errorMessage ?? "回复已生成，但保存失败。请重试。"
            )
            return
        }
        chatRequestFailures[context.sessionID] = nil
    }

    private func finishResponseRequest(_ context: ChatRequestContext) {
        chatRequestTasks.removeValue(forKey: context.requestID)
        chatRequestSessions.removeValue(forKey: context.requestID)
        let hasAnotherRequest = chatRequestSessions.values.contains(context.sessionID)
        if !hasAnotherRequest {
            pendingChatSessionIDs.remove(context.sessionID)
        }
    }
    
    // 更新会话标题
    @discardableResult
    func updateSessionTitle(_ session: ChatSession, newTitle: String) -> Bool {
        let oldTitle = session.title
        let oldModifiedDate = session.lastModifiedDate
        session.title = newTitle
        session.updateLastModified()
        guard saveContext() else {
            session.title = oldTitle
            session.lastModifiedDate = oldModifiedDate
            return false
        }
        
        return true
    }
    
    // 删除会话
    @discardableResult
    func deleteSession(_ session: ChatSession) -> Bool {
        let sessionID = session.id
        let messages = session.messages
        for message in messages {
            modelContext.delete(message)
        }
        modelContext.delete(session)
        guard saveContext(onFailure: {
            for message in messages {
                self.modelContext.insert(message)
            }
            self.modelContext.insert(session)
            session.messages = messages
        }, rollbackOnFailure: false) else {
            return false
        }
        cancelChatRequests(forSessionID: sessionID)
        chatRequestFailures[sessionID] = nil

        // 在本地列表中删除
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions.remove(at: index)
        }
        
        // 如果删除的是当前会话，切换到其他会话
        if currentSession?.id == sessionID {
            currentSession = sessions.first
            
            // 如果没有会话了，创建一个新会话
            if currentSession == nil && sessions.isEmpty {
                _ = createNewSession()
            }
        }

        return true
    }
    
    // 清空当前会话
    @discardableResult
    func clearCurrentSession() -> Bool {
        guard let session = currentSession else { return false }
        
        let sessionID = session.id
        let previousMessages = session.messages
        let previousTitle = session.title
        let previousModifiedDate = session.lastModifiedDate
        
        // 删除所有消息
        for message in session.messages {
            modelContext.delete(message)
        }
        
        // 清空消息列表并保存
        session.messages.removeAll()
        session.title = "新会话"
        session.updateLastModified()
        guard saveContext(onFailure: {
            session.messages = previousMessages
            session.title = previousTitle
            session.lastModifiedDate = previousModifiedDate
        }) else {
            return false
        }
        cancelChatRequests(forSessionID: sessionID)
        chatRequestFailures[sessionID] = nil
        
        return true
    }
    
    // 保存上下文
    @discardableResult
    private func saveContext(
        onFailure: (() -> Void)? = nil,
        rollbackOnFailure: Bool = true
    ) -> Bool {
        do {
            try saveAction(modelContext)
            errorMessage = nil
            return true
        } catch {
            onFailure?()
            if rollbackOnFailure {
                modelContext.rollback()
            }
            errorMessage = "保存会话失败: \(error.localizedDescription)"
            return false
        }
    }

    private func normalizeMessageOrder(in session: ChatSession) {
        session.messages.sort { lhs, rhs in
            if lhs.timestamp != rhs.timestamp {
                return lhs.timestamp < rhs.timestamp
            }
            if lhs.isUser != rhs.isUser {
                return lhs.isUser && !rhs.isUser
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}
