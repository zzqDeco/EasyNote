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
    @State private var showingSessionList = false
    @State private var showingNewSessionAlert = false
    @State private var newSessionTitle = "新会话"
    
    init(diaryViewModel: DiaryViewModel, modelContext: ModelContext? = nil) {
        self.diaryViewModel = diaryViewModel
        self._sessionViewModel = StateObject(wrappedValue: ChatSessionViewModel(modelContext: modelContext))
    }

    private var activeSessionID: UUID? {
        sessionViewModel.currentSession?.id
    }

    private var isProcessing: Bool {
        guard let activeSessionID else { return false }
        return sessionViewModel.isProcessingChatRequest(forSessionID: activeSessionID)
    }

    private var activeFailure: ChatRequestFailure? {
        guard let activeSessionID else { return nil }
        return sessionViewModel.chatRequestFailure(forSessionID: activeSessionID)
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

                            if let activeFailure {
                                chatFailureView(activeFailure)
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
                diaryViewModel.loadEntries()
                sessionViewModel.loadSessions()
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

    private func chatFailureView(_ failure: ChatRequestFailure) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle")
                .foregroundColor(.orange)

            VStack(alignment: .leading, spacing: 8) {
                Text(failure.message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Button("重试") {
                    _ = sessionViewModel.retryFailedChatRequest(
                        forSessionID: failure.context.sessionID,
                        provider: diaryViewModel.getOpenAIService()
                    )
                }
                .font(.subheadline.weight(.medium))
            }

            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.08))
        .cornerRadius(8)
        .id("chat-request-failure")
    }
    
    // 发送消息
    private func sendMessage() {
        let userQuery = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userQuery.isEmpty,
              let session = sessionViewModel.currentSession else {
            return
        }

        diaryViewModel.loadEntries()
        let diarySnapshots = diaryViewModel.allEntries.map(ChatDiaryEntrySnapshot.init(entry:))
        let relatedEntryIDs = LocalDiaryQueryAnalyzer.matchingEntries(
            for: userQuery,
            in: diarySnapshots
        ).map(\.id)
        let context = ChatRequestContext(
            requestID: UUID(),
            sessionID: session.id,
            userQuery: userQuery,
            relatedEntryIDs: relatedEntryIDs,
            conversationHistory: session.messages.map(ChatConversationMessageSnapshot.init(message:)),
            diaryEntries: diarySnapshots
        )

        if sessionViewModel.submitChatRequest(
            context,
            provider: diaryViewModel.getOpenAIService()
        ) {
            inputText = ""
        }
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
