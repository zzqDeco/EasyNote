import SwiftUI
import SwiftData

// 循环间隔枚举引用
typealias RecurringInterval = TodoItem.RecurringInterval

struct ExploreView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel: ExploreViewModel
    @StateObject private var todoViewModel: TodoViewModel
    @State private var editingTodo: TodoItem? = nil
    @State private var isEditingTodo = false
    @State private var editTitle: String = ""
    @State private var editPriority: TodoItem.PriorityLevel = .medium
    @State private var editDeadline: Date? = nil
    @State private var editNotes: String = ""
    @State private var editIsRecurring = false
    @State private var editRecurringInterval: RecurringInterval = .daily
    @State private var showAllTodos = false
    @State private var showAllTodosSheet = false
    @State private var isRefreshing = false
    @State private var showToast = false
    @State private var toastMessage = ""
    @State private var toastSuccess = true
    @State private var rotationDegree: Double = 0
    
    // 初始化方法
    init(viewModel: ExploreViewModel? = nil, todoViewModel: TodoViewModel? = nil) {
        if let vm = viewModel {
            self._viewModel = StateObject(wrappedValue: vm)
        } else {
            // 使用环境中的ModelContext创建ViewModel
            // 注：这里实际不会使用，因为在View初始化时环境尚未建立
            self._viewModel = StateObject(wrappedValue: ExploreViewModel(modelContext: nil))
        }
        
        if let todoVM = todoViewModel {
            self._todoViewModel = StateObject(wrappedValue: todoVM)
        } else {
            // 创建一个临时ModelContext
            do {
                let container = try ModelContainer(for: TodoItem.self)
                self._todoViewModel = StateObject(wrappedValue: TodoViewModel(modelContext: ModelContext(container)))
            } catch {
                // 如果失败，使用内存存储
                let config = ModelConfiguration(isStoredInMemoryOnly: true)
                do {
                    let container = try ModelContainer(for: TodoItem.self, configurations: config)
                    self._todoViewModel = StateObject(wrappedValue: TodoViewModel(modelContext: ModelContext(container)))
                } catch {
                    fatalError("无法创建TodoViewModel: \(error)")
                }
            }
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    // 头部信息
                    VStack(alignment: .leading) {
                        // 标题和刷新按钮
                        HStack {
                            Text("个性化推荐")
                                .font(.title2)
                                .fontWeight(.bold)
                                .padding(.top, 5)
                            
                            Spacer()
                            
                            // 刷新按钮
                            Button {
                                // 使用更自然的动画效果
                                withAnimation(.easeInOut(duration: 0.8)) {
                                    rotationDegree += 360
                                    isRefreshing = true
                                }
                                
                                // 执行刷新操作
                                viewModel.generateRecommendations(forceUpdate: true)
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .foregroundColor(viewModel.errorMessage != nil ? .red : .blue)
                                    .imageScale(.large)
                                    .rotationEffect(Angle(degrees: rotationDegree))
                                    .overlay(
                                        Circle()
                                            .stroke(isRefreshing ? 
                                                    Color.blue.opacity(0.3) : Color.clear, 
                                                    lineWidth: isRefreshing ? 2 : 0)
                                            .frame(width: 30, height: 30)
                                    )
                            }
                        }
                        
                        // 最后更新时间
                        if let lastUpdated = viewModel.lastUpdated {
                            Text("更新于: \(lastUpdated.formatted(.dateTime.hour().minute()))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.bottom, 5)
                        }
                        
                        // 待办事项区域，只显示今日待办
                        todoSection(title: "今日待办", items: todoViewModel.todoItems.filter { item in
                            if let deadline = item.deadline {
                                return Calendar.current.isDateInToday(deadline)
                            }
                            return false
                        })
                        
                        // 显示全部/隐藏按钮，修改为打开弹出页面
                        HStack {
                            Spacer()
                            
                            Button {
                                showAllTodosSheet = true
                            } label: {
                                HStack(spacing: 5) {
                                    Text("查看全部")
                                        .font(.caption)
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                }
                                .foregroundColor(.blue)
                            }
                        }
                        .padding(.top, 5)
                        
                        // 分隔符
                        Divider()
                            .padding(.vertical, 10)
                        
                        // 推荐活动
                        Text("今日推荐活动")
                            .font(.title2)
                            .fontWeight(.bold)
                    }
                    .padding(.horizontal)
                    
                    // 推荐活动列表
                    if viewModel.isLoading {
                        // 加载中状态
                        VStack {
                            ProgressView()
                                .padding()
                            Text("正在生成推荐...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                    } else if let error = viewModel.errorMessage {
                        // 错误状态
                        VStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.red)
                                .padding()
                            
                            Text("获取推荐失败")
                                .font(.headline)
                                .foregroundColor(.red)
                                .padding(.bottom, 5)
                            
                            Text(error)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                            
                            Button {
                                // 点击重试时开始动画
                                withAnimation(.easeInOut(duration: 0.8)) {
                                    isRefreshing = true
                                    rotationDegree += 360
                                }
                                viewModel.generateRecommendations(forceUpdate: true)
                            } label: {
                                HStack {
                                    Image(systemName: "arrow.clockwise")
                                    Text("重试")
                                }
                                .font(.subheadline)
                                .padding(.horizontal, 25)
                                .padding(.vertical, 10)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                            }
                            .padding()
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red.opacity(0.05))
                        .cornerRadius(12)
                        .padding(.horizontal)
                    } else {
                        // 推荐内容
                        LazyVStack(spacing: 15) {
                            ForEach(viewModel.recommendations) { recommendation in
                                recommendationCard(recommendation)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .navigationTitle("探索")
                
                // Toast提示
                if showToast {
                    VStack {
                        Spacer()
                        
                        HStack(spacing: 10) {
                            Image(systemName: toastSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(toastSuccess ? .green : .red)
                                .imageScale(.large)
                            
                            Text(toastMessage)
                                .font(.subheadline)
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.black.opacity(0.8))
                        )
                        .shadow(color: toastSuccess ? .green.opacity(0.3) : .red.opacity(0.3), radius: 5)
                        .padding(.bottom, 150)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    .frame(maxWidth: .infinity)
                    .zIndex(100)
                }
            }
        }
        .sheet(isPresented: $isEditingTodo) {
            editTodoSheet
        }
        .onReceive(viewModel.$isLoading) { loading in
            // 当加载状态变为false时，停止刷新动画
            if !loading && isRefreshing {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isRefreshing = false
                    
                    // 显示Toast消息
                    toastSuccess = viewModel.errorMessage == nil
                    toastMessage = viewModel.errorMessage ?? "推荐已刷新"
                    showToast = true
                    
                    // 4秒后隐藏Toast
                    DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                        withAnimation(.easeOut) {
                            showToast = false
                        }
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showAllTodosSheet) {
            // 全部待办事项弹出页面
            NavigationView {
                VStack {
                    // 全部待办事项列表
                    if todoViewModel.todoItems.isEmpty {
                        VStack {
                            Spacer()
                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 60))
                                .foregroundColor(.gray)
                                .padding()
                            
                            Text("暂无待办事项")
                                .font(.title3)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                    } else {
                        List {
                            ForEach(todoViewModel.todoItems.sorted(by: { 
                                // 按照截止日期排序，完成的项目放在最后
                                if $0.isCompleted && !$1.isCompleted { return false }
                                if !$0.isCompleted && $1.isCompleted { return true }
                                
                                // 同为完成或未完成状态，按截止日期排序
                                if let date1 = $0.deadline, let date2 = $1.deadline {
                                    return date1 < date2
                                } else if $0.deadline != nil {
                                    return true
                                } else if $1.deadline != nil {
                                    return false
                                }
                                
                                // 默认按创建日期排序
                                return $0.creationDate > $1.creationDate
                            })) { item in
                                SwipeableTodoItemView(
                                    item: item,
                                    todoViewModel: todoViewModel,
                                    onEdit: { showEditTodoSheet(item) }
                                )
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 5, leading: 10, bottom: 5, trailing: 10))
                            }
                        }
                        .listStyle(PlainListStyle())
                    }
                }
                .navigationTitle("全部待办事项")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            showAllTodosSheet = false
                        } label: {
                            Text("关闭")
                        }
                    }
                    
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            createNewTodo()
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
        }
        .onAppear {
            viewModel.generateRecommendations()
        }
    }
    
    // 推荐卡片
    private func recommendationCard(_ recommendation: Recommendation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                // 推荐内容和优先级指示
                HStack(alignment: .center, spacing: 10) {
                    Circle()
                        .fill(recommendation.priority.color)
                        .frame(width: 10, height: 10)
                    
                    Text(recommendation.title)
                        .font(.headline)
                        .lineLimit(1)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Spacer()
                
                // 添加到待办按钮
                AddToTodoButton(recommendation: recommendation, todoViewModel: todoViewModel)
            }
            
            // 获取主题标签（假设从推荐内容中提取）
            HStack {
                ForEach(getThemesFromRecommendation(recommendation), id: \.self) { theme in
                    Text(theme)
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(5)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .frame(height: 90)
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(10)
    }
    
    // 从推荐内容中提取主题的辅助方法
    private func getThemesFromRecommendation(_ recommendation: Recommendation) -> [String] {
        // 简单实现：根据推荐内容关键词生成标签
        let title = recommendation.title.lowercased()
        var themes: [String] = []
        
        if title.contains("读") || title.contains("书") || title.contains("阅读") {
            themes.append("阅读")
        }
        
        if title.contains("锻炼") || title.contains("运动") || title.contains("健身") {
            themes.append("健康")
        }
        
        if title.contains("学习") || title.contains("技能") {
            themes.append("学习")
        }
        
        if title.contains("冥想") || title.contains("放松") || title.contains("休息") {
            themes.append("放松")
        }
        
        if title.contains("朋友") || title.contains("家人") || title.contains("联系") {
            themes.append("社交")
        }
        
        // 如果没有匹配任何标签，添加一个默认标签
        if themes.isEmpty {
            themes.append("活动")
        }
        
        return themes
    }
    
    // 待办事项分区视图
    private func todoSection(title: String, items: [TodoItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title2)
                .fontWeight(.bold)
            
            if items.isEmpty {
                // 空状态
                VStack {
                    Image(systemName: "checkmark.circle")
                        .font(.largeTitle)
                        .foregroundColor(.gray)
                        .padding(.top, 10)
                    
                    Text("暂无待办事项")
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 10)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 110) // 与待办项保持相同的高度
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(10)
            } else {
                // 待办列表
                ForEach(items) { item in
                    SwipeableTodoItemView(
                        item: item,
                        todoViewModel: todoViewModel,
                        onEdit: { showEditTodoSheet(item) }
                    )
                    .transition(.opacity.combined(with: .slide))
                }
            }
        }
    }
    
    // 待办事项卡片（供SwipeableTodoItemView使用）
    private func todoItemContent(_ item: TodoItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 15) {
                // 完成状态按钮
                Button {
                    todoViewModel.toggleTodoCompletion(for: item.id)
                } label: {
                    Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(item.isCompleted ? .green : .gray)
                        .font(.title3)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    // 标题
                    Text(item.title)
                        .font(.headline)
                        .strikethrough(item.isCompleted)
                        .foregroundColor(item.isCompleted ? .gray : .primary)
                    
                    HStack {
                        // 优先级指示器
                        HStack(spacing: 5) {
                            Circle()
                                .fill(item.priority.color)
                                .frame(width: 8, height: 8)
                            
                            Text(priorityText(item.priority))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        // 截止日期（如果有）
                        if let deadline = item.deadline {
                            HStack(spacing: 3) {
                                Image(systemName: "calendar")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                
                                Text(formatDeadline(deadline))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        // 循环指示器（如果是循环待办）
                        if item.isRecurring {
                            HStack(spacing: 3) {
                                Image(systemName: "repeat")
                                    .font(.caption2)
                                    .foregroundColor(.blue)
                                
                                if let interval = item.recurringInterval {
                                    Text(interval)
                                        .font(.caption2)
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }
                
                Spacer()
            }
            
            // 备注（如果有）
            if let notes = item.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .padding(.leading, 35)
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(10)
    }
    
    // 优先级文本
    private func priorityText(_ priority: TodoItem.PriorityLevel) -> String {
        switch priority {
        case .high: return "高优先级"
        case .medium: return "中优先级"
        case .low: return "低优先级"
        }
    }
    
    // 格式化截止日期
    private func formatDeadline(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    // 显示编辑待办事项的Sheet
    private func showEditTodoSheet(_ item: TodoItem) {
        editingTodo = item
        editTitle = item.title
        editPriority = item.priority
        editDeadline = item.deadline
        editNotes = item.notes ?? ""
        editIsRecurring = item.isRecurring
        
        if let intervalString = item.recurringInterval,
           let interval = RecurringInterval(rawValue: intervalString) {
            editRecurringInterval = interval
        } else {
            editRecurringInterval = .daily
        }
        
        isEditingTodo = true
    }
    
    // 编辑待办事项Sheet
    private var editTodoSheet: some View {
        NavigationView {
            Form {
                Section(header: Text("待办内容")) {
                    TextField("标题", text: $editTitle)
                    
                    Picker("优先级", selection: $editPriority) {
                        Text("高").tag(TodoItem.PriorityLevel.high)
                        Text("中").tag(TodoItem.PriorityLevel.medium)
                        Text("低").tag(TodoItem.PriorityLevel.low)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                
                Section(header: Text("截止日期")) {
                    Toggle(isOn: Binding(
                        get: { editDeadline != nil },
                        set: { if $0 { editDeadline = Date() } else { editDeadline = nil } }
                    )) {
                        Text("设置截止日期")
                    }
                    
                    if editDeadline != nil {
                        DatePicker("选择日期", selection: Binding(
                            get: { editDeadline ?? Date() },
                            set: { editDeadline = $0 }
                        ), displayedComponents: [.date, .hourAndMinute])
                        
                        // 循环选项
                        Toggle(isOn: $editIsRecurring) {
                            Text("循环待办")
                        }
                        
                        if editIsRecurring {
                            Picker("循环周期", selection: $editRecurringInterval) {
                                Text("每天").tag(RecurringInterval.daily)
                                Text("每周").tag(RecurringInterval.weekly)
                                Text("两周").tag(RecurringInterval.biweekly)
                                Text("每月").tag(RecurringInterval.monthly)
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
                    TextEditor(text: $editNotes)
                        .frame(height: 100)
                }
            }
            .navigationTitle("编辑待办事项")
            .navigationBarItems(
                leading: Button("取消") {
                    isEditingTodo = false
                },
                trailing: Button("保存") {
                    if let todo = editingTodo {
                        todoViewModel.updateTodoItem(
                            id: todo.id,
                            title: editTitle,
                            priority: editPriority,
                            deadline: editDeadline,
                            notes: editNotes.isEmpty ? nil : editNotes,
                            isRecurring: editIsRecurring && editDeadline != nil,
                            recurringInterval: editIsRecurring && editDeadline != nil ? editRecurringInterval.rawValue : nil
                        )
                    }
                    isEditingTodo = false
                }
                .disabled(editTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            )
        }
    }
    
    // 创建新的待办事项
    private func createNewTodo() {
        let newTodo = TodoItem(title: "新待办事项")
        todoViewModel.addTodoItem(title: newTodo.title)
        
        // 设置为编辑状态
        editingTodo = newTodo
        isEditingTodo = true
        
        // 初始化编辑值
        editTitle = newTodo.title
        editPriority = newTodo.priority
        editDeadline = newTodo.deadline
        editNotes = newTodo.notes ?? ""
        editIsRecurring = newTodo.isRecurring
        if let intervalString = newTodo.recurringInterval,
           let interval = RecurringInterval(rawValue: intervalString) {
            editRecurringInterval = interval
        } else {
            editRecurringInterval = .daily
        }
    }
}

// 可滑动的待办事项视图
struct SwipeableTodoItemView: View {
    let item: TodoItem
    let todoViewModel: TodoViewModel
    let onEdit: () -> Void
    
    @State private var offset: CGFloat = 0
    @State private var isSwiped = false
    @State private var showDeleteAlert = false
    
    // 定义固定高度和内容部分的高度
    private let itemHeight: CGFloat = 110
    private let contentHeight: CGFloat = 90 // 内容实际高度(itemHeight - 垂直padding)
    
    var body: some View {
        ZStack {
            // 背景按钮层
            HStack(spacing: 0) {
                Spacer()
                
                // 编辑按钮
                Button {
                    offset = 0
                    isSwiped = false
                    onEdit()
                } label: {
                    Image(systemName: "square.and.pencil")
                        .foregroundColor(.white)
                        .frame(width: 60, height: contentHeight)
                        .background(Color.blue)
                }
                
                // 删除按钮
                Button {
                    offset = 0
                    isSwiped = false
                    showDeleteAlert = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.white)
                        .frame(width: 60, height: contentHeight)
                        .background(Color.red)
                }
            }
            .cornerRadius(10)
            
            // 内容层
            VStack {
                todoItemContentView
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(10)
                    .contentShape(Rectangle()) // 确保整个区域可点击
                    .onTapGesture {
                        // 点击内容区域打开详情视图，而不是编辑视图
                        navigateToDetailView()
                    }
            }
            .frame(maxWidth: .infinity)
            .offset(x: offset)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        // 只允许向左滑动（负值）
                        if value.translation.width < 0 {
                            offset = value.translation.width
                        }
                    }
                    .onEnded { value in
                        withAnimation {
                            if value.translation.width < -50 {
                                // 滑动超过阈值，显示按钮
                                offset = -120
                                isSwiped = true
                            } else {
                                // 恢复原位
                                offset = 0
                                isSwiped = false
                            }
                        }
                    }
            )
            .alert(isPresented: $showDeleteAlert) {
                Alert(
                    title: Text("删除待办事项"),
                    message: Text("确定要删除\"\(item.title)\"吗？此操作不能撤销。"),
                    primaryButton: .destructive(Text("删除")) {
                        todoViewModel.deleteTodoItem(withID: item.id)
                    },
                    secondaryButton: .cancel(Text("取消"))
                )
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: itemHeight)
    }
    
    // 待办事项内容视图
    private var todoItemContentView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 15) {
                // 完成状态按钮
                Button {
                    todoViewModel.toggleTodoCompletion(for: item.id)
                } label: {
                    Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(item.isCompleted ? .green : .gray)
                        .font(.title3)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    // 标题
                    Text(item.title)
                        .font(.headline)
                        .strikethrough(item.isCompleted)
                        .foregroundColor(item.isCompleted ? .gray : .primary)
                        .lineLimit(1) // 限制为1行
                    
                    HStack {
                        // 优先级指示器
                        HStack(spacing: 5) {
                            Circle()
                                .fill(item.priority.color)
                                .frame(width: 8, height: 8)
                            
                            Text(priorityText(item.priority))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        // 截止日期（如果有）
                        if let deadline = item.deadline {
                            HStack(spacing: 3) {
                                Image(systemName: "calendar")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                
                                Text(formatDeadline(deadline))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        // 循环指示器（如果是循环待办）
                        if item.isRecurring {
                            HStack(spacing: 3) {
                                Image(systemName: "repeat")
                                    .font(.caption2)
                                    .foregroundColor(.blue)
                                
                                if let interval = item.recurringInterval {
                                    Text(interval)
                                        .font(.caption2)
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }
                
                Spacer()
            }
            
            // 备注（如果有）
            if let notes = item.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2) // 限制为2行
                    .padding(.leading, 35)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .frame(height: contentHeight)
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(10)
        .clipped() // 裁剪溢出内容
    }
    
    // 优先级文本
    private func priorityText(_ priority: TodoItem.PriorityLevel) -> String {
        switch priority {
        case .high: return "高优先级"
        case .medium: return "中优先级"
        case .low: return "低优先级"
        }
    }
    
    // 格式化截止日期
    private func formatDeadline(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    // 添加导航到详情页的方法
    private func navigateToDetailView() {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootViewController = window.rootViewController {
            let hostingController = UIHostingController(rootView:
                NavigationStack {
                    TodoDetailView(viewModel: todoViewModel, item: item)
                }
            )
            if let navigationController = rootViewController as? UINavigationController {
                navigationController.pushViewController(hostingController, animated: true)
            } else {
                rootViewController.present(hostingController, animated: true)
            }
        }
    }
}

// 预览
#Preview {
    // 使用内存中的配置创建轻量级预览容器
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    do {
        let container = try ModelContainer(for: DiaryEntry.self, configurations: config)
        let context = ModelContext(container)
        let viewModel = ExploreViewModel(modelContext: context)
        
        // 添加一些测试数据
        let entry1 = DiaryEntry(title: "今天的工作", content: "今天完成了很多任务，明天需要继续跟进项目进度。", mood: "平静")
        let entry2 = DiaryEntry(title: "跑步感受", content: "今天跑步5公里，感觉很棒。希望能够保持这个习惯。", mood: "开心")
        context.insert(entry1)
        context.insert(entry2)
        
        return ExploreView(viewModel: viewModel)
            .modelContainer(container)
    } catch {
        return Text("预览加载失败: \(error.localizedDescription)")
    }
}

// 添加待办按钮组件
struct AddToTodoButton: View {
    let recommendation: Recommendation
    let todoViewModel: TodoViewModel
    @State private var isAdding = false
    
    var body: some View {
        Button {
            withAnimation {
                isAdding = true
                todoViewModel.createTodoFromRecommendation(
                    recommendation.title,
                    priority: TodoItem.PriorityLevel(rawValue: recommendation.priority.rawValue) ?? .medium
                )
                
                // 动画完成后重置状态
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isAdding = false
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isAdding ? "checkmark" : "plus")
                    .font(.caption)
                
                if !isAdding {
                    Text("添加")
                        .font(.caption)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isAdding ? Color.green.opacity(0.2) : Color.blue.opacity(0.2))
            .cornerRadius(8)
            .foregroundColor(isAdding ? .green : .blue)
        }
    }
} 