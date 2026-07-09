import Foundation
import SwiftData
import Combine
import SwiftUI

class TodoViewModel: ObservableObject {
    // 数据状态
    @Published private(set) var todoItems: [TodoItem] = []
    @Published var errorMessage: String?
    @Published var systemReminderMessage: String?
    @Published var systemReminderErrorMessage: String?
    
    // 模型上下文
    private var modelContext: ModelContext
    private let notificationScheduler: any TodoNotificationSchedulingProviding
    private let systemReminderAgent: any SystemReminderAgentProviding
    private let systemReminderWriter: any SystemReminderWritingProviding
    private let reminderModeStore: any TodoReminderModeProviding
    private let saveModelContext: (ModelContext) throws -> Void
    private var cancellables = Set<AnyCancellable>()
    
    // 初始化方法
    init(
        modelContext: ModelContext?,
        notificationScheduler: any TodoNotificationSchedulingProviding = LocalTodoNotificationService.shared,
        systemReminderAgent: any SystemReminderAgentProviding = SystemReminderAgent(),
        systemReminderWriter: any SystemReminderWritingProviding = SystemReminderService.shared,
        reminderModeStore: any TodoReminderModeProviding = TodoReminderModeStore(),
        saveModelContext: @escaping (ModelContext) throws -> Void = { try $0.save() }
    ) {
        if let context = modelContext {
            self.modelContext = context
        } else {
            self.modelContext = Self.makeFallbackContext()
        }
        self.notificationScheduler = notificationScheduler
        self.systemReminderAgent = systemReminderAgent
        self.systemReminderWriter = systemReminderWriter
        self.reminderModeStore = reminderModeStore
        self.saveModelContext = saveModelContext
        
        // 加载待办列表
        loadTodoItems()

        NotificationCenter.default.publisher(for: .easyNoteBackupDidImport)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.loadTodoItems()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - 数据管理方法
    
    /// 加载所有待办事项
    private func loadTodoItems() {
        let descriptor = FetchDescriptor<TodoItem>(sortBy: [SortDescriptor(\.creationDate, order: .forward)])
        
        do {
            todoItems = try modelContext.fetch(descriptor)
            reconcileTodoNotificationsIfNeeded()
            print("从数据库加载了 \(todoItems.count) 个待办事项")
        } catch {
            print("加载待办事项失败: \(error)")
            todoItems = []
        }
    }
    
    func updateModelContext(_ newContext: ModelContext) {
        modelContext = newContext
        loadTodoItems()
    }
    
    /// 标记待办事项为已完成或未完成
    @discardableResult
    func toggleTodoCompletion(for id: UUID) -> Bool {
        if let index = todoItems.firstIndex(where: { $0.id == id }) {
            let wasCompleted = todoItems[index].isCompleted

            // 修改内存中的模型
            todoItems[index].isCompleted.toggle()

            let item = todoItems[index]
            let newTodo = TodoRecurrencePlanner.nextTodo(afterCompleted: item)

            if let newTodo {
                modelContext.insert(newTodo)
            }

            guard saveContext() else {
                todoItems[index].isCompleted = wasCompleted
                return false
            }

            if let newTodo {
                withAnimation {
                    todoItems.append(newTodo)
                }
            }

            synchronizeReminderOutputsAfterSaving(
                changedTodos: [item] + (newTodo.map { [$0] } ?? []),
                completedTodoIDs: item.isCompleted ? [item.id] : []
            )

            return true
        }

        errorMessage = "未找到待办事项"
        return false
    }
    
    /// 重置所有待办事项
    @discardableResult
    func resetAllTodoItems() -> Bool {
        for i in 0..<todoItems.count {
            todoItems[i].isCompleted = false
        }
        // 保存更改到数据库
        guard saveContext() else {
            return false
        }

        synchronizeReminderOutputsAfterSaving(changedTodos: todoItems)
        return true
    }
    
    /// 删除指定ID的待办事项
    @discardableResult
    func deleteTodoItem(withID id: UUID, completion: (() -> Void)? = nil) -> Bool {
        if let index = todoItems.firstIndex(where: { $0.id == id }) {
            let itemToDelete = todoItems[index]
            
            // 从数据库中删除
            modelContext.delete(itemToDelete)
            
            // 保存更改
            if saveContext() {
                // 从内存中的列表删除
                _ = withAnimation {
                    todoItems.remove(at: index)
                }
                removeReminderOutputsAfterDeleting(todoID: id)
                completion?()
                return true
            }
        }

        return false
    }
    
    /// 创建待办事项
    @discardableResult
    func addTodoItem(title: String, priority: TodoItem.PriorityLevel = .medium, deadline: Date? = nil, notes: String? = nil, isRecurring: Bool = false, recurringInterval: String? = nil) -> Bool {
        let newTodo = TodoItem(
            id: UUID(),
            title: title,
            isCompleted: false,
            priority: priority,
            deadline: deadline,
            notes: notes,
            isRecurring: isRecurring,
            recurringInterval: recurringInterval
        )

        return addTodoItem(newTodo)
    }

    /// 插入已构造的待办事项，供创建后立即编辑的入口复用同一个模型对象。
    @discardableResult
    func addTodoItem(_ todo: TodoItem) -> Bool {
        modelContext.insert(todo)
        guard saveContext() else {
            return false
        }

        withAnimation {
            todoItems.append(todo)
        }

        synchronizeReminderOutputsAfterSaving(changedTodos: [todo])

        return true
    }
    
    /// 编辑待办事项
    @discardableResult
    func updateTodoItem(id: UUID, title: String, priority: TodoItem.PriorityLevel, deadline: Date?, notes: String?, isRecurring: Bool = false, recurringInterval: String? = nil) -> Bool {
        if let index = todoItems.firstIndex(where: { $0.id == id }) {
            let oldTitle = todoItems[index].title
            let oldPriority = todoItems[index].priority
            let oldDeadline = todoItems[index].deadline
            let oldNotes = todoItems[index].notes
            let oldIsRecurring = todoItems[index].isRecurring
            let oldRecurringInterval = todoItems[index].recurringInterval

            withAnimation {
                todoItems[index].title = title
                todoItems[index].priority = priority
                todoItems[index].deadline = deadline
                todoItems[index].notes = notes
                todoItems[index].isRecurring = isRecurring
                todoItems[index].recurringInterval = recurringInterval
            }
            
            // 保存到数据库
            guard saveContext() else {
                todoItems[index].title = oldTitle
                todoItems[index].priority = oldPriority
                todoItems[index].deadline = oldDeadline
                todoItems[index].notes = oldNotes
                todoItems[index].isRecurring = oldIsRecurring
                todoItems[index].recurringInterval = oldRecurringInterval
                return false
            }

            synchronizeReminderOutputsAfterSaving(changedTodos: [todoItems[index]])

            return true
        }

        errorMessage = "未找到待办事项"
        return false
    }
    
    /// 通过推荐创建待办项
    @discardableResult
    func createTodoFromRecommendation(_ title: String, priority: TodoItem.PriorityLevel = .medium) -> Bool {
        return addTodoItem(
            title: title,
            priority: priority,
            deadline: Date().addingTimeInterval(3600), // 默认1小时后
            notes: nil
        )
    }
    
    @discardableResult
    private func saveContext() -> Bool {
        do {
            try saveModelContext(modelContext)
            errorMessage = nil
            return true
        } catch {
            modelContext.rollback()
            errorMessage = "保存待办事项失败: \(error.localizedDescription)"
            print("保存待办事项失败: \(error)")
            return false
        }
    }

    private func synchronizeReminderOutputsAfterSaving(
        changedTodos: [TodoItem],
        completedTodoIDs: [UUID] = []
    ) {
        switch reminderModeStore.currentMode {
        case .off:
            return
        case .localNotification:
            notificationScheduler.reconcileNotifications(for: todoItems)
        case .systemReminderAgent:
            completedTodoIDs.forEach { completeSystemReminderIfNeeded(for: $0) }
            changedTodos
                .filter { !completedTodoIDs.contains($0.id) }
                .forEach { applySystemReminderIfNeeded(for: $0) }
        }
    }

    private func removeReminderOutputsAfterDeleting(todoID: UUID) {
        switch reminderModeStore.currentMode {
        case .off:
            return
        case .localNotification:
            notificationScheduler.cancelNotification(forTodoID: todoID)
            notificationScheduler.reconcileNotifications(for: todoItems)
        case .systemReminderAgent:
            removeSystemReminderIfNeeded(for: todoID)
        }
    }

    private func reconcileTodoNotificationsIfNeeded() {
        guard reminderModeStore.currentMode == .localNotification else {
            return
        }

        notificationScheduler.reconcileNotifications(for: todoItems)
    }

    private func applySystemReminderIfNeeded(for todo: TodoItem) {
        guard reminderModeStore.currentMode == .systemReminderAgent else {
            return
        }

        let proposal = systemReminderAgent.proposal(
            for: todo,
            mode: reminderModeStore.currentMode,
            context: .current
        )

        guard proposal.action == .createOrUpdate else {
            systemReminderMessage = proposal.reason
            systemReminderErrorMessage = nil
            return
        }

        systemReminderWriter.applyProposal(proposal) { [weak self] result in
            switch result {
            case .success(let writeResult):
                self?.systemReminderMessage = Self.systemReminderMessage(for: writeResult, proposal: proposal)
                self?.systemReminderErrorMessage = nil
            case .failure(let error):
                self?.systemReminderErrorMessage = error.localizedDescription
            }
        }
    }

    private func completeSystemReminderIfNeeded(for id: UUID) {
        guard reminderModeStore.currentMode == .systemReminderAgent else {
            return
        }

        systemReminderWriter.completeReminder(forTodoID: id) { [weak self] result in
            switch result {
            case .success:
                self?.systemReminderMessage = "系统提醒事项已标记完成"
                self?.systemReminderErrorMessage = nil
            case .failure(let error):
                self?.systemReminderErrorMessage = error.localizedDescription
            }
        }
    }

    private func removeSystemReminderIfNeeded(for id: UUID) {
        guard reminderModeStore.currentMode == .systemReminderAgent else {
            return
        }

        systemReminderWriter.removeReminder(forTodoID: id) { [weak self] result in
            switch result {
            case .success:
                self?.systemReminderMessage = "系统提醒事项已移除"
                self?.systemReminderErrorMessage = nil
            case .failure(let error):
                self?.systemReminderErrorMessage = error.localizedDescription
            }
        }
    }

    private static func systemReminderMessage(
        for result: SystemReminderWriteResult,
        proposal: SystemReminderProposal
    ) -> String {
        switch result {
        case .created:
            return "已创建系统提醒事项：\(proposal.reason)"
        case .updated:
            return "已更新系统提醒事项：\(proposal.reason)"
        case .skipped:
            return proposal.reason
        case .completed:
            return "系统提醒事项已标记完成"
        case .removed:
            return "系统提醒事项已移除"
        case .notFound:
            return "没有找到对应的系统提醒事项"
        }
    }
    
    private static func makeFallbackContext() -> ModelContext {
        do {
            let container = try ModelContainer(for: TodoItem.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            return ModelContext(container)
        } catch {
            fatalError("无法创建待办事项ModelContext: \(error)")
        }
    }
    
    /// 添加测试数据（仅用于预览）
    func addSampleData() {
        // 添加几个示例待办事项
        addTodoItem(
            title: "完成项目报告",
            priority: .high,
            deadline: Date().addingTimeInterval(86400), // 明天
            notes: "需要包含第三季度的销售数据分析"
        )
        
        addTodoItem(
            title: "购买生日礼物",
            priority: .medium,
            deadline: Date().addingTimeInterval(259200) // 3天后
        )
        
        addTodoItem(
            title: "安排团队会议",
            priority: .low
        )
    }
} 
