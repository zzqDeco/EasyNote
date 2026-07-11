struct SettingsDependencies {
    let backupService: any BackupServiceProviding
    let todoNotificationScheduler: any TodoNotificationSchedulingProviding
    let systemReminderAgent: any SystemReminderAgentProviding
    let systemReminderWriter: any SystemReminderWritingProviding
    let reminderModeStore: any TodoReminderModeProviding
    let cloudKitPreflightReport: CloudKitPreflightReport

    init(
        backupService: any BackupServiceProviding = BackupService(),
        todoNotificationScheduler: any TodoNotificationSchedulingProviding = LocalTodoNotificationService.shared,
        systemReminderAgent: any SystemReminderAgentProviding = SystemReminderAgent(),
        systemReminderWriter: any SystemReminderWritingProviding = SystemReminderService.shared,
        reminderModeStore: any TodoReminderModeProviding = TodoReminderModeStore(),
        cloudKitPreflightReport: CloudKitPreflightReport = CloudKitSyncPreflight.currentProjectReport()
    ) {
        self.backupService = backupService
        self.todoNotificationScheduler = todoNotificationScheduler
        self.systemReminderAgent = systemReminderAgent
        self.systemReminderWriter = systemReminderWriter
        self.reminderModeStore = reminderModeStore
        self.cloudKitPreflightReport = cloudKitPreflightReport
    }
}
