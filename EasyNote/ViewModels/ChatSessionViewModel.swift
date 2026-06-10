import Foundation
import SwiftData
import Combine
import SwiftUI

class ChatSessionViewModel: ObservableObject {
    // 模型上下文
    private var modelContext: ModelContext
    
    // 会话数据
    @Published var sessions: [ChatSession] = []
    @Published var currentSession: ChatSession?
    @Published var isLoadingMessages = false
    @Published var errorMessage: String?
    
    // MARK: - 初始化方法
    
    init(modelContext: ModelContext?) {
        if let context = modelContext {
            self.modelContext = context
        } else {
            // 如果没有提供ModelContext，创建一个内存中的临时ModelContext
            do {
                // 确保使用相同的URL路径
                let storeURL = URL.documentsDirectory.appending(path: "EasyNote.store")
                let schema = Schema([ChatSession.self, SessionMessage.self])
                let config = ModelConfiguration(
                    "EasyNoteChatSessions",
                    schema: schema,
                    url: storeURL,
                    allowsSave: true,
                    cloudKitDatabase: .none
                )
                
                let container = try ModelContainer(for: schema, configurations: [config])
                self.modelContext = ModelContext(container)
                print("ChatSessionViewModel: 创建了ModelContext，使用数据库路径: \(storeURL.path())")
            } catch {
                print("无法创建临时ModelContext: \(error)")
                fatalError("无法创建ModelContext，应用程序无法继续: \(error)")
            }
        }
        // 加载所有会话
        loadSessions()
    }
    
    // MARK: - 会话管理
    
    // 加载所有会话
    func loadSessions() {
        isLoadingMessages = true
        
        do {
            let descriptor = FetchDescriptor<ChatSession>(sortBy: [SortDescriptor(\.lastModifiedDate, order: .reverse)])
            let fetchedSessions = try modelContext.fetch(descriptor)
            
            print("已加载 \(fetchedSessions.count) 个会话")
            
            DispatchQueue.main.async {
                self.sessions = fetchedSessions
                
                // 如果没有会话，创建一个新会话
                if self.sessions.isEmpty {
                    print("没有找到会话，创建新会话")
                    _ = self.createNewSession()
                } else if self.currentSession == nil {
                    // 如果当前没有选中的会话，选择最新的会话
                    print("选择最近的会话: \(self.sessions.first?.title ?? "未知")")
                    self.currentSession = self.sessions.first
                }
                
                self.isLoadingMessages = false
            }
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = "加载会话失败: \(error.localizedDescription)"
                self.isLoadingMessages = false
                print("加载会话失败: \(error.localizedDescription)")
                
                // 如果加载失败，至少确保有一个会话可用
                if self.sessions.isEmpty {
                    _ = self.createNewSession()
                }
            }
        }
    }
    
    // 创建新会话
    func createNewSession(title: String = "新会话") -> ChatSession {
        let newSession = ChatSession(title: title)
        
        // 确保添加前没有相同ID的会话
        if let existingIndex = sessions.firstIndex(where: { $0.id == newSession.id }) {
            sessions.remove(at: existingIndex)
        }
        
        // 插入到数据库
        modelContext.insert(newSession)
        
        // 立即保存更改
        saveContext()
        
        print("创建了新会话: \(title), ID: \(newSession.id)")
        
        // 确保在主线程更新UI状态
        DispatchQueue.main.async {
            // 将新会话添加到列表并设为当前会话
            self.sessions.insert(newSession, at: 0)
            self.currentSession = newSession
        }
        
        return newSession
    }
    
    // 切换到指定会话
    func switchToSession(_ session: ChatSession) {
        // 确保在主线程更新UI状态
        DispatchQueue.main.async {
            self.currentSession = session
        }
        print("切换到会话: \(session.title), ID: \(session.id)")
    }
    
    // 添加消息到当前会话
    func addMessageToCurrentSession(content: String, isUser: Bool, relatedEntryIds: [String] = []) -> SessionMessage? {
        guard let session = currentSession else {
            errorMessage = "没有活动的会话"
            return nil
        }
        
        // 创建消息
        let message = SessionMessage(content: content, isUser: isUser, relatedEntryIds: relatedEntryIds)
        
        // 插入到数据库
        modelContext.insert(message)
        
        // 将消息添加到会话中
        session.addMessage(message)
        
        // 更新会话最后修改时间
        session.updateLastModified()
        
        // 立即保存更改
        saveContext()
        
        print("添加消息到会话 '\(session.title)': \(content.prefix(20))...")
        
        // 如果会话有自定义标题，则不更新
        if session.title == "新会话" && isUser {
            // 生成新标题
            let newTitle = session.generateSummary()
            session.title = newTitle
            saveContext()
            
            print("更新会话标题为: \(newTitle)")
        }
        
        return message
    }
    
    // 更新会话标题
    func updateSessionTitle(_ session: ChatSession, newTitle: String) {
        session.title = newTitle
        session.updateLastModified()
        saveContext()
        
        print("更新会话标题: \(newTitle)")
    }
    
    // 删除会话
    func deleteSession(_ session: ChatSession) {
        // 保存会话ID，用于日志
        let sessionID = session.id
        let sessionTitle = session.title
        
        // 在本地列表中删除
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions.remove(at: index)
        }
        
        // 从数据库中删除
        modelContext.delete(session)
        saveContext()
        
        print("删除会话: \(sessionTitle), ID: \(sessionID)")
        
        // 如果删除的是当前会话，切换到其他会话
        if currentSession?.id == sessionID {
            currentSession = sessions.first
            
            // 如果没有会话了，创建一个新会话
            if currentSession == nil && sessions.isEmpty {
                _ = createNewSession()
                
                print("已删除所有会话，创建新会话")
            }
        }
    }
    
    // 清空当前会话
    func clearCurrentSession() {
        guard let session = currentSession else { return }
        
        // 保存会话ID，用于日志
        let sessionID = session.id
        
        // 删除所有消息
        for message in session.messages {
            modelContext.delete(message)
        }
        
        // 清空消息列表并保存
        session.messages.removeAll()
        session.title = "新会话"
        session.updateLastModified()
        saveContext()
        
        print("清空会话消息, ID: \(sessionID)")
    }
    
    // 保存上下文
    private func saveContext() {
        do {
            try modelContext.save()
            print("成功保存数据库变更")
        } catch {
            errorMessage = "保存会话失败: \(error.localizedDescription)"
            print("保存会话失败: \(error.localizedDescription)")
        }
    }
}
