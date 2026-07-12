struct SettingsDependencies {
    let aiCredentialStore: any CredentialStoreProviding
    let aiContentConsentStore: any AIContentConsentProviding
    let backupService: any BackupServiceProviding
    let todoNotificationScheduler: any TodoNotificationSchedulingProviding
    let systemReminderAgent: any SystemReminderAgentProviding
    let systemReminderWriter: any SystemReminderWritingProviding
    let reminderModeStore: any TodoReminderModeProviding
    let cloudKitPreflightReport: CloudKitPreflightReport

    init(
        aiCredentialStore: any CredentialStoreProviding = KeychainCredentialStore(),
        aiContentConsentStore: any AIContentConsentProviding = AIContentConsentStore(),
        backupService: any BackupServiceProviding = BackupService(),
        todoNotificationScheduler: any TodoNotificationSchedulingProviding = LocalTodoNotificationService.shared,
        systemReminderAgent: any SystemReminderAgentProviding = SystemReminderAgent(),
        systemReminderWriter: any SystemReminderWritingProviding = SystemReminderService.shared,
        reminderModeStore: any TodoReminderModeProviding = TodoReminderModeStore(),
        cloudKitPreflightReport: CloudKitPreflightReport = CloudKitSyncPreflight.currentProjectReport()
    ) {
        self.aiCredentialStore = aiCredentialStore
        self.aiContentConsentStore = aiContentConsentStore
        self.backupService = backupService
        self.todoNotificationScheduler = todoNotificationScheduler
        self.systemReminderAgent = systemReminderAgent
        self.systemReminderWriter = systemReminderWriter
        self.reminderModeStore = reminderModeStore
        self.cloudKitPreflightReport = cloudKitPreflightReport
    }
}
