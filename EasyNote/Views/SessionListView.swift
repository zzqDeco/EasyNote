import SwiftUI
import SwiftData

struct SessionListView: View {
    @ObservedObject var sessionViewModel: ChatSessionViewModel
    @Binding var isPresented: Bool
    var themeManager: ThemeManager
    
    @State private var editingSessionID: UUID?
    @State private var newTitle: String = ""
    @State private var showingRenameAlert = false
    @State private var showingDeleteAlert = false
    @State private var sessionToDelete: ChatSession? = nil
    
    var body: some View {
        NavigationStack {
            VStack {
                if sessionViewModel.sessions.isEmpty {
                    // 没有会话时显示空状态
                    VStack {
                        Spacer()
                        Image(systemName: "text.bubble")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                            .padding()
                        
                        Text("暂无会话")
                            .font(.title3)
                            .foregroundColor(.secondary)
                        
                        Button {
                            // 创建新会话
                            _ = sessionViewModel.createNewSession()
                            isPresented = false
                        } label: {
                            Text("创建新会话")
                                .padding(.horizontal)
                                .padding(.vertical, 8)
                                .background(themeManager.accentColor)
                                .foregroundColor(.white)
                                .cornerRadius(20)
                        }
                        .padding(.top)
                        
                        Spacer()
                    }
                } else {
                    // 显示会话列表
                    List {
                        ForEach(sessionViewModel.sessions) { session in
                            SessionRow(
                                session: session,
                                isActive: session.id == sessionViewModel.currentSession?.id,
                                themeManager: themeManager,
                                onTap: {
                                    // 切换到该会话
                                    sessionViewModel.switchToSession(session)
                                    isPresented = false
                                },
                                onRename: {
                                    // 重命名会话
                                    editingSessionID = session.id
                                    newTitle = session.title
                                    showingRenameAlert = true
                                },
                                onDelete: {
                                    // 删除会话
                                    sessionToDelete = session
                                    showingDeleteAlert = true
                                }
                            )
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        }
                    }
                    .listStyle(PlainListStyle())
                }
            }
            .navigationTitle("会话列表")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") {
                        isPresented = false
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        // 创建新会话
                        if let newSession = sessionViewModel.createNewSession() {
                            sessionViewModel.switchToSession(newSession)
                            isPresented = false
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .alert("重命名会话", isPresented: $showingRenameAlert) {
                TextField("会话标题", text: $newTitle)
                
                Button("取消", role: .cancel) { }
                
                Button("保存") {
                    if let sessionID = editingSessionID {
                        sessionViewModel.updateSessionTitle(sessionID: sessionID, newTitle: newTitle)
                    }
                }
            } message: {
                Text("请输入新的会话标题")
            }
            .alert("删除会话", isPresented: $showingDeleteAlert) {
                Button("取消", role: .cancel) { }
                
                Button("删除", role: .destructive) {
                    if let session = sessionToDelete {
                        sessionViewModel.deleteSession(session)
                    }
                }
            } message: {
                Text("确定要删除这个会话吗？此操作无法撤销。")
            }
        }
    }
}

// 会话行视图
struct SessionRow: View {
    let session: ChatSession
    let isActive: Bool
    let themeManager: ThemeManager
    let onTap: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            // 会话信息
            VStack(alignment: .leading, spacing: 4) {
                Text(session.title)
                    .font(.headline)
                    .foregroundColor(isActive ? themeManager.accentColor : .primary)
                
                // 显示日期
                Text(formatDate(session.lastModifiedDate))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // 操作菜单
            Menu {
                Button(action: onRename) {
                    Label("重命名", systemImage: "pencil")
                }
                
                Divider()
                
                Button(role: .destructive, action: onDelete) {
                    Label("删除", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundColor(.gray)
                    .padding(8)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isActive ? themeManager.accentColor.opacity(0.1) : Color.clear)
        )
    }
    
    // 格式化日期
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

#Preview {
    // 创建一个预览用的视图模型
    @MainActor
    func createPreview() -> SessionListView {
        let container = try! ModelContainer(for: ChatSession.self, SessionMessage.self)
        let context = ModelContext(container)
        let viewModel = ChatSessionViewModel(modelContext: context)
        
        // 创建一些测试数据
        let session1 = ChatSession(title: "笔记查询")
        session1.addMessage(SessionMessage(content: "最近写了哪些日记？", isUser: true))
        session1.addMessage(SessionMessage(content: "您最近的笔记包括：...", isUser: false))
        
        let session2 = ChatSession(title: "心情分析")
        session2.addMessage(SessionMessage(content: "我的笔记中提到过哪些心情？", isUser: true))
        session2.addMessage(SessionMessage(content: "您的笔记中记录了以下心情：...", isUser: false))
        
        context.insert(session1)
        context.insert(session2)
        
        viewModel.loadSessions()
        viewModel.switchToSession(session1)
        
        return SessionListView(
            sessionViewModel: viewModel,
            isPresented: .constant(true),
            themeManager: ThemeManager()
        )
    }
    
    return createPreview()
}
