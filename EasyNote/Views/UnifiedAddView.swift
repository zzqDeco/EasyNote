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
    
    // 待办事项状态
    @State private var todoTitle = ""
    @State private var todoPriority: TodoItem.PriorityLevel = .medium
    @State private var todoHasDeadline = false
    @State private var todoDeadline = Date()
    @State private var todoNotes = ""
    @State private var todoIsRecurring = false
    @State private var todoRecurringInterval: TodoItem.RecurringInterval = .daily
    
    // 动画状态
    @State private var showKeyboardToolbar = false
    @State private var keyboardHeight: CGFloat = 0
    @State private var contentFocused = false
    
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
                    recurringView
                    
                    // 备注编辑区
                    notesInputView
                }
                .padding()
                // 添加足够的底部间距，避免底部工具栏遮挡内容
                .padding(.bottom, 100)
            }
            
            // 底部工具栏
            bottomToolbar
        }
        .background(Color(UIColor.systemBackground))
        .onAppear {
            setupKeyboardObservers()
        }
        .onDisappear {
            removeKeyboardObservers()
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
                .disabled(todoTitle.isEmpty)
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
                if todoTitle.isEmpty {
                    Text("输入待办事项...")
                        .font(.title2.bold())
                        .foregroundColor(.gray.opacity(0.8))
                        .padding(.top, 7)
                        .padding(.leading, 12)
                        .padding(.bottom, 0)
                }
                
                TextEditor(text: $todoTitle)
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
            
            Picker("优先级", selection: $todoPriority) {
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
                
                Toggle("", isOn: $todoHasDeadline)
                    .labelsHidden()
                    .tint(themeManager.accentColor)
            }
            
            if todoHasDeadline {
                DatePicker("选择日期和时间", selection: $todoDeadline, displayedComponents: [.date, .hourAndMinute])
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
                
                Toggle("", isOn: $todoIsRecurring)
                    .labelsHidden()
                    .tint(themeManager.accentColor)
            }
            
            if todoIsRecurring {
                Picker("重复频率", selection: $todoRecurringInterval) {
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
                if todoNotes.isEmpty {
                    Text("添加备注...")
                        .foregroundColor(.gray.opacity(0.8))
                        .padding(.top, 7)
                        .padding(.leading, 5)
                }
                
                TextEditor(text: $todoNotes)
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
                .background(todoTitle.isEmpty ? Color.gray.opacity(0.3) : themeManager.accentColor)
                .foregroundColor(todoTitle.isEmpty ? .gray : .white)
                .cornerRadius(8)
        }
        .disabled(todoTitle.isEmpty)
    }
    
    // MARK: - 辅助方法
    
    // 设置键盘观察者
    private func setupKeyboardObservers() {
        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillShowNotification,
            object: nil,
            queue: .main
        ) { notification in
            if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                self.keyboardHeight = keyboardFrame.height
                withAnimation {
                    self.showKeyboardToolbar = true
                }
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillHideNotification,
            object: nil,
            queue: .main
        ) { _ in
            withAnimation {
                self.showKeyboardToolbar = false
                self.keyboardHeight = 0
                self.contentFocused = false
            }
        }
    }
    
    // 移除键盘观察者
    private func removeKeyboardObservers() {
        NotificationCenter.default.removeObserver(
            self,
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )
        
        NotificationCenter.default.removeObserver(
            self,
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }
    
    // 保存待办事项
    private func saveTodo() {
        guard let vm = todoViewModel else { return }
        
        vm.addTodoItem(
            title: todoTitle,
            priority: todoPriority,
            deadline: todoHasDeadline ? todoDeadline : nil,
            notes: todoNotes.isEmpty ? nil : todoNotes,
            isRecurring: todoIsRecurring,
            recurringInterval: todoIsRecurring ? todoRecurringInterval.rawValue : nil
        )
        
        isPresented = false
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