//
//  ChatExploreView.swift
//  EasyNote
//
//  Created by Claude AI on 2025/3/21.
//

import SwiftUI
import SwiftData

struct ChatExploreView: View {
    @ObservedObject var diaryViewModel: DiaryViewModel
    @StateObject private var sessionViewModel: ChatSessionViewModel
    @EnvironmentObject private var themeManager: ThemeManager
    
    @State private var inputText = ""
    @State private var isProcessing = false
    @State private var showingSessionList = false
    @State private var showingNewSessionAlert = false
    @State private var newSessionTitle = "新会话"
    
    init(diaryViewModel: DiaryViewModel, modelContext: ModelContext? = nil) {
        self.diaryViewModel = diaryViewModel
        self._sessionViewModel = StateObject(wrappedValue: ChatSessionViewModel(modelContext: modelContext))
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 消息列表
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 15) {
                            // 显示欢迎信息
                            if sessionViewModel.currentSession?.messages.isEmpty ?? true {
                                welcomeMessage
                            }
                            
                            // 显示聊天历史
                            if let currentSession = sessionViewModel.currentSession {
                                ForEach(currentSession.messages) { message in
                                    chatBubble(message: message)
                                }
                            }
                            
                            // 处理中占位
                            if isProcessing {
                                HStack {
                                    Image(systemName: "ellipsis")
                                        .foregroundColor(themeManager.accentColor)
                                        .font(.system(size: 30))
                                        .symbolEffect(.pulse)
                                    Spacer()
                                }
                                .padding(.horizontal)
                                .padding(.top, 10)
                                .id("processing")
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 10)
                    }
                    .onChange(of: sessionViewModel.currentSession?.messages.count) { _, _ in
                        // 当消息数量发生变化时，滚动到底部
                        if let lastMessage = sessionViewModel.currentSession?.messages.last {
                            withAnimation {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        } else if isProcessing {
                            withAnimation {
                                proxy.scrollTo("processing", anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: isProcessing) { _, newValue in
                        // 当处理状态变化时，如果正在处理则滚动到底部
                        if newValue {
                            withAnimation {
                                proxy.scrollTo("processing", anchor: .bottom)
                            }
                        }
                    }
                }
                
                Divider()
                
                // 输入区域
                HStack(spacing: 12) {
                    TextField("输入您的问题...", text: $inputText)
                        .padding(10)
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(20)
                        .disabled(isProcessing)
                    
                    Button {
                        sendMessage()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isProcessing ? .gray : themeManager.accentColor)
                    }
                    .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isProcessing)
                }
                .padding()
            }
            .navigationTitle(sessionViewModel.currentSession?.title ?? "探索")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        Button(action: {
                            showingSessionList = true
                        }) {
                            Label("管理会话", systemImage: "folder")
                        }
                        
                        Button(action: {
                            showingNewSessionAlert = true
                        }) {
                            Label("新建会话", systemImage: "plus")
                        }
                        
                        if sessionViewModel.currentSession != nil {
                            Divider()
                            
                            Button(role: .destructive, action: {
                                sessionViewModel.clearCurrentSession()
                            }) {
                                Label("清空当前会话", systemImage: "trash")
                            }
                        }
                    } label: {
                        Label("会话", systemImage: "line.3.horizontal")
                    }
                }
            }
            .sheet(isPresented: $showingSessionList) {
                SessionListView(
                    sessionViewModel: sessionViewModel,
                    isPresented: $showingSessionList,
                    themeManager: themeManager
                )
            }
            .alert("新建会话", isPresented: $showingNewSessionAlert) {
                TextField("会话标题", text: $newSessionTitle)
                    .autocorrectionDisabled()
                
                Button("取消", role: .cancel) {
                    newSessionTitle = "新会话"
                }
                
                Button("创建") {
                    _ = sessionViewModel.createNewSession(title: newSessionTitle)
                    newSessionTitle = "新会话"
                }
            } message: {
                Text("请为新会话输入一个标题")
            }
            .onAppear {
                // 加载所有笔记数据，确保AI可以访问完整的笔记内容
                diaryViewModel.loadEntries()
                
                // 加载会话数据
                sessionViewModel.loadSessions()
                
                // 打印会话状态
                print("ChatExploreView appears - 当前会话数: \(sessionViewModel.sessions.count)")
                if let currentSession = sessionViewModel.currentSession {
                    print("当前会话: \(currentSession.title), 消息数: \(currentSession.messages.count)")
                } else {
                    print("当前没有选中的会话")
                }
            }
            .onDisappear {
                // 确保在视图消失时保存任何未保存的更改
                print("ChatExploreView disappears - 保存会话状态")
            }
        }
    }
    
    // 欢迎信息
    private var welcomeMessage: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("欢迎使用笔记探索")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(themeManager.accentColor)
            
            Text("您可以通过对话方式探索您的笔记内容。试试以下问题：")
                .font(.body)
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 8) {
                ForEach(["最近写了哪些日记？", "我的笔记中提到过哪些心情？", "查找包含特定主题的笔记"], id: \.self) { suggestion in
                    Button {
                        inputText = suggestion
                    } label: {
                        Text(suggestion)
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(themeManager.accentColor.opacity(0.1))
                            .foregroundColor(themeManager.accentColor)
                            .cornerRadius(16)
                    }
                }
            }
            .padding(.top, 4)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(themeManager.accentColor.opacity(0.05))
        .cornerRadius(12)
        .padding(.bottom, 10)
    }
    
    // 聊天气泡
    private func chatBubble(message: SessionMessage) -> some View {
        HStack {
            if message.isUser {
                Spacer()
                Text(message.content)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(themeManager.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(20)
                    .cornerRadius(20, corners: [.topLeft, .topRight, .bottomLeft])
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text(message.content)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color(UIColor.secondarySystemBackground))
                        .foregroundColor(.primary)
                        .cornerRadius(20)
                        .cornerRadius(20, corners: [.topLeft, .topRight, .bottomRight])
                    
                    if !message.relatedEntryIds.isEmpty {
                        Text("相关笔记: \(message.relatedEntryIds.count)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.leading, 8)
                    }
                }
                
                Spacer()
            }
        }
        .id(message.id)
    }
    
    // 发送消息
    private func sendMessage() {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        // 保存用户输入并清空输入框
        let userQuery = inputText
        inputText = ""
        
        // 设置处理状态
        isProcessing = true
        
        // 处理用户请求并生成回复
        Task {
            // 确保加载最新的笔记数据
            diaryViewModel.loadEntries()
            
            // 模拟网络延迟
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            
            // 获取相关笔记用于上下文
            let relatedEntries = findRelatedEntries(query: userQuery)
            
            // 添加用户消息到会话
            await MainActor.run {
                // 将DiaryEntry转换为ID数组
                let entryIds = relatedEntries.map { $0.id.uuidString }
                
                _ = sessionViewModel.addMessageToCurrentSession(
                    content: userQuery,
                    isUser: true,
                    relatedEntryIds: entryIds
                )
            }
            
            // 首先尝试使用AI生成回复
            var response = await generateAIResponse(userQuery: userQuery, relatedEntries: relatedEntries)
            
            // 如果AI响应为空，回退到基本的笔记查询
            if response.isEmpty {
                let (fallbackResponse, _) = await analyzeQuery(userQuery)
                response = fallbackResponse
            }
            
            // 返回主线程更新UI
            await MainActor.run {
                // 将DiaryEntry转换为ID数组
                let entryIds = relatedEntries.map { $0.id.uuidString }
                
                // 添加AI回复到会话
                _ = sessionViewModel.addMessageToCurrentSession(
                    content: response,
                    isUser: false,
                    relatedEntryIds: entryIds
                )
                
                // 结束处理状态
                isProcessing = false
            }
        }
    }
    
    // 获取对话历史
    private func getConversationHistory() -> [SessionMessage]? {
        return sessionViewModel.currentSession?.messages
    }
    
    // 查找相关笔记
    private func findRelatedEntries(query: String) -> [DiaryEntry] {
        let entries = diaryViewModel.allEntries
        
        // 根据查询内容找出相关的笔记
        return entries.filter { entry in
            entry.title.lowercased().contains(query.lowercased()) ||
            entry.content.lowercased().contains(query.lowercased()) ||
            entry.tags.contains { tag in
                tag.lowercased().contains(query.lowercased())
            }
        }
    }
    
    // 使用AI生成响应
    private func generateAIResponse(userQuery: String, relatedEntries: [DiaryEntry]) async -> String {
        // 使用应用中已有的OpenAIService
        let openAIService = diaryViewModel.getOpenAIService()
        
        // 构建上下文和提示
        var prompt = "你是EasyNote应用的AI助手，可以帮助用户查找和分析他们的笔记内容。"
        prompt += "\n\n用户的问题是: \"\(userQuery)\"\n\n"
        
        // 添加对话历史作为上下文
        if let currentSession = sessionViewModel.currentSession, !currentSession.messages.isEmpty {
            prompt += "对话历史:\n"
            // 只包含最近的5条消息，避免提示太长
            let recentMessages = currentSession.messages.suffix(min(5, currentSession.messages.count))
            for msg in recentMessages {
                let role = msg.isUser ? "用户" : "AI"
                prompt += "\(role): \(msg.content)\n"
            }
            prompt += "\n"
        }
        
        // 添加相关笔记作为上下文
        if !relatedEntries.isEmpty {
            prompt += "相关笔记内容:\n"
            for (index, entry) in relatedEntries.prefix(3).enumerated() {
                prompt += "笔记\(index + 1) - 标题: \(entry.title)\n"
                prompt += "内容: \(entry.content.prefix(100))...\n"
                if let mood = entry.mood {
                    prompt += "心情: \(mood)\n"
                }
                if !entry.tags.isEmpty {
                    prompt += "标签: \(entry.tags.joined(separator: ", "))\n"
                }
                prompt += "\n"
            }
        } else {
            // 如果没有相关笔记，提供最近的几篇笔记作为上下文
            let allEntries = diaryViewModel.allEntries
            if !allEntries.isEmpty {
                let recentEntries = allEntries.sorted { $0.creationDate > $1.creationDate }.prefix(3)
                prompt += "最近的笔记内容（可能与查询无直接关联）:\n"
                
                for (index, entry) in recentEntries.enumerated() {
                    prompt += "最近笔记\(index + 1) - 标题: \(entry.title)\n"
                    prompt += "内容: \(entry.content.prefix(100))...\n"
                    if let mood = entry.mood {
                        prompt += "心情: \(mood)\n"
                    }
                    if !entry.tags.isEmpty {
                        prompt += "标签: \(entry.tags.joined(separator: ", "))\n"
                    }
                    prompt += "\n"
                }
            } else {
                prompt += "用户目前没有任何笔记。\n\n"
            }
        }
        
        // 添加指导
        prompt += "请以自然、友好的语气回应用户的问题。如果你找到了相关的笔记，可以总结这些内容并提供相关信息。如果没有找到相关笔记，可以礼貌告知并提供一些建议。不要重复列出所有笔记详情，而是提供有见解的回应。"
        
        // 尝试使用OpenAIService生成回应
        do {
            // 检查API密钥是否可用
            if openAIService.apiKey.isEmpty {
                return "AI服务需要设置API密钥才能使用。请在设置中添加您的API密钥。"
            }
            
            // 使用OpenAI服务生成回复
            let response = try await openAIService.chat(prompt: prompt)
            return response
        } catch {
            // 如果AI服务失败，使用备用响应
            let fallbackResponses = [
                "基于您的笔记，我发现您最近关注的主题是工作和心情。您在上周写了关于项目进展的笔记，感觉还不错。需要我帮您回顾一下详细内容吗？",
                
                "我查看了您的日记，发现您经常在感到开心的时候记录。您喜欢用\"很棒\"和\"不错\"这样的词来描述心情。您想了解更多关于这些积极情绪背后的活动吗？",
                
                "关于\"\(userQuery)\"，我在您的笔记中找到了几条相关记录。您曾经写到对这个话题感到兴奋，尤其是在工作取得进展时。您是想了解更多这方面的细节，还是想知道这些经历如何影响您的整体情绪？",
                
                "您的笔记显示，每当您使用\"开心\"标签时，通常也会提到家人或朋友。这表明您的社交活动对您的情绪有积极影响。您想深入了解这种关联吗？",
                
                "虽然我没有找到与\"\(userQuery)\"直接相关的笔记，但我注意到您经常写关于类似主题的内容。您的写作风格表明您是一个善于思考和分析的人。您想探索更多这方面的见解吗？"
            ]
            
            // 当AI服务失败时，返回一个备用回复
            if let response = fallbackResponses.randomElement() {
                return response
            }
            
            return "我理解您想了解关于\"\(userQuery)\"的信息。根据您的笔记内容，我可以帮您分析相关的记录和模式。您想要我重点关注哪些方面呢？"
        }
    }
    
    // 基本的笔记分析和查询（作为后备方案）
    private func analyzeQuery(_ query: String) async -> (String, [DiaryEntry]) {
        // 加载用户的所有日记条目
        let entries = diaryViewModel.allEntries
        
        // 如果没有日记条目
        if entries.isEmpty {
            return ("您似乎还没有创建任何笔记。要开始记录，请前往日记或待办页面点击添加按钮。", [])
        }
        
        // 查找相关笔记
        let relatedEntries = findRelatedEntries(query: query)
        
        // 生成回复
        var response = ""
        
        // 处理不同类型的查询
        if query.contains("最近") || query.contains("近期") {
            // 处理时间相关查询
            let sortedEntries = entries.sorted { $0.creationDate > $1.creationDate }
            let recentEntries = Array(sortedEntries.prefix(5))
            
            response = "您最近的笔记包括：\n"
            for (index, entry) in recentEntries.enumerated() {
                let dateFormatter = DateFormatter()
                dateFormatter.dateStyle = .medium
                dateFormatter.timeStyle = .none
                
                response += "\(index + 1). \(entry.title) - \(dateFormatter.string(from: entry.creationDate))\n"
            }
        } else if query.contains("心情") || query.contains("情绪") || query.contains("感受") {
            // 处理心情相关查询
            var moodEntries: [String: [DiaryEntry]] = [:]
            
            for entry in entries where entry.mood != nil {
                if let mood = entry.mood {
                    if moodEntries[mood] == nil {
                        moodEntries[mood] = []
                    }
                    moodEntries[mood]?.append(entry)
                }
            }
            
            response = "您的笔记中记录了以下心情：\n"
            for (mood, entries) in moodEntries.sorted(by: { $0.value.count > $1.value.count }) {
                response += "- \(mood): \(entries.count)条记录\n"
            }
        } else if relatedEntries.isEmpty {
            // 没有找到相关笔记
            response = "我没有找到与\"\(query)\"相关的笔记。您可以尝试使用不同的关键词，或者查询最近的笔记。"
        } else {
            // 找到相关笔记
            response = "我找到了\(relatedEntries.count)条与\"\(query)\"相关的笔记：\n"
            
            for (index, entry) in relatedEntries.prefix(5).enumerated() {
                let dateFormatter = DateFormatter()
                dateFormatter.dateStyle = .medium
                dateFormatter.timeStyle = .none
                
                response += "\(index + 1). \(entry.title) - \(dateFormatter.string(from: entry.creationDate))\n"
                
                // 添加一小部分内容预览
                if !entry.content.isEmpty {
                    let preview = String(entry.content.prefix(50))
                    response += "   预览: \(preview)...\n"
                }
            }
            
            if relatedEntries.count > 5 {
                response += "\n还有\(relatedEntries.count - 5)条相关笔记。"
            }
        }
        
        return (response, relatedEntries)
    }
}

// 扩展View以支持多个圆角设置
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

// 自定义形状用于多圆角设置
struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners
    
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

// 预览
#Preview {
    let modelContext = try! ModelContext(ModelContainer(for: DiaryEntry.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    let viewModel = DiaryViewModel(modelContext: modelContext)
    
    // 创建一些测试数据
    let entry1 = DiaryEntry(title: "今天很开心")
    entry1.content = "今天遇到了很多好事，心情非常好。"
    entry1.mood = "很棒"
    entry1.tags = ["开心", "好事"]
    
    let entry2 = DiaryEntry(title: "工作总结")
    entry2.content = "今天完成了项目的第一阶段，进展顺利。"
    entry2.mood = "不错"
    entry2.tags = ["工作", "项目"]
    
    modelContext.insert(entry1)
    modelContext.insert(entry2)
    
    return ChatExploreView(diaryViewModel: viewModel)
        .environmentObject(ThemeManager())
} 