import SwiftUI
import SwiftData
import UniformTypeIdentifiers

extension UTType {
    static var easyNoteBackup: UTType {
        UTType(filenameExtension: BackupService.fileExtension) ?? .json
    }
}

struct EasyNoteBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.easyNoteBackup, .json] }

    var data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject var themeManager: ThemeManager
    @AppStorage("openai_api_key") private var apiKey = ""
    @State private var backupDocument = EasyNoteBackupDocument()
    @State private var isExportingBackup = false
    @State private var isImportingBackup = false
    @State private var pendingImportBackup: EasyNoteBackupV1?
    @State private var pendingImportSummary: BackupSummary?
    @State private var showImportConfirmation = false
    @State private var backupMessage: String?
    @State private var backupErrorMessage: String?

    private let backupService: any BackupServiceProviding
    private let cloudKitPreflightReport: CloudKitPreflightReport

    init(
        themeManager: ThemeManager,
        backupService: any BackupServiceProviding = BackupService(),
        cloudKitPreflightReport: CloudKitPreflightReport = CloudKitSyncPreflight.currentProjectReport()
    ) {
        self._themeManager = ObservedObject(wrappedValue: themeManager)
        self.backupService = backupService
        self.cloudKitPreflightReport = cloudKitPreflightReport
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("外观")) {
                    Toggle("深色模式", isOn: Binding(
                        get: { themeManager.colorScheme == .dark },
                        set: { _ in themeManager.toggleDarkMode() }
                    ))
                    
                    Picker("主题颜色", selection: Binding(
                        get: { themeManager.accentColorName },
                        set: { themeManager.setAccentColor($0) }
                    )) {
                        Text("蓝色").tag("blue")
                        Text("绿色").tag("green")
                        Text("紫色").tag("purple")
                        Text("红色").tag("red")
                        Text("橙色").tag("orange")
                    }
                    .pickerStyle(MenuPickerStyle())
                }
                
                Section {
                    SecureField("DeepSeek API密钥", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("settings.apiKeyField")

                    if apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("未配置 API 密钥")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("API 密钥已配置")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if !apiKey.isEmpty {
                        Button("清除API密钥", role: .destructive) {
                            apiKey = ""
                        }
                        .accessibilityIdentifier("settings.clearApiKeyButton")
                    }
                } header: {
                    Text("AI")
                } footer: {
                    Text("API密钥仅保存在本机UserDefaults中，仓库不包含默认密钥。")
                }

                Section {
                    Button {
                        prepareBackupExport()
                    } label: {
                        Label("导出备份", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("settings.exportBackupButton")

                    Button {
                        isImportingBackup = true
                    } label: {
                        Label("导入备份", systemImage: "square.and.arrow.down")
                    }
                    .accessibilityIdentifier("settings.importBackupButton")

                    if let backupMessage {
                        Text(backupMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if let backupErrorMessage {
                        Text(backupErrorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                } header: {
                    Text("数据备份")
                } footer: {
                    Text("备份包含日记、待办、聊天会话和本地录音文件。导入会覆盖相同ID的数据，但不会删除备份中不存在的本地数据。")
                }

                Section {
                    HStack {
                        Label("同步状态", systemImage: cloudKitPreflightStatusIcon)
                            .foregroundColor(cloudKitPreflightStatusColor)

                        Spacer()

                        Text(cloudKitPreflightStatusText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Text(cloudKitPreflightReport.summary)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("容器：\(cloudKitPreflightReport.containerIdentifier)")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    ForEach(cloudKitPreflightReport.checks) { check in
                        VStack(alignment: .leading, spacing: 4) {
                            Label(check.title, systemImage: iconName(for: check.severity))
                                .foregroundColor(color(for: check.severity))

                            Text(check.detail)
                                .font(.caption)
                                .foregroundColor(.secondary)

                            if check.severity != .passed {
                                Text(check.remediation)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text("iCloud 同步预检")
                } footer: {
                    Text("当前仅展示真实同步启用前置条件，不会开启 CloudKit 或改变本地 SwiftData 存储。")
                }
                
                Section(header: Text("关于")) {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.gray)
                    }
                }
                
                Section {
                    Color.clear
                        .frame(height: 60)
                        .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("设置")
            .fileExporter(
                isPresented: $isExportingBackup,
                document: backupDocument,
                contentType: .easyNoteBackup,
                defaultFilename: defaultBackupFilename
            ) { result in
                switch result {
                case .success:
                    backupMessage = "备份已导出"
                    backupErrorMessage = nil
                case .failure(let error):
                    backupErrorMessage = "导出失败: \(error.localizedDescription)"
                }
            }
            .fileImporter(
                isPresented: $isImportingBackup,
                allowedContentTypes: EasyNoteBackupDocument.readableContentTypes,
                allowsMultipleSelection: false
            ) { result in
                handleBackupImportSelection(result)
            }
            .confirmationDialog(
                "导入备份",
                isPresented: $showImportConfirmation,
                presenting: pendingImportSummary
            ) { _ in
                Button("确认导入") {
                    importPendingBackup()
                }
                Button("取消", role: .cancel) {
                    pendingImportBackup = nil
                    pendingImportSummary = nil
                }
            } message: { summary in
                Text(importPreviewText(summary))
            }
        }
    }

    private var defaultBackupFilename: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "EasyNoteBackup-\(formatter.string(from: Date()))"
    }

    private func prepareBackupExport() {
        do {
            let backup = try backupService.exportBackup(from: modelContext)
            backupDocument = EasyNoteBackupDocument(data: try backupService.encodeBackup(backup))
            isExportingBackup = true
            backupMessage = "已准备导出：\(importPreviewText(backupService.summary(for: backup)))"
            backupErrorMessage = nil
        } catch {
            backupErrorMessage = "导出失败: \(error.localizedDescription)"
        }
    }

    private func handleBackupImportSelection(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else {
                backupErrorMessage = "未选择备份文件"
                return
            }

            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let data = try Data(contentsOf: url)
            let backup = try backupService.decodeAndValidateBackup(from: data)
            pendingImportBackup = backup
            pendingImportSummary = backupService.summary(for: backup)
            backupErrorMessage = nil
            showImportConfirmation = true
        } catch {
            pendingImportBackup = nil
            pendingImportSummary = nil
            backupErrorMessage = "读取备份失败: \(error.localizedDescription)"
        }
    }

    private func importPendingBackup() {
        guard let pendingImportBackup else {
            backupErrorMessage = "没有可导入的备份"
            return
        }

        do {
            let result = try backupService.importBackup(pendingImportBackup, into: modelContext)
            backupMessage = "导入完成：\(importPreviewText(result.summary))"
            backupErrorMessage = nil
            self.pendingImportBackup = nil
            pendingImportSummary = nil
            NotificationCenter.default.post(name: .easyNoteBackupDidImport, object: nil)
        } catch {
            backupErrorMessage = "导入失败: \(error.localizedDescription)"
        }
    }

    private func importPreviewText(_ summary: BackupSummary) -> String {
        "日记 \(summary.diaryCount) 篇，待办 \(summary.todoCount) 个，会话 \(summary.chatSessionCount) 个，消息 \(summary.messageCount) 条，录音 \(summary.audioAssetCount) 个"
    }

    private var cloudKitPreflightStatusText: String {
        switch cloudKitPreflightReport.overallSeverity {
        case .passed:
            return "通过"
        case .warning:
            return "需注意"
        case .blocked:
            return "未就绪"
        }
    }

    private var cloudKitPreflightStatusIcon: String {
        iconName(for: cloudKitPreflightReport.overallSeverity)
    }

    private var cloudKitPreflightStatusColor: Color {
        color(for: cloudKitPreflightReport.overallSeverity)
    }

    private func iconName(for severity: CloudKitPreflightSeverity) -> String {
        switch severity {
        case .passed:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .blocked:
            return "xmark.octagon.fill"
        }
    }

    private func color(for severity: CloudKitPreflightSeverity) -> Color {
        switch severity {
        case .passed:
            return .green
        case .warning:
            return .orange
        case .blocked:
            return .red
        }
    }
}

#Preview {
    SettingsView(themeManager: ThemeManager())
        .modelContainer(for: [DiaryEntry.self, TodoItem.self, ChatSession.self, SessionMessage.self], inMemory: true)
}
