import SwiftUI
import SwiftData

struct UnifiedAddView: View {
    // 视图模型
    var todoViewModel: TodoViewModel?
    
    // 显示状态
    @Binding var isPresented: Bool
    @Binding var contentType: AddingContentType
    
    // 环境对象
    @EnvironmentObject private var tabBarController: TabBarController
    @EnvironmentObject private var tabSelectionManager: TabSelectionManager
    @Environment(\.colorScheme) private var colorScheme
    
    // 使用ThemeManager
    @EnvironmentObject private var themeManager: ThemeManager
    
    @State private var todoDraft = TodoDraft()
    @State private var persistenceError: String?
    @StateObject private var keyboardObserver = KeyboardObserver()
    
    // 日期格式器
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter
    }()
    
    var body: some View {
        VStack(spacing: 0) {
            // 标题输入区
            titleInputView
            
            Divider()
            
            // 内容输入区
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // 优先级选择
                    priorityView
                    
                    // 截止日期
                    deadlineView
                    
                    // 循环设置
                    if todoDraft.deadline != nil {
                        recurringView
                    }
                    
                    // 备注编辑区
                    notesInputView
                }
                .padding()
                // 添加足够的底部间距，避免底部工具栏遮挡内容
                .padding(.bottom, 100)
            }

            if let persistenceError {
                Text(persistenceError)
                    .font(.footnote)
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
            
            // 底部工具栏
            bottomToolbar
        }
        .background(Color(UIColor.systemBackground))
        .onAppear {
            keyboardObserver.start()
        }
        .onDisappear {
            keyboardObserver.stop()
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("取消") {
                    isPresented = false
                }
                .foregroundColor(.red)
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("保存") {
                    saveTodo()
                }
                .disabled(todoDraft.title.isEmpty)
                .fontWeight(.medium)
            }
        }
    }
    
    // MARK: - 子视图
    
    private var titleInputView: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 标题标签
            HStack {
                Text("待办内容")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.top, 16)
                Spacer()
            }
            .padding(.horizontal)
            
            // 标题编辑器
            ZStack(alignment: .topLeading) {
                if todoDraft.title.isEmpty {
                    Text("输入待办事项...")
                        .font(.title2.bold())
                        .foregroundColor(.gray.opacity(0.8))
                        .padding(.top, 7)
                        .padding(.leading, 12)
                        .padding(.bottom, 0)
                }
                
                TextEditor(text: $todoDraft.title)
                    .font(.title2.bold())
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .frame(height: 45)
                    .padding(0)
            }
            .padding(.horizontal, 12)
        }
        .padding(.bottom, 10)
    }
    
    private var priorityView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("优先级")
                .font(.headline)
                .foregroundColor(.primary.opacity(0.8))
                .padding(.top, 8)
            
            Picker("优先级", selection: $todoDraft.priority) {
                Text("低").tag(TodoItem.PriorityLevel.low)
                Text("中").tag(TodoItem.PriorityLevel.medium)
                Text("高").tag(TodoItem.PriorityLevel.high)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.vertical, 8)
            .accentColor(themeManager.accentColor)
        }
    }
    
    private var deadlineView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("截止日期")
                    .font(.headline)
                    .foregroundColor(.primary.opacity(0.8))
                
                Spacer()
                
                Toggle("", isOn: Binding(
                    get: { todoDraft.deadline != nil },
                    set: { isEnabled in
                        todoDraft.deadline = isEnabled ? Date() : nil
                        if !isEnabled {
                            todoDraft.isRecurring = false
                        }
                    }
                ))
                    .labelsHidden()
                    .tint(themeManager.accentColor)
            }
            
            if todoDraft.deadline != nil {
                DatePicker(
                    "选择日期和时间",
                    selection: Binding(
                        get: { todoDraft.deadline ?? Date() },
                        set: { todoDraft.deadline = $0 }
                    ),
                    displayedComponents: [.date, .hourAndMinute]
                )
                    .datePickerStyle(GraphicalDatePickerStyle())
                    .padding(.vertical, 8)
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(8)
                    .accentColor(themeManager.accentColor)
            }
        }
    }
    
    private var recurringView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("重复")
                    .font(.headline)
                    .foregroundColor(.primary.opacity(0.8))
                
                Spacer()
                
                Toggle("", isOn: $todoDraft.isRecurring)
                    .labelsHidden()
                    .tint(themeManager.accentColor)
            }
            
            if todoDraft.isRecurring {
                Picker("重复频率", selection: $todoDraft.recurringInterval) {
                    Text("每天").tag(TodoItem.RecurringInterval.daily)
                    Text("每周").tag(TodoItem.RecurringInterval.weekly)
                    Text("两周").tag(TodoItem.RecurringInterval.biweekly)
                    Text("每月").tag(TodoItem.RecurringInterval.monthly)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.vertical, 8)
                .accentColor(themeManager.accentColor)
            }
        }
    }
    
    private var notesInputView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("备注")
                .font(.headline)
                .foregroundColor(.primary.opacity(0.8))
                .padding(.top, 8)
            
            ZStack(alignment: .topLeading) {
                if todoDraft.notes.isEmpty {
                    Text("添加备注...")
                        .foregroundColor(.gray.opacity(0.8))
                        .padding(.top, 7)
                        .padding(.leading, 5)
                }
                
                TextEditor(text: $todoDraft.notes)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .frame(minHeight: 120)
                    .padding(.horizontal, 0)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
            }
            .padding(.horizontal, 5)
        }
    }
    
    private var bottomToolbar: some View {
        HStack {
            // 辅助说明
            Text("创建后可在\"探索\"页面查看")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
            
            // 右侧分隔线
            Divider()
                .frame(height: 30)
                .padding(.horizontal, 8)
            
            // 保存按钮
            saveButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Rectangle()
                .fill(Color(UIColor.systemBackground))
                .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: -2)
        )
    }
    
    private var saveButton: some View {
        Button {
            saveTodo()
        } label: {
            Text("保存")
                .fontWeight(.medium)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(todoDraft.title.isEmpty ? Color.gray.opacity(0.3) : themeManager.accentColor)
                .foregroundColor(todoDraft.title.isEmpty ? .gray : .white)
                .cornerRadius(8)
        }
        .disabled(todoDraft.title.isEmpty)
    }
    
    // 保存待办事项
    private func saveTodo() {
        guard let vm = todoViewModel else { return }

        let feedback = PersistenceFeedback.resolve(
            succeeded: vm.addTodoItem(from: todoDraft),
            viewModelError: vm.errorMessage,
            fallbackError: "保存待办事项失败，请重试"
        )
        persistenceError = feedback.errorMessage

        if feedback.shouldDismiss {
            isPresented = false
        }
    }
}

#Preview {
    // 创建一个内存中的ModelContainer用于预览
    do {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: DiaryEntry.self, TodoItem.self, configurations: config)
        let context = ModelContext(container)
        
        return NavigationStack {
            UnifiedAddView(
                todoViewModel: TodoViewModel(modelContext: context),
                isPresented: .constant(true),
                contentType: .constant(.todo)
            )
            .navigationTitle("新建待办")
            .navigationBarTitleDisplayMode(.inline)
            .environmentObject(ThemeManager())
            .environmentObject(TabSelectionManager(selectedTab: .constant(0)))
            .environmentObject(TabBarController())
        }
    } catch {
        return Text("预览加载失败: \(error.localizedDescription)")
    }
}
