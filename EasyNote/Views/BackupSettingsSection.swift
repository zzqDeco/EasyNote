import SwiftData
import SwiftUI
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

struct BackupSettingsSection: View {
    let modelContext: ModelContext
    let backupService: any BackupServiceProviding

    @State private var backupDocument = EasyNoteBackupDocument()
    @State private var isExportingBackup = false
    @State private var isImportingBackup = false
    @State private var pendingImportBackup: EasyNoteBackupV1?
    @State private var pendingImportSummary: BackupSummary?
    @State private var showImportConfirmation = false
    @State private var backupMessage: String?
    @State private var backupErrorMessage: String?

    var body: some View {
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
}
