import Foundation
import SwiftData
import Combine
import SwiftUI

class ExploreViewModel: ObservableObject {
    // 数据状态
    @Published var recommendations: [Recommendation] = []
    @Published private(set) var allTodoItems: [TodoItem] = []
    @Published var isLoading = true
    @Published var lastUpdated: Date?
    @Published var errorMessage: String?
    
    // 计算属性：今日待办（只显示今天截止或没有设置截止日期的待办）
    var todoItems: [TodoItem] {
        return allTodoItems.filter { item in
            // 没有设置截止日期的项目
            if item.deadline == nil {
                return true
            }
            
            // 截止日期是今天的项目
            if let deadline = item.deadline {
                let calendar = Calendar.current
                return calendar.isDateInToday(deadline)
            }
            
            return false
        }
    }
    
    // 服务
    private let openAIService: OpenAIService
    
    // 模型上下文
    @Published var modelContext: ModelContext
    
    // 取消令牌
    private var cancellables = Set<AnyCancellable>()
    
    // 初始化方法
    init(modelContext: ModelContext?) {
        self.openAIService = OpenAIService()
        
        if let context = modelContext {
            self.modelContext = context
        } else {
            // 如果没有提供ModelContext，创建一个内存中的临时ModelContext
            do {
                let container = try ModelContainer(for: DiaryEntry.self, TodoItem.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
                self.modelContext = ModelContext(container)
            } catch {
                print("无法创建临时ModelContext: \(error)")
                // 这里不再调用fatalError，而是创建一个空的ModelContainer
                let descriptor = ModelConfiguration(isStoredInMemoryOnly: true)
                do {
                    let container = try ModelContainer(for: DiaryEntry.self, TodoItem.self, configurations: descriptor)
                    self.modelContext = ModelContext(container)
                } catch {
                    print("创建备用ModelContainer失败: \(error)")
                    // 如果还是失败，使用最简单的方法
                    let schema = Schema([DiaryEntry.self, TodoItem.self])
                    let container = try! ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
                    self.modelContext = ModelContext(container)
                }
            }
        }
        
        // 加载待办列表
        loadTodoItems()
        
        // 加载缓存的推荐内容
        loadCachedRecommendations()
    }
    
    // MARK: - 公共方法
    
    /// 生成今日推荐
    /// - Parameter forceUpdate: 是否强制更新，不考虑上次更新时间
    func generateRecommendations(forceUpdate: Bool = false) {
        isLoading = true
        // 重置错误信息
        errorMessage = nil
        
        // 检查是否应该重新生成推荐内容，或者强制更新
        if forceUpdate || shouldGenerateNewRecommendations() {
            // 获取最近七天的日记
            let recentEntries = fetchRecentEntries(days: 7)
            
            if recentEntries.isEmpty {
                // 如果没有最近的日记，生成一些默认的推荐
                generateDefaultRecommendations()
                isLoading = false
                return
            }
            
            // 分析日记内容，生成推荐
            analyzeEntriesAndGenerateRecommendations(entries: recentEntries)
        } else {
            // 不需要重新生成，使用缓存的推荐
            isLoading = false
        }
    }
    
    /// 判断是否应该重新生成推荐
    func shouldGenerateNewRecommendations() -> Bool {
        // 如果从未生成过推荐，或者最后一次更新是昨天或更早，就重新生成
        guard let lastUpdated = lastUpdated else { return true }
        
        let calendar = Calendar.current
        
        // 比较两个日期是否在同一天
        return !calendar.isDateInToday(lastUpdated)
    }
    
    // MARK: - 私有辅助方法
    
    /// 分析日记条目并生成推荐
    private func analyzeEntriesAndGenerateRecommendations(entries: [DiaryEntry]) {
        // 将所有条目的内容合并为一个文本进行分析，包含日期信息
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy年MM月dd日"
        
        let combinedContent = entries.map { entry -> String in
            let dateStr = dateFormatter.string(from: entry.creationDate)
            return "日期: \(dateStr)\n标题: \(entry.title)\n内容: \(entry.content)\n心情: \(entry.mood ?? "未记录")"
        }.joined(separator: "\n\n")
        
        // 添加当前日期信息
        let currentDateStr = dateFormatter.string(from: Date())
        let contentWithCurrentDate = "当前日期: \(currentDateStr)\n\n用户最近的日记内容:\n\n" + combinedContent
        
        // 使用OpenAI API生成推荐
        openAIService.generateRecommendations(from: contentWithCurrentDate)
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { [weak self] completion in
                switch completion {
                case .finished:
                    break
                case .failure(let error):
                    self?.handleAPIError(error)
                }
                self?.isLoading = false
            }, receiveValue: { [weak self] result in
                self?.processRecommendationResponse(result)
                self?.saveRecommendations()
            })
            .store(in: &cancellables)
    }
    
    /// 处理推荐响应
    /// - Parameters:
    ///   - response: AI生成的推荐和待办事项
    private func processRecommendationResponse(_ response: (recommendations: [String], todos: [String])) {
        print("处理AI推荐响应: 收到\(response.recommendations.count)个推荐和\(response.todos.count)个待办事项")
        
        // 清空当前推荐
        recommendations = []
        
        // 处理推荐活动
        for (index, recommendation) in response.recommendations.enumerated() {
            let rec = Recommendation(
                id: UUID(),
                title: recommendation,
                priority: index < 2 ? .high : (index < 4 ? .medium : .low)
            )
            recommendations.append(rec)
        }
        
        // 更新最后更新时间
        lastUpdated = Date()
        
        print("处理完成: \(recommendations.count)个推荐")
    }
    
    /// 生成默认推荐
    private func generateDefaultRecommendations() {
        print("生成默认推荐内容")
        recommendations = [
            Recommendation(id: UUID(), title: "花点时间阅读一本书", priority: .medium),
            Recommendation(id: UUID(), title: "尝试冥想15分钟", priority: .medium),
            Recommendation(id: UUID(), title: "进行30分钟的有氧运动", priority: .high),
            Recommendation(id: UUID(), title: "和朋友或家人联系", priority: .medium),
            Recommendation(id: UUID(), title: "学习一项新技能", priority: .low)
        ]
        
        // 更新最后更新时间
        lastUpdated = Date()
        saveRecommendations()
    }
    
    /// 获取最近几天的日记
    private func fetchRecentEntries(days: Int) -> [DiaryEntry] {
        let calendar = Calendar.current
        guard let fromDate = calendar.date(byAdding: .day, value: -days, to: Date()) else {
            return []
        }
        
        let fetchDescriptor = FetchDescriptor<DiaryEntry>(
            predicate: #Predicate<DiaryEntry> { entry in
                entry.creationDate >= fromDate
            },
            sortBy: [SortDescriptor(\.creationDate, order: .reverse)]
        )
        
        do {
            let entries = try modelContext.fetch(fetchDescriptor)
            return entries
        } catch {
            print("获取最近日记失败: \(error)")
            return []
        }
    }
    
    /// 保存推荐到UserDefaults
    func saveRecommendations() {
        let recommendationsData = try? JSONEncoder().encode(recommendations)
        UserDefaults.standard.set(recommendationsData, forKey: "cached_recommendations")
        UserDefaults.standard.set(lastUpdated, forKey: "recommendations_last_updated")
    }
    
    /// 从UserDefaults加载缓存的推荐内容
    private func loadCachedRecommendations() {
        print("开始加载缓存的推荐内容")
        if let recommendationsData = UserDefaults.standard.data(forKey: "cached_recommendations"),
           let cachedRecommendations = try? JSONDecoder().decode([Recommendation].self, from: recommendationsData) {
            
            self.recommendations = cachedRecommendations
            self.lastUpdated = UserDefaults.standard.object(forKey: "recommendations_last_updated") as? Date
            
            print("从缓存加载：\(recommendations.count)个推荐")
            
            // 即使加载了缓存，也应该检查是否需要更新
            if shouldGenerateNewRecommendations() {
                // 重置错误信息
                errorMessage = nil
                generateRecommendations()
            } else {
                isLoading = false
            }
        } else {
            print("没有找到缓存数据，将生成新的推荐")
            // 没有缓存的数据，生成新的推荐
            generateRecommendations()
        }
    }
    
    /// 处理API错误
    private func handleAPIError(_ error: Error) {
        // 提供更具体的错误信息
        if let networkError = error as? URLError {
            switch networkError.code {
            case .notConnectedToInternet:
                errorMessage = "网络连接已断开，请检查您的网络设置后重试"
            case .timedOut:
                errorMessage = "请求超时，服务器可能暂时不可用"
            case .cannotConnectToHost:
                errorMessage = "无法连接到服务器，请稍后重试"
            default:
                errorMessage = "网络错误: \(networkError.localizedDescription)"
            }
        } else {
            errorMessage = "生成推荐时出错: \(error.localizedDescription)"
        }
        
        // 如果当前没有推荐，生成默认推荐
        if recommendations.isEmpty {
            generateDefaultRecommendations()
        }
    }
    
    /// 加载所有待办事项
    private func loadTodoItems() {
        let descriptor = FetchDescriptor<TodoItem>(sortBy: [SortDescriptor(\.creationDate, order: .forward)])
        
        do {
            allTodoItems = try modelContext.fetch(descriptor)
            print("从数据库加载了 \(allTodoItems.count) 个待办事项")
        } catch {
            print("加载待办事项失败: \(error)")
            allTodoItems = []
        }
    }
    
    func updateModelContext(_ newContext: ModelContext) {
        modelContext = newContext
        loadTodoItems()
    }
    
    /// 标记待办事项为已完成或未完成
    @discardableResult
    func toggleTodoCompletion(for id: UUID) -> Bool {
        if let index = allTodoItems.firstIndex(where: { $0.id == id }) {
            let wasCompleted = allTodoItems[index].isCompleted

            // 修改内存中的模型
            allTodoItems[index].isCompleted.toggle()

            let item = allTodoItems[index]
            let newTodo = TodoRecurrencePlanner.nextTodo(afterCompleted: item)

            if let newTodo {
                modelContext.insert(newTodo)
            }

            guard saveContext() else {
                allTodoItems[index].isCompleted = wasCompleted
                if let newTodo {
                    modelContext.delete(newTodo)
                }
                return false
            }

            if let newTodo {
                withAnimation {
                    allTodoItems.append(newTodo)
                }
            }

            return true
        }

        errorMessage = "未找到待办事项"
        return false
    }
    
    /// 重置所有待办事项
    @discardableResult
    func resetAllTodoItems() -> Bool {
        for i in 0..<allTodoItems.count {
            allTodoItems[i].isCompleted = false
        }
        // 保存更改到数据库
        return saveContext()
    }
    
    /// 删除指定ID的待办事项
    @discardableResult
    func deleteTodoItem(withID id: UUID, completion: (() -> Void)? = nil) -> Bool {
        if let index = allTodoItems.firstIndex(where: { $0.id == id }) {
            let item = allTodoItems[index]
            
            modelContext.delete(item)
            
            // 保存更改到数据库
            if saveContext() {
                // 使用动画删除
                withAnimation(.easeInOut(duration: 0.3)) {
                    allTodoItems.remove(at: index)
                }
                completion?()
                return true
            }
        }

        return false
    }
    
    /// 从推荐活动创建待办事项
    @discardableResult
    func createTodoFromRecommendation(_ recommendation: Recommendation) -> Bool {
        let newTodo = TodoItem(
            id: UUID(),
            title: recommendation.title,
            isCompleted: false,
            priority: TodoItem.PriorityLevel(rawValue: recommendation.priority.rawValue) ?? .medium,
            deadline: Date().addingTimeInterval(3600), // 默认1小时后
            notes: nil,
            isRecurring: false
        )
        
        // 保存到数据库
        modelContext.insert(newTodo)
        guard saveContext() else {
            return false
        }

        // 添加到内存中的列表
        withAnimation {
            allTodoItems.append(newTodo)
        }

        return true
    }
    
    /// 编辑待办事项
    @discardableResult
    func updateTodoItem(id: UUID, title: String, priority: TodoItem.PriorityLevel, deadline: Date?, notes: String?, isRecurring: Bool = false, recurringInterval: String? = nil) -> Bool {
        if let index = allTodoItems.firstIndex(where: { $0.id == id }) {
            let oldTitle = allTodoItems[index].title
            let oldPriority = allTodoItems[index].priority
            let oldDeadline = allTodoItems[index].deadline
            let oldNotes = allTodoItems[index].notes
            let oldIsRecurring = allTodoItems[index].isRecurring
            let oldRecurringInterval = allTodoItems[index].recurringInterval

            withAnimation {
                allTodoItems[index].title = title
                allTodoItems[index].priority = priority
                allTodoItems[index].deadline = deadline
                allTodoItems[index].notes = notes
                allTodoItems[index].isRecurring = isRecurring
                allTodoItems[index].recurringInterval = recurringInterval
            }
            
            // 保存到数据库
            guard saveContext() else {
                allTodoItems[index].title = oldTitle
                allTodoItems[index].priority = oldPriority
                allTodoItems[index].deadline = oldDeadline
                allTodoItems[index].notes = oldNotes
                allTodoItems[index].isRecurring = oldIsRecurring
                allTodoItems[index].recurringInterval = oldRecurringInterval
                return false
            }

            return true
        }

        errorMessage = "未找到待办事项"
        return false
    }
    
    /// 创建待办事项
    @discardableResult
    func addTodoItem(_ todo: TodoItem) -> Bool {
        // 保存到数据库
        modelContext.insert(todo)
        guard saveContext() else {
            return false
        }

        // 添加到内存中的列表
        withAnimation {
            allTodoItems.append(todo)
        }

        return true
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
}

/// 推荐的活动
struct Recommendation: Identifiable, Codable {
    var id: UUID
    var title: String
    var priority: Priority
    
    enum Priority: String, Codable {
        case high, medium, low
        
        var color: Color {
            switch self {
            case .high: return .red
            case .medium: return .orange
            case .low: return .blue
            }
        }
    }
} 
