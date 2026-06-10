import Foundation
import SwiftData
import Combine
import SwiftUI

class TodoViewModel: ObservableObject {
    // 数据状态
    @Published private(set) var todoItems: [TodoItem] = []
    @Published var errorMessage: String?
    
    // 模型上下文
    private var modelContext: ModelContext
    
    // 初始化方法
    init(modelContext: ModelContext?) {
        if let context = modelContext {
            self.modelContext = context
        } else {
            self.modelContext = Self.makeFallbackContext()
        }
        
        // 加载待办列表
        loadTodoItems()
    }
    
    // MARK: - 数据管理方法
    
    /// 加载所有待办事项
    private func loadTodoItems() {
        let descriptor = FetchDescriptor<TodoItem>(sortBy: [SortDescriptor(\.creationDate, order: .forward)])
        
        do {
            todoItems = try modelContext.fetch(descriptor)
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
    func toggleTodoCompletion(for id: UUID) {
        if let index = todoItems.firstIndex(where: { $0.id == id }) {
            // 修改内存中的模型
            todoItems[index].isCompleted.toggle()
            
            // 检查是否需要创建下一个循环任务
            let item = todoItems[index]
            
            if todoItems[index].isCompleted && item.isRecurring, 
               let intervalString = item.recurringInterval,
               let interval = TodoItem.RecurringInterval(rawValue: intervalString),
               let deadline = item.deadline {
                
                // 创建下一个循环待办
                let nextDate = interval.nextDate(from: deadline)
                let newTodo = TodoItem(
                    id: UUID(),
                    title: item.title,
                    isCompleted: false,
                    priority: item.priority,
                    deadline: nextDate,
                    notes: item.notes,
                    isRecurring: true,
                    recurringInterval: intervalString
                )
                
                // 添加到待办列表并保存到数据库
                withAnimation {
                    todoItems.append(newTodo)
                    modelContext.insert(newTodo)
                }
            }
            
            // 保存更改到数据库
            saveContext()
        }
    }
    
    /// 重置所有待办事项
    func resetAllTodoItems() {
        for i in 0..<todoItems.count {
            todoItems[i].isCompleted = false
        }
        // 保存更改到数据库
        saveContext()
    }
    
    /// 删除指定ID的待办事项
    func deleteTodoItem(withID id: UUID, completion: (() -> Void)? = nil) {
        if let index = todoItems.firstIndex(where: { $0.id == id }) {
            let itemToDelete = todoItems[index]
            
            // 从数据库中删除
            modelContext.delete(itemToDelete)
            
            // 从内存中的列表删除
            _ = withAnimation {
                todoItems.remove(at: index)
            }
            
            // 保存更改
            if saveContext() {
                completion?()
            }
        }
    }
    
    /// 创建待办事项
    func addTodoItem(title: String, priority: TodoItem.PriorityLevel = .medium, deadline: Date? = nil, notes: String? = nil, isRecurring: Bool = false, recurringInterval: String? = nil) {
        // 创建新的待办事项
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
        
        // 添加到内存中的列表
        withAnimation {
            todoItems.append(newTodo)
        }
        
        // 保存到数据库
        modelContext.insert(newTodo)
        saveContext()
    }
    
    /// 编辑待办事项
    func updateTodoItem(id: UUID, title: String, priority: TodoItem.PriorityLevel, deadline: Date?, notes: String?, isRecurring: Bool = false, recurringInterval: String? = nil) {
        if let index = todoItems.firstIndex(where: { $0.id == id }) {
            withAnimation {
                todoItems[index].title = title
                todoItems[index].priority = priority
                todoItems[index].deadline = deadline
                todoItems[index].notes = notes
                todoItems[index].isRecurring = isRecurring
                todoItems[index].recurringInterval = recurringInterval
            }
            
            // 保存到数据库
            saveContext()
        }
    }
    
    /// 通过推荐创建待办项
    func createTodoFromRecommendation(_ title: String, priority: TodoItem.PriorityLevel = .medium) {
        addTodoItem(
            title: title,
            priority: priority,
            deadline: Date().addingTimeInterval(3600), // 默认1小时后
            notes: nil
        )
    }
    
    @discardableResult
    private func saveContext() -> Bool {
        do {
            try modelContext.save()
            errorMessage = nil
            return true
        } catch {
            errorMessage = "保存待办事项失败: \(error.localizedDescription)"
            print("保存待办事项失败: \(error)")
            return false
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
