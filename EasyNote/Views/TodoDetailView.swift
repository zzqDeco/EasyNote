import SwiftUI
import SwiftData

struct TodoDetailView: View {
    @ObservedObject var viewModel: TodoViewModel
    @Environment(\.dismiss) private var dismiss
    let item: TodoItem
    
    @State private var isEditingTodo = false
    @State private var showingDeleteConfirmation = false
    @State private var persistenceError: String?
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 标题和状态区域
                titleSection

                reminderStatusSection

                if let persistenceError {
                    Text(persistenceError)
                        .font(.footnote)
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                // 截止日期和优先级
                deadlineAndPrioritySection
                
                // 笔记内容
                if let notes = item.notes, !notes.isEmpty {
                    notesSection(notes)
                }
                
                // 底部按钮
                buttonSection
            }
            .padding()
            .padding(.bottom, 80)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("待办详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    isEditingTodo = true
                }) {
                    Text("编辑")
                        .fontWeight(.medium)
                }
            }
        }
        .sheet(isPresented: $isEditingTodo) {
            editTodoSheet
        }
        .alert("确认删除", isPresented: $showingDeleteConfirmation) {
            Button("删除", role: .destructive) {
                let feedback = PersistenceFeedback.resolve(
                    succeeded: viewModel.deleteTodoItem(withID: item.id),
                    viewModelError: viewModel.errorMessage,
                    fallbackError: "删除待办事项失败，请重试"
                )
                persistenceError = feedback.errorMessage
                if feedback.shouldDismiss {
                    dismiss()
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("确定要删除这个待办事项吗？此操作不可撤销。")
        }
    }
    
    // MARK: - 子视图

    @ViewBuilder
    private var reminderStatusSection: some View {
        if let systemReminderErrorMessage = viewModel.systemReminderErrorMessage {
            Text(systemReminderErrorMessage)
                .font(.caption)
                .foregroundColor(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if let systemReminderMessage = viewModel.systemReminderMessage {
            Text(systemReminderMessage)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                // 完成状态按钮
                Button {
                    viewModel.toggleTodoCompletion(for: item.id)
                } label: {
                    Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(item.isCompleted ? .green : .gray)
                        .font(.title)
                }
                
                // 标题 - 删除行数限制，允许完整显示
                Text(item.title)
                    .font(.system(.title, design: .default))
                    .fontWeight(.bold)
                    .foregroundColor(item.isCompleted ? .gray : .primary)
                    .strikethrough(item.isCompleted)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true) // 确保垂直方向自适应
            }
            
            // 循环指示器（如果是循环待办）
            if item.isRecurring, let interval = item.recurringInterval {
                HStack(spacing: 5) {
                    Image(systemName: "repeat")
                        .foregroundColor(.blue)
                    
                    Text(TodoItem.RecurringInterval.parse(interval)?.displayText ?? "重复")
                        .font(.subheadline)
                        .foregroundColor(.blue)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(12)
            }
        }
    }
    
    private var deadlineAndPrioritySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 优先级
            HStack(spacing: 8) {
                Image(systemName: "flag.fill")
                    .foregroundColor(item.priority.color)
                
                Text(priorityText(item.priority))
                    .font(.subheadline)
                    .foregroundColor(item.priority.color)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(item.priority.color.opacity(0.1))
            .cornerRadius(12)
            
            // 截止日期
            if let deadline = item.deadline {
                HStack(spacing: 8) {
                    Image(systemName: "calendar")
                        .foregroundColor(.secondary)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("截止日期")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text(formatDeadline(deadline))
                            .font(.subheadline)
                            .foregroundColor(isOverdue(deadline) ? .red : .primary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(12)
            }
        }
    }
    
    private func notesSection(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("备注")
                .font(.headline)
                .foregroundColor(.primary.opacity(0.8))
            
            Text(notes)
                .font(.body)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true) // 确保备注内容完整显示
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(UIColor.secondarySystemBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
        }
    }
    
    private var buttonSection: some View {
        VStack(spacing: 12) {
            Button(action: {
                viewModel.toggleTodoCompletion(for: item.id)
            }) {
                HStack {
                    Spacer()
                    
                    Text(item.isCompleted ? "标记为未完成" : "标记为已完成")
                        .fontWeight(.medium)
                    
                    Spacer()
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.green.opacity(0.1))
                )
                .foregroundColor(.green)
            }
            
            Button(action: {
                showingDeleteConfirmation = true
            }) {
                HStack {
                    Spacer()
                    
                    Text("删除")
                        .fontWeight(.medium)
                    
                    Spacer()
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.red.opacity(0.1))
                )
                .foregroundColor(.red)
            }
        }
        .padding(.top, 20)
    }
    
    private var editTodoSheet: some View {
        NavigationView {
            TodoEditView(viewModel: viewModel, item: item, isPresented: $isEditingTodo)
                .navigationBarTitleDisplayMode(.inline)
                .navigationTitle("编辑待办事项")
        }
    }
    
    // MARK: - 辅助方法
    
    private func priorityText(_ priority: TodoItem.PriorityLevel) -> String {
        switch priority {
        case .high: return "高优先级"
        case .medium: return "中优先级"
        case .low: return "低优先级"
        }
    }
    
    private func formatDeadline(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: date)
    }
    
    private func isOverdue(_ deadline: Date) -> Bool {
        return deadline < Date() && !item.isCompleted
    }
    
}

// MARK: - 待办编辑视图
struct TodoEditView: View {
    @ObservedObject var viewModel: TodoViewModel
    let item: TodoItem
    @Binding var isPresented: Bool
    
    @State private var draft: TodoDraft
    @State private var persistenceError: String?
    
    init(viewModel: TodoViewModel, item: TodoItem, isPresented: Binding<Bool>) {
        self.viewModel = viewModel
        self.item = item
        self._isPresented = isPresented
        
        self._draft = State(initialValue: TodoDraft(item: item))
    }
    
    var body: some View {
        Form {
            if let persistenceError {
                Section {
                    Text(persistenceError)
                        .font(.footnote)
                        .foregroundColor(.red)
                }
            }

            Section(header: Text("待办内容")) {
                TextEditor(text: $draft.title)
                    .frame(minHeight: 80)
                    .font(.body)
                    .padding(.vertical, 4)
                    .background(Color(UIColor.systemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                            .opacity(draft.title.isEmpty ? 1 : 0)
                    )
                    .overlay(
                        HStack {
                            Text("标题")
                                .foregroundColor(Color.gray.opacity(0.7))
                                .padding(.leading, 5)
                            Spacer()
                        }
                        .opacity(draft.title.isEmpty ? 1 : 0),
                        alignment: .topLeading
                    )
                
                Picker("优先级", selection: $draft.priority) {
                    Text("高").tag(TodoItem.PriorityLevel.high)
                    Text("中").tag(TodoItem.PriorityLevel.medium)
                    Text("低").tag(TodoItem.PriorityLevel.low)
                }
                .pickerStyle(SegmentedPickerStyle())
            }
            
            Section(header: Text("截止日期")) {
                Toggle(isOn: Binding(
                    get: { draft.deadline != nil },
                    set: { draft.deadline = $0 ? Date() : nil }
                )) {
                    Text("设置截止日期")
                }
                
                if draft.deadline != nil {
                    DatePicker("选择日期", selection: Binding(
                        get: { draft.deadline ?? Date() },
                        set: { draft.deadline = $0 }
                    ), displayedComponents: [.date, .hourAndMinute])
                    
                    // 循环选项
                    Toggle(isOn: $draft.isRecurring) {
                        Text("循环待办")
                    }
                    
                    if draft.isRecurring {
                        Picker("循环周期", selection: $draft.recurringInterval) {
                            Text("每天").tag(TodoItem.RecurringInterval.daily)
                            Text("每周").tag(TodoItem.RecurringInterval.weekly)
                            Text("两周").tag(TodoItem.RecurringInterval.biweekly)
                            Text("每月").tag(TodoItem.RecurringInterval.monthly)
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        
                        // 解释这个循环事项的行为
                        Text("完成后会自动创建下一个循环待办")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Section(header: Text("备注")) {
                TextEditor(text: $draft.notes)
                    .frame(minHeight: 100) // 使用最小高度而不是固定高度
            }
            
            // 添加一个空的Section作为底部间距
            Section {
                Color.clear
                    .frame(height: 60)
                    .listRowBackground(Color.clear)
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("取消") {
                    isPresented = false
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("保存") {
                    let feedback = PersistenceFeedback.resolve(
                        succeeded: viewModel.updateTodoItem(
                            id: item.id,
                            title: draft.title,
                            priority: draft.priority,
                            deadline: draft.deadline,
                            notes: draft.persistedNotes,
                            isRecurring: draft.isRecurring && draft.deadline != nil,
                            recurringInterval: draft.isRecurring && draft.deadline != nil ? draft.recurringInterval.rawValue : nil
                        ),
                        viewModelError: viewModel.errorMessage,
                        fallbackError: "更新待办事项失败，请重试"
                    )
                    persistenceError = feedback.errorMessage
                    if feedback.shouldDismiss {
                        isPresented = false
                    }
                }
                .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}

// MARK: - 预览
#Preview {
    // 创建模拟数据
    let todo = TodoItem(
        id: UUID(),
        title: "完成项目设计文档",
        isCompleted: false,
        priority: .high,
        deadline: Date().addingTimeInterval(86400), // 明天
        notes: "需要包含用户流程图和线框图，完成后发送给团队评审。",
        isRecurring: true,
        recurringInterval: "weekly"
    )
    
    // 创建视图模型
    let viewModel = TodoViewModel(modelContext: ModelContext(try! ModelContainer(for: TodoItem.self)))
    
    return NavigationView {
        TodoDetailView(viewModel: viewModel, item: todo)
    }
}
