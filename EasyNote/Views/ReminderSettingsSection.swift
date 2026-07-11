import SwiftData
import SwiftUI

struct ReminderSettingsSection: View {
    let modelContext: ModelContext
    let scenePhase: ScenePhase

    @AppStorage(LocalTodoNotificationService.enabledDefaultsKey) private var todoNotificationsEnabled = false
    @State private var todoNotificationAuthorizationStatus: TodoNotificationAuthorizationStatus = .notDetermined
    @State private var todoNotificationMessage: String?
    @State private var todoNotificationErrorMessage: String?
    @State private var selectedTodoReminderMode: TodoReminderMode = .off
    @State private var systemReminderAuthorizationStatus: SystemReminderAuthorizationStatus = .notDetermined
    @State private var systemReminderMessage: String?
    @State private var systemReminderErrorMessage: String?
    @State private var reminderWriteTask: Task<Void, Never>?
    @State private var reminderStatusTask: Task<Void, Never>?

    private let todoNotificationScheduler: any TodoNotificationSchedulingProviding
    private let systemReminderAgent: any SystemReminderAgentProviding
    private let systemReminderWriter: any SystemReminderWritingProviding
    private let reminderModeStore: any TodoReminderModeProviding

    init(
        modelContext: ModelContext,
        scenePhase: ScenePhase,
        dependencies: SettingsDependencies
    ) {
        self.modelContext = modelContext
        self.scenePhase = scenePhase
        self.todoNotificationScheduler = dependencies.todoNotificationScheduler
        self.systemReminderAgent = dependencies.systemReminderAgent
        self.systemReminderWriter = dependencies.systemReminderWriter
        self.reminderModeStore = dependencies.reminderModeStore
    }

    var body: some View {
        Section {
            Picker("提醒方式", selection: Binding(
                get: { selectedTodoReminderMode },
                set: { setTodoReminderMode($0) }
            )) {
                ForEach(TodoReminderMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("settings.todoReminderModePicker")

            if selectedTodoReminderMode == .localNotification {
                localNotificationControls
            }

            if selectedTodoReminderMode == .systemReminderAgent {
                systemReminderControls
            }

            reminderModeFeedback
        } header: {
            Text("提醒方式")
        } footer: {
            Text("EasyNote 通知只在本应用内安排本地通知；系统提醒事项会由 Agent 根据待办内容和截止时间写入系统“提醒事项”App。")
        }
        .onAppear {
            selectedTodoReminderMode = reminderModeStore.currentMode
            refreshReminderAuthorizationStatuses()
        }
        .onDisappear {
            reminderStatusTask?.cancel()
            reminderStatusTask = nil
        }
        .onReceive(todoNotificationScheduler.authorizationStatusPublisher) { status in
            todoNotificationAuthorizationStatus = status
        }
        .onReceive(systemReminderWriter.authorizationStatusPublisher) { status in
            systemReminderAuthorizationStatus = status
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                refreshReminderAuthorizationStatuses()
            }
        }
    }

    @ViewBuilder
    private var localNotificationControls: some View {
        HStack {
            Label("通知权限", systemImage: todoNotificationStatusIcon)
                .foregroundColor(todoNotificationStatusColor)

            Spacer()

            Text(todoNotificationStatusText)
                .font(.caption)
                .foregroundColor(.secondary)
        }

        Button {
            requestTodoNotificationAuthorization()
        } label: {
            Label("请求通知权限", systemImage: "bell.badge")
        }
        .disabled(todoNotificationAuthorizationStatus.allowsScheduling)
        .accessibilityIdentifier("settings.requestTodoNotificationPermissionButton")

        Button {
            reconcileTodoNotifications()
        } label: {
            Label("同步 EasyNote 通知", systemImage: "arrow.triangle.2.circlepath")
        }
        .disabled(!todoNotificationAuthorizationStatus.allowsScheduling)
        .accessibilityIdentifier("settings.syncTodoNotificationsButton")

        if let todoNotificationMessage {
            Text(todoNotificationMessage)
                .font(.caption)
                .foregroundColor(.secondary)
        }

        if let todoNotificationErrorMessage {
            Text(todoNotificationErrorMessage)
                .font(.caption)
                .foregroundColor(.red)
        }
    }

    @ViewBuilder
    private var systemReminderControls: some View {
        HStack {
            Label("提醒事项权限", systemImage: systemReminderStatusIcon)
                .foregroundColor(systemReminderStatusColor)

            Spacer()

            Text(systemReminderStatusText)
                .font(.caption)
                .foregroundColor(.secondary)
        }

        Text("Agent 会根据待办内容和截止时间写入系统“提醒事项”App，并自动决定预留时间。")
            .font(.caption)
            .foregroundColor(.secondary)

        Button {
            requestSystemReminderAuthorization()
        } label: {
            Label("请求提醒事项权限", systemImage: "checklist")
        }
        .disabled(systemReminderAuthorizationStatus.allowsWriting)
        .accessibilityIdentifier("settings.requestSystemReminderPermissionButton")

        Button {
            syncCurrentTodosToSystemReminders()
        } label: {
            Label("同步当前待办到系统提醒事项", systemImage: "arrow.triangle.2.circlepath")
        }
        .disabled(!systemReminderAuthorizationStatus.allowsWriting)
        .accessibilityIdentifier("settings.syncSystemRemindersButton")

        if let systemReminderMessage {
            Text(systemReminderMessage)
                .font(.caption)
                .foregroundColor(.secondary)
        }

        if let systemReminderErrorMessage {
            Text(systemReminderErrorMessage)
                .font(.caption)
                .foregroundColor(.red)
        }
    }

    @ViewBuilder
    private var reminderModeFeedback: some View {
        if selectedTodoReminderMode != .localNotification {
            if let todoNotificationMessage {
                Text(todoNotificationMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let todoNotificationErrorMessage {
                Text(todoNotificationErrorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }

        if selectedTodoReminderMode != .systemReminderAgent {
            if let systemReminderMessage {
                Text(systemReminderMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let systemReminderErrorMessage {
                Text(systemReminderErrorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
    }

    private func setTodoReminderMode(_ mode: TodoReminderMode) {
        let previousMode = reminderModeStore.currentMode
        let shouldRemoveSystemReminders = TodoReminderModeTransitionPlanner.shouldRemoveSystemReminders(
            previousMode: previousMode,
            nextMode: mode,
            systemRemindersMayExist: reminderModeStore.systemRemindersMayExist
        )
        let shouldSyncSystemReminders = TodoReminderModeTransitionPlanner.shouldSyncSystemReminders(nextMode: mode)

        selectedTodoReminderMode = mode
        reminderModeStore.currentMode = mode
        todoNotificationMessage = nil
        todoNotificationErrorMessage = nil
        systemReminderMessage = nil
        systemReminderErrorMessage = nil

        switch mode {
        case .off:
            todoNotificationsEnabled = false
            todoNotificationMessage = "已关闭提醒"
            startReminderWriteOperation {
                await todoNotificationScheduler.cancelAllTodoNotifications()
            }
        case .localNotification:
            todoNotificationsEnabled = true
            startReminderWriteOperation {
                do {
                    try await todoNotificationScheduler.requestAuthorization()
                    let synchronized = await reconcileTodoNotificationsNow()
                    if synchronized, shouldRemoveSystemReminders {
                        await removeCurrentSystemRemindersAfterSwitchingToLocalMode()
                    }
                } catch is CancellationError {
                    return
                } catch {
                    todoNotificationsEnabled = false
                    reminderModeStore.currentMode = .off
                    selectedTodoReminderMode = .off
                    await todoNotificationScheduler.cancelAllTodoNotifications()
                    todoNotificationErrorMessage = "EasyNote 通知未开启: \(error.localizedDescription)"
                }
            }
        case .systemReminderAgent:
            todoNotificationsEnabled = false
            startReminderWriteOperation {
                await todoNotificationScheduler.cancelAllTodoNotifications()
                let status = await systemReminderWriter.refreshAuthorizationStatus()
                systemReminderAuthorizationStatus = status
                guard !Task.isCancelled else {
                    return
                }

                if status.allowsWriting {
                    if shouldSyncSystemReminders {
                        await syncCurrentTodosToSystemRemindersNow()
                    } else {
                        systemReminderMessage = "已切换到系统提醒事项模式"
                    }
                } else {
                    systemReminderMessage = "请授予提醒事项权限后同步当前待办"
                }
            }
        }
    }

    @MainActor
    private func removeCurrentSystemRemindersAfterSwitchingToLocalMode() async {
        do {
            let todos = try modelContext.fetch(FetchDescriptor<TodoItem>())
                .sorted { $0.creationDate < $1.creationDate }

            guard !todos.isEmpty else {
                reminderModeStore.systemRemindersMayExist = false
                return
            }

            var successCount = 0
            var firstError: String?

            for todo in todos {
                do {
                    try Task.checkCancellation()
                    try await systemReminderWriter.removeReminder(forTodoID: todo.id)
                    successCount += 1
                } catch is CancellationError {
                    return
                } catch {
                    if firstError == nil {
                        firstError = error.localizedDescription
                    }
                }
            }

            if let firstError {
                todoNotificationErrorMessage = "已切换到 EasyNote 通知，但清理旧系统提醒事项失败: \(firstError)"
            } else if successCount > 0 {
                reminderModeStore.systemRemindersMayExist = false
                todoNotificationMessage = "已同步 EasyNote 通知，并清理 \(successCount) 个系统提醒事项"
            }
        } catch {
            todoNotificationErrorMessage = "已切换到 EasyNote 通知，但读取待办清理系统提醒事项失败: \(error.localizedDescription)"
        }
    }

    private func requestSystemReminderAuthorization() {
        systemReminderMessage = nil
        systemReminderErrorMessage = nil

        startReminderWriteOperation {
            do {
                try await systemReminderWriter.requestAuthorization()
                systemReminderAuthorizationStatus = await systemReminderWriter.refreshAuthorizationStatus()
                if selectedTodoReminderMode == .systemReminderAgent {
                    await syncCurrentTodosToSystemRemindersNow()
                } else {
                    systemReminderMessage = "提醒事项权限已开启"
                }
            } catch is CancellationError {
                return
            } catch {
                systemReminderErrorMessage = error.localizedDescription
            }
        }
    }

    private func syncCurrentTodosToSystemReminders() {
        startReminderWriteOperation {
            await syncCurrentTodosToSystemRemindersNow()
        }
    }

    @MainActor
    private func syncCurrentTodosToSystemRemindersNow() async {
        systemReminderMessage = nil
        systemReminderErrorMessage = nil

        guard selectedTodoReminderMode == .systemReminderAgent else {
            systemReminderErrorMessage = "当前不是系统提醒事项模式"
            return
        }

        guard systemReminderAuthorizationStatus.allowsWriting else {
            systemReminderErrorMessage = "未授予提醒事项权限"
            return
        }

        do {
            let todos = try modelContext.fetch(FetchDescriptor<TodoItem>())
                .sorted { $0.creationDate < $1.creationDate }
            let context = SystemReminderContext(now: Date(), calendar: .current)
            let proposals = todos.map {
                systemReminderAgent.proposal(for: $0, mode: .systemReminderAgent, context: context)
            }
            let operations = proposals
                .map { SystemReminderProposalReconciler.operation(for: $0) }
                .filter { operation in
                    operation != .ignore
                }

            guard !operations.isEmpty else {
                systemReminderMessage = "没有需要写入系统提醒事项的待办"
                return
            }

            var successCount = 0
            var firstError: String?
            var wroteOrCompletedSystemReminder = false

            for operation in operations {
                do {
                    try Task.checkCancellation()
                    switch operation {
                    case .apply(let proposal):
                        _ = try await systemReminderWriter.applyProposal(proposal)
                        successCount += 1
                        wroteOrCompletedSystemReminder = true
                    case .complete(let id):
                        try await systemReminderWriter.completeReminder(forTodoID: id)
                        successCount += 1
                        wroteOrCompletedSystemReminder = true
                    case .remove(let id):
                        try await systemReminderWriter.removeReminder(forTodoID: id)
                        successCount += 1
                    case .ignore:
                        break
                    }
                } catch is CancellationError {
                    return
                } catch {
                    if firstError == nil {
                        firstError = error.localizedDescription
                    }
                }
            }

            if let firstError {
                systemReminderErrorMessage = "同步失败: \(firstError)"
            } else {
                reminderModeStore.systemRemindersMayExist = wroteOrCompletedSystemReminder
                systemReminderMessage = "已同步/清理 \(successCount) 个系统提醒事项"
            }
        } catch {
            systemReminderErrorMessage = "读取待办失败: \(error.localizedDescription)"
        }
    }

    private func setTodoNotificationsEnabled(_ enabled: Bool) {
        guard enabled else {
            setTodoReminderMode(.off)
            return
        }

        setTodoReminderMode(.localNotification)
    }

    private func requestTodoNotificationAuthorization() {
        todoNotificationMessage = nil
        todoNotificationErrorMessage = nil

        startReminderWriteOperation {
            do {
                try await todoNotificationScheduler.requestAuthorization()
                todoNotificationAuthorizationStatus = await todoNotificationScheduler.refreshAuthorizationStatus()
                todoNotificationMessage = "通知权限已开启"
                if selectedTodoReminderMode == .localNotification {
                    _ = await reconcileTodoNotificationsNow()
                }
            } catch is CancellationError {
                return
            } catch {
                todoNotificationsEnabled = false
                reminderModeStore.currentMode = .off
                selectedTodoReminderMode = .off
                await todoNotificationScheduler.cancelAllTodoNotifications()
                todoNotificationErrorMessage = error.localizedDescription
            }
        }
    }

    private func reconcileTodoNotifications() {
        startReminderWriteOperation {
            _ = await reconcileTodoNotificationsNow()
        }
    }

    @MainActor
    private func reconcileTodoNotificationsNow() async -> Bool {
        do {
            let todos = try modelContext.fetch(FetchDescriptor<TodoItem>())
                .sorted { $0.creationDate < $1.creationDate }
            let now = Date()
            let eligibleCount = todos.filter { TodoNotificationPlanner.shouldScheduleNotification(for: $0, now: now) }.count
            let retainedCount = TodoNotificationPlanner.retainedNotificationTodos(from: todos, now: now).count
            let snapshots = todos.map { TodoNotificationSnapshot(todo: $0) }
            try await TodoNotificationSchedulingBridge.reconcile(
                snapshots: snapshots,
                using: todoNotificationScheduler
            )
            if eligibleCount > retainedCount {
                todoNotificationMessage = "已同步最近 \(retainedCount) 个待办提醒（共 \(eligibleCount) 个符合条件）"
            } else {
                todoNotificationMessage = "已同步 \(retainedCount) 个待办提醒"
            }
            todoNotificationErrorMessage = nil
            return true
        } catch is CancellationError {
            return false
        } catch {
            todoNotificationErrorMessage = "同步待办提醒失败: \(error.localizedDescription)"
            return false
        }
    }

    private func refreshReminderAuthorizationStatuses() {
        reminderStatusTask?.cancel()
        reminderStatusTask = Task { @MainActor in
            let previousTodoStatus = todoNotificationAuthorizationStatus
            let previousSystemStatus = systemReminderAuthorizationStatus
            let todoStatus = await todoNotificationScheduler.refreshAuthorizationStatus()
            let systemStatus = await systemReminderWriter.refreshAuthorizationStatus()
            guard !Task.isCancelled else { return }
            todoNotificationAuthorizationStatus = todoStatus
            systemReminderAuthorizationStatus = systemStatus

            if selectedTodoReminderMode == .localNotification,
               todoNotificationsEnabled,
               !previousTodoStatus.allowsScheduling,
               todoStatus.allowsScheduling {
                startReminderWriteOperation {
                    _ = await reconcileTodoNotificationsNow()
                }
            }

            if ReminderAuthorizationTransitionPlanner.shouldSyncSystemReminders(
                mode: selectedTodoReminderMode,
                previousStatus: previousSystemStatus,
                currentStatus: systemStatus
            ) {
                startReminderWriteOperation {
                    await syncCurrentTodosToSystemRemindersNow()
                }
            }
        }
    }

    private func startReminderWriteOperation(
        _ operation: @escaping @MainActor () async -> Void
    ) {
        reminderWriteTask?.cancel()
        reminderWriteTask = Task { @MainActor in
            await operation()
        }
    }

    private var todoNotificationStatusText: String {
        switch todoNotificationAuthorizationStatus {
        case .notDetermined:
            return "未请求"
        case .denied:
            return "已拒绝"
        case .authorized:
            return "已允许"
        case .provisional:
            return "临时允许"
        case .ephemeral:
            return "本次允许"
        case .unknown:
            return "未知"
        }
    }

    private var todoNotificationStatusIcon: String {
        switch todoNotificationAuthorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return "bell.badge.fill"
        case .denied:
            return "bell.slash.fill"
        case .notDetermined, .unknown:
            return "bell"
        }
    }

    private var todoNotificationStatusColor: Color {
        switch todoNotificationAuthorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return .green
        case .denied:
            return .red
        case .notDetermined, .unknown:
            return .secondary
        }
    }

    private var systemReminderStatusText: String {
        switch systemReminderAuthorizationStatus {
        case .notDetermined:
            return "未请求"
        case .restricted:
            return "受限制"
        case .denied:
            return "已拒绝"
        case .fullAccess:
            return "已允许"
        case .unknown:
            return "未知"
        }
    }

    private var systemReminderStatusIcon: String {
        switch systemReminderAuthorizationStatus {
        case .fullAccess:
            return "checklist.checked"
        case .denied, .restricted:
            return "exclamationmark.triangle.fill"
        case .notDetermined, .unknown:
            return "checklist"
        }
    }

    private var systemReminderStatusColor: Color {
        switch systemReminderAuthorizationStatus {
        case .fullAccess:
            return .green
        case .denied, .restricted:
            return .red
        case .notDetermined, .unknown:
            return .secondary
        }
    }
}
