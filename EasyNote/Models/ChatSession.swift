import Foundation
import SwiftData

// 聊天会话模型 - 用于保存整个对话会话
@Model
final class ChatSession {
    var id: UUID
    var title: String
    var creationDate: Date
    var lastModifiedDate: Date
    var messages: [SessionMessage] = []
    
    init(id: UUID = UUID(), title: String = "新会话", messages: [SessionMessage] = []) {
        self.id = id
        self.title = title
        self.creationDate = Date()
        self.lastModifiedDate = Date()
        self.messages = messages
    }
    
    // 更新最后修改日期
    func updateLastModified() {
        self.lastModifiedDate = Date()
    }
    
    // 添加消息到会话
    func addMessage(_ message: SessionMessage) {
        self.messages.append(message)
        self.updateLastModified()
    }
    
    // 生成会话摘要（取自最近的一条用户消息或使用默认标题）
    func generateSummary() -> String {
        if let lastUserMessage = messages.filter({ $0.isUser }).last {
            // 截取用户最后一条消息的前20个字符作为摘要
            let content = lastUserMessage.content
            let summary = content.prefix(20)
            return summary.count < content.count ? "\(summary)..." : String(summary)
        }
        return title
    }
    
    // 通过ID查找消息
    func findMessage(withID id: UUID) -> SessionMessage? {
        return messages.first(where: { $0.id == id })
    }
    
    // 验证会话完整性
    func validateIntegrity() -> Bool {
        guard !title.isEmpty else {
            print("无效会话：标题为空")
            return false
        }
        
        guard creationDate <= Date() else {
            print("无效会话：创建日期在未来")
            return false
        }
        
        guard lastModifiedDate <= Date() else {
            print("无效会话：修改日期在未来")
            return false
        }
        
        // 检查所有消息
        for message in messages {
            guard !message.content.isEmpty else {
                print("无效会话：包含空消息内容")
                return false
            }
        }
        
        return true
    }
}

// 聊天消息模型 - 用于保存单条消息
@Model
final class SessionMessage {
    var id: UUID
    var content: String
    var isUser: Bool
    var timestamp: Date
    var relatedEntryIds: [String] // 存储相关日记条目的ID
    
    init(id: UUID = UUID(), content: String, isUser: Bool, timestamp: Date = Date(), relatedEntryIds: [String] = []) {
        self.id = id
        self.content = content
        self.isUser = isUser
        self.timestamp = timestamp
        self.relatedEntryIds = relatedEntryIds
    }
    
    // 验证消息完整性
    func validateIntegrity() -> Bool {
        guard !content.isEmpty else { return false }
        guard timestamp <= Date() else { return false }
        return true
    }
}

// 添加类型别名，解决与ChatExploreView中定义的ChatMessage结构体的命名冲突
typealias ChatMessage = SessionMessage
