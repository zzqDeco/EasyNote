import Foundation
import SwiftData

extension Notification.Name {
    static let easyNoteBackupDidImport = Notification.Name("EasyNoteBackupDidImport")
}

struct EasyNoteBackupV1: Codable, Equatable {
    var version: Int
    var exportedAt: Date
    var diaryEntries: [BackupDiaryEntry]
    var todoItems: [BackupTodoItem]
    var chatSessions: [BackupChatSession]
    var sessionMessages: [BackupSessionMessage]
    var audioAssets: [BackupAudioAsset]
}

struct BackupDiaryEntry: Codable, Equatable, Identifiable {
    var id: UUID
    var title: String
    var content: String
    var mood: String?
    var tags: [String]
    var creationDate: Date
    var lastModified: Date
    var isFavorite: Bool
    var aiSummary: String?
    var audioAssetId: UUID?
}

struct BackupTodoItem: Codable, Equatable, Identifiable {
    var id: UUID
    var title: String
    var isCompleted: Bool
    var priority: TodoItem.PriorityLevel
    var deadline: Date?
    var notes: String?
    var isRecurring: Bool
    var recurringInterval: String?
    var creationDate: Date
}

struct BackupChatSession: Codable, Equatable, Identifiable {
    var id: UUID
    var title: String
    var creationDate: Date
    var lastModifiedDate: Date
    var messageIds: [UUID]
}

struct BackupSessionMessage: Codable, Equatable, Identifiable {
    var id: UUID
    var content: String
    var isUser: Bool
    var timestamp: Date
    var relatedEntryIds: [String]
}

struct BackupAudioAsset: Codable, Equatable, Identifiable {
    var id: UUID
    var originalFilename: String
    var pathExtension: String
    var byteCount: Int
    var data: Data
}

struct BackupSummary: Equatable {
    var diaryCount: Int
    var todoCount: Int
    var chatSessionCount: Int
    var messageCount: Int
    var audioAssetCount: Int
}

struct BackupLimits: Equatable, Sendable {
    var maxFileBytes: Int
    var maxSingleAudioBytes: Int
    var maxTotalAudioBytes: Int
    var maxDiaryEntries: Int
    var maxTodoItems: Int
    var maxChatSessions: Int
    var maxSessionMessages: Int
    var maxAudioAssets: Int

    static let `default` = BackupLimits()

    init(
        maxFileBytes: Int = 64 * 1_024 * 1_024,
        maxSingleAudioBytes: Int = 16 * 1_024 * 1_024,
        maxTotalAudioBytes: Int = 47 * 1_024 * 1_024,
        maxDiaryEntries: Int = 10_000,
        maxTodoItems: Int = 50_000,
        maxChatSessions: Int = 5_000,
        maxSessionMessages: Int = 100_000,
        maxAudioAssets: Int = 500
    ) {
        self.maxFileBytes = maxFileBytes
        self.maxSingleAudioBytes = maxSingleAudioBytes
        self.maxTotalAudioBytes = maxTotalAudioBytes
        self.maxDiaryEntries = maxDiaryEntries
        self.maxTodoItems = maxTodoItems
        self.maxChatSessions = maxChatSessions
        self.maxSessionMessages = maxSessionMessages
        self.maxAudioAssets = maxAudioAssets
    }
}

enum BackupResourceLimit: String, Equatable, Sendable {
    case fileBytes
    case singleAudioBytes
    case totalAudioBytes
    case diaryEntries
    case todoItems
    case chatSessions
    case sessionMessages
    case audioAssets
}

enum BackupFileOperation: Equatable {
    case stageWrite(UUID)
    case preserveExisting(URL)
    case installStaged(URL)
    case cleanupManaged(URL)
}

enum BackupServiceError: LocalizedError, Equatable {
    case unsupportedVersion(Int)
    case invalidBackup(String)
    case resourceLimitExceeded(BackupResourceLimit, maximum: Int, actual: Int)
    case fileOperationFailed(String)
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            return "不支持的备份版本: \(version)"
        case .invalidBackup(let message):
            return "备份文件无效: \(message)"
        case .resourceLimitExceeded(let limit, let maximum, let actual):
            return "备份超出资源限制（\(limit.rawValue)）：最大 \(maximum)，实际 \(actual)"
        case .fileOperationFailed(let message):
            return "备份文件操作失败: \(message)"
        case .saveFailed(let message):
            return "保存备份数据失败: \(message)"
        }
    }
}

struct BackupImportResult: Equatable {
    var summary: BackupSummary
}

struct BackupService {
    static let supportedVersion = 1
    static let fileExtension = "easynotebackup"

    private static let supportedAudioExtensions = Set(["caf", "m4a"])

    private let fileManager: FileManager
    private let documentsDirectory: URL
    private let limits: BackupLimits
    private let saveModelContext: @MainActor (ModelContext) throws -> Void
    private let backgroundWorkObserver: (() -> Void)?
    private let fileOperationHook: ((BackupFileOperation) throws -> Void)?

    init(
        fileManager: FileManager = .default,
        documentsDirectory: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0],
        limits: BackupLimits = .default,
        saveModelContext: @escaping @MainActor (ModelContext) throws -> Void = { try $0.save() },
        backgroundWorkObserver: (() -> Void)? = nil,
        fileOperationHook: ((BackupFileOperation) throws -> Void)? = nil
    ) {
        self.fileManager = fileManager
        self.documentsDirectory = documentsDirectory
        self.limits = limits
        self.saveModelContext = saveModelContext
        self.backgroundWorkObserver = backgroundWorkObserver
        self.fileOperationHook = fileOperationHook
    }

    @MainActor
    func exportBackup(from modelContext: ModelContext, exportedAt: Date = Date()) async throws -> EasyNoteBackupV1 {
        let snapshot = try snapshot(from: modelContext, exportedAt: exportedAt)
        return try await performBackground {
            try buildBackup(from: snapshot)
        }
    }

    func encodeBackup(_ backup: EasyNoteBackupV1) async throws -> Data {
        try await performBackground {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .custom { date, encoder in
                try Self.encodeBackupDate(date, encoder: encoder)
            }
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(backup)
            try validateRawFileSize(data.count)
            return data
        }
    }

    func decodeAndValidateBackup(from data: Data) async throws -> EasyNoteBackupV1 {
        try validateRawFileSize(data.count)
        return try await performBackground {
            try decodeAndValidateBackupSynchronously(from: data)
        }
    }

    func readAndDecodeBackup(from url: URL) async throws -> EasyNoteBackupV1 {
        try await performBackground {
            let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey])
            if let fileSize = resourceValues.fileSize {
                try validateRawFileSize(fileSize)
            }
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            try validateRawFileSize(data.count)
            return try decodeAndValidateBackupSynchronously(from: data)
        }
    }

    func summary(for backup: EasyNoteBackupV1) -> BackupSummary {
        BackupSummary(
            diaryCount: backup.diaryEntries.count,
            todoCount: backup.todoItems.count,
            chatSessionCount: backup.chatSessions.count,
            messageCount: backup.sessionMessages.count,
            audioAssetCount: backup.audioAssets.count
        )
    }

    @MainActor
    @discardableResult
    func importBackupData(_ data: Data, into modelContext: ModelContext) async throws -> BackupImportResult {
        let backup = try await decodeAndValidateBackup(from: data)
        return try await importBackup(backup, into: modelContext)
    }

    @MainActor
    @discardableResult
    func importBackup(_ backup: EasyNoteBackupV1, into modelContext: ModelContext) async throws -> BackupImportResult {
        let normalizedBackup = try await performBackground {
            let normalized = Self.normalizedLegacySharedMessages(in: backup)
            try validate(normalized)
            return normalized
        }

        let importedDiaryIDs = Set(normalizedBackup.diaryEntries.map(\.id))
        let protectedAudioPaths = try referencedAudioPaths(
            in: modelContext,
            excludingDiaryIDs: importedDiaryIDs
        )
        let preparedAudio = try await performBackground {
            try prepareAudioImport(
                for: normalizedBackup.audioAssets,
                protectedAudioPaths: protectedAudioPaths
            )
        }

        do {
            try apply(
                normalizedBackup,
                restoredAudioByAssetID: preparedAudio.restoredAudioByAssetID,
                to: modelContext
            )
            try saveModelContext(modelContext)
        } catch {
            modelContext.rollback()
            do {
                try await performBackground {
                    try rollbackAudioImport(preparedAudio.transaction)
                }
            } catch let rollbackError {
                throw BackupServiceError.saveFailed(
                    "\(error.localizedDescription)；录音回滚失败: \(rollbackError.localizedDescription)"
                )
            }

            if let backupError = error as? BackupServiceError {
                throw backupError
            }
            throw BackupServiceError.saveFailed(error.localizedDescription)
        }

        let referencedAudioPaths = try? referencedAudioPaths(in: modelContext)
        try? await performBackground {
            try? finalizeAudioImport(preparedAudio.transaction)
            if let referencedAudioPaths {
                try? removeUnreferencedManagedRecordings(referencedPaths: referencedAudioPaths)
            }
        }

        return BackupImportResult(summary: summary(for: normalizedBackup))
    }

    func validate(_ backup: EasyNoteBackupV1) throws {
        guard backup.version == Self.supportedVersion else {
            throw BackupServiceError.unsupportedVersion(backup.version)
        }

        try validateCount(backup.diaryEntries.count, maximum: limits.maxDiaryEntries, limit: .diaryEntries)
        try validateCount(backup.todoItems.count, maximum: limits.maxTodoItems, limit: .todoItems)
        try validateCount(backup.chatSessions.count, maximum: limits.maxChatSessions, limit: .chatSessions)
        try validateCount(backup.sessionMessages.count, maximum: limits.maxSessionMessages, limit: .sessionMessages)
        try validateCount(backup.audioAssets.count, maximum: limits.maxAudioAssets, limit: .audioAssets)

        try ensureUnique(backup.diaryEntries.map(\.id), name: "日记 ID")
        try ensureUnique(backup.todoItems.map(\.id), name: "待办 ID")
        try ensureUnique(backup.chatSessions.map(\.id), name: "会话 ID")
        try ensureUnique(backup.sessionMessages.map(\.id), name: "消息 ID")
        try ensureUnique(backup.audioAssets.map(\.id), name: "录音资产 ID")

        let audioIDs = Set(backup.audioAssets.map(\.id))
        for diaryEntry in backup.diaryEntries {
            if let audioAssetId = diaryEntry.audioAssetId, !audioIDs.contains(audioAssetId) {
                throw BackupServiceError.invalidBackup("日记引用了不存在的录音资产")
            }
        }

        let messageIDs = Set(backup.sessionMessages.map(\.id))
        var referencedMessageIDs = Set<UUID>()
        for session in backup.chatSessions {
            try ensureUnique(session.messageIds, name: "会话消息 ID")

            for messageID in session.messageIds where !messageIDs.contains(messageID) {
                throw BackupServiceError.invalidBackup("会话引用了不存在的消息")
            }

            for messageID in session.messageIds where !referencedMessageIDs.insert(messageID).inserted {
                throw BackupServiceError.invalidBackup("消息不能同时属于多个会话")
            }
        }

        for message in backup.sessionMessages where message.content.isEmpty {
            throw BackupServiceError.invalidBackup("消息内容不能为空")
        }

        var totalAudioBytes = 0
        for asset in backup.audioAssets {
            let pathExtension = asset.pathExtension.lowercased()
            if !Self.supportedAudioExtensions.contains(pathExtension) {
                throw BackupServiceError.invalidBackup("不支持的录音格式: \(asset.pathExtension)")
            }

            if asset.byteCount != asset.data.count {
                throw BackupServiceError.invalidBackup("录音资产大小不匹配")
            }

            try validateCount(
                asset.data.count,
                maximum: limits.maxSingleAudioBytes,
                limit: .singleAudioBytes
            )
            totalAudioBytes = try addingWithoutOverflow(totalAudioBytes, asset.data.count)
        }
        try validateCount(totalAudioBytes, maximum: limits.maxTotalAudioBytes, limit: .totalAudioBytes)
    }

    @MainActor
    private func snapshot(from modelContext: ModelContext, exportedAt: Date) throws -> BackupSnapshot {
        var diaryDescriptor = FetchDescriptor<DiaryEntry>(
            sortBy: [SortDescriptor(\.creationDate, order: .forward)]
        )
        diaryDescriptor.fetchLimit = overflowProbeLimit(for: limits.maxDiaryEntries)
        let diaryEntries = try modelContext.fetch(diaryDescriptor)
        try validateCount(diaryEntries.count, maximum: limits.maxDiaryEntries, limit: .diaryEntries)

        var todoDescriptor = FetchDescriptor<TodoItem>(
            sortBy: [SortDescriptor(\.creationDate, order: .forward)]
        )
        todoDescriptor.fetchLimit = overflowProbeLimit(for: limits.maxTodoItems)
        let todoItems = try modelContext.fetch(todoDescriptor)
        try validateCount(todoItems.count, maximum: limits.maxTodoItems, limit: .todoItems)

        var chatDescriptor = FetchDescriptor<ChatSession>(
            sortBy: [SortDescriptor(\.creationDate, order: .forward)]
        )
        chatDescriptor.fetchLimit = overflowProbeLimit(for: limits.maxChatSessions)
        let chatSessions = try modelContext.fetch(chatDescriptor)
        try validateCount(chatSessions.count, maximum: limits.maxChatSessions, limit: .chatSessions)

        let chatExport = try exportChatData(from: chatSessions)
        let diarySnapshots = diaryEntries.map { entry in
            let audioSource: BackupAudioSource?
            if let audioURL = entry.audioURL,
               audioURL.isFileURL,
               Self.supportedAudioExtensions.contains(audioURL.pathExtension.lowercased()) {
                audioSource = BackupAudioSource(assetID: UUID(), url: audioURL)
            } else {
                audioSource = nil
            }

            return BackupDiarySnapshot(
                entry: BackupDiaryEntry(
                    id: entry.id,
                    title: entry.title,
                    content: entry.content,
                    mood: entry.mood,
                    tags: entry.tags,
                    creationDate: entry.creationDate,
                    lastModified: entry.lastModified,
                    isFavorite: entry.isFavorite,
                    aiSummary: entry.aiSummary,
                    audioAssetId: audioSource?.assetID
                ),
                audioSource: audioSource
            )
        }

        return BackupSnapshot(
            exportedAt: exportedAt,
            diarySnapshots: diarySnapshots,
            todoItems: todoItems.map { item in
                BackupTodoItem(
                    id: item.id,
                    title: item.title,
                    isCompleted: item.isCompleted,
                    priority: item.priority,
                    deadline: item.deadline,
                    notes: item.notes,
                    isRecurring: item.isRecurring,
                    recurringInterval: item.recurringInterval,
                    creationDate: item.creationDate
                )
            },
            chatSessions: chatExport.sessions,
            sessionMessages: chatExport.messages
        )
    }

    private func buildBackup(from snapshot: BackupSnapshot) throws -> EasyNoteBackupV1 {
        try validateCount(snapshot.diarySnapshots.count, maximum: limits.maxDiaryEntries, limit: .diaryEntries)
        try validateCount(snapshot.todoItems.count, maximum: limits.maxTodoItems, limit: .todoItems)
        try validateCount(snapshot.chatSessions.count, maximum: limits.maxChatSessions, limit: .chatSessions)
        try validateCount(snapshot.sessionMessages.count, maximum: limits.maxSessionMessages, limit: .sessionMessages)

        var audioAssets: [BackupAudioAsset] = []
        var exportedAudioIDs = Set<UUID>()
        var totalAudioBytes = 0

        for source in snapshot.diarySnapshots.compactMap(\.audioSource) {
            guard fileManager.fileExists(atPath: source.url.path),
                  let resourceValues = try? source.url.resourceValues(forKeys: [.fileSizeKey]) else {
                continue
            }

            let fileSize = resourceValues.fileSize ?? 0
            try validateCount(fileSize, maximum: limits.maxSingleAudioBytes, limit: .singleAudioBytes)
            let projectedTotal = try addingWithoutOverflow(totalAudioBytes, fileSize)
            try validateCount(projectedTotal, maximum: limits.maxTotalAudioBytes, limit: .totalAudioBytes)

            guard let data = try? Data(contentsOf: source.url, options: .mappedIfSafe) else {
                continue
            }
            try validateCount(data.count, maximum: limits.maxSingleAudioBytes, limit: .singleAudioBytes)
            totalAudioBytes = try addingWithoutOverflow(totalAudioBytes, data.count)
            try validateCount(totalAudioBytes, maximum: limits.maxTotalAudioBytes, limit: .totalAudioBytes)

            audioAssets.append(BackupAudioAsset(
                id: source.assetID,
                originalFilename: source.url.lastPathComponent,
                pathExtension: source.url.pathExtension.lowercased(),
                byteCount: data.count,
                data: data
            ))
            exportedAudioIDs.insert(source.assetID)
        }

        let backup = EasyNoteBackupV1(
            version: Self.supportedVersion,
            exportedAt: snapshot.exportedAt,
            diaryEntries: snapshot.diarySnapshots.map { snapshot in
                var entry = snapshot.entry
                if let audioAssetID = entry.audioAssetId, !exportedAudioIDs.contains(audioAssetID) {
                    entry.audioAssetId = nil
                }
                return entry
            },
            todoItems: snapshot.todoItems,
            chatSessions: snapshot.chatSessions,
            sessionMessages: snapshot.sessionMessages,
            audioAssets: audioAssets
        )
        try validate(backup)
        return backup
    }

    private func decodeAndValidateBackupSynchronously(from data: Data) throws -> EasyNoteBackupV1 {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            try Self.decodeBackupDate(decoder)
        }
        let decodedBackup = try decoder.decode(EasyNoteBackupV1.self, from: data)
        let backup = Self.normalizedLegacySharedMessages(in: decodedBackup)
        try validate(backup)
        return backup
    }

    @MainActor
    private func apply(
        _ backup: EasyNoteBackupV1,
        restoredAudioByAssetID: [UUID: URL],
        to modelContext: ModelContext
    ) throws {
        let existingDiaryEntries = try fetchByID(DiaryEntry.self, modelContext: modelContext)
        let existingTodoItems = try fetchByID(TodoItem.self, modelContext: modelContext)
        var messagesByID = try fetchByID(SessionMessage.self, modelContext: modelContext)
        let existingSessions = try fetchByID(ChatSession.self, modelContext: modelContext)

        for messageDTO in backup.sessionMessages {
            let message = messagesByID[messageDTO.id] ?? SessionMessage(
                id: messageDTO.id,
                content: messageDTO.content,
                isUser: messageDTO.isUser,
                timestamp: messageDTO.timestamp,
                relatedEntryIds: messageDTO.relatedEntryIds
            )

            message.content = messageDTO.content
            message.isUser = messageDTO.isUser
            message.timestamp = messageDTO.timestamp
            message.relatedEntryIds = messageDTO.relatedEntryIds

            if messagesByID[messageDTO.id] == nil {
                modelContext.insert(message)
                messagesByID[messageDTO.id] = message
            }
        }

        for entryDTO in backup.diaryEntries {
            let entry = existingDiaryEntries[entryDTO.id] ?? DiaryEntry(
                id: entryDTO.id,
                title: entryDTO.title,
                content: entryDTO.content,
                mood: entryDTO.mood,
                tags: entryDTO.tags,
                isFavorite: entryDTO.isFavorite
            )

            entry.title = entryDTO.title
            entry.content = entryDTO.content
            entry.mood = entryDTO.mood
            entry.tags = entryDTO.tags
            entry.creationDate = entryDTO.creationDate
            entry.lastModified = entryDTO.lastModified
            entry.isFavorite = entryDTO.isFavorite
            entry.aiSummary = entryDTO.aiSummary
            entry.audioURL = entryDTO.audioAssetId.flatMap { restoredAudioByAssetID[$0] }

            if existingDiaryEntries[entryDTO.id] == nil {
                modelContext.insert(entry)
            }
        }

        for todoDTO in backup.todoItems {
            let item = existingTodoItems[todoDTO.id] ?? TodoItem(
                id: todoDTO.id,
                title: todoDTO.title,
                isCompleted: todoDTO.isCompleted,
                priority: todoDTO.priority,
                deadline: todoDTO.deadline,
                notes: todoDTO.notes,
                isRecurring: todoDTO.isRecurring,
                recurringInterval: todoDTO.recurringInterval
            )

            item.title = todoDTO.title
            item.isCompleted = todoDTO.isCompleted
            item.priority = todoDTO.priority
            item.deadline = todoDTO.deadline
            item.notes = todoDTO.notes
            item.isRecurring = todoDTO.isRecurring
            item.recurringInterval = todoDTO.recurringInterval
            item.creationDate = todoDTO.creationDate

            if existingTodoItems[todoDTO.id] == nil {
                modelContext.insert(item)
            }
        }

        for sessionDTO in backup.chatSessions {
            let session = existingSessions[sessionDTO.id] ?? ChatSession(
                id: sessionDTO.id,
                title: sessionDTO.title
            )

            let existingSession = existingSessions[sessionDTO.id]
            let mergedMessages = mergedSessionMessages(
                importedMessageIDs: sessionDTO.messageIds,
                messagesByID: messagesByID,
                existingSession: existingSession
            )

            session.title = sessionDTO.title
            session.creationDate = sessionDTO.creationDate
            session.lastModifiedDate = mergedLastModifiedDate(
                importedLastModifiedDate: sessionDTO.lastModifiedDate,
                existingSession: existingSession,
                messages: mergedMessages
            )
            session.messages = mergedMessages

            if existingSessions[sessionDTO.id] == nil {
                modelContext.insert(session)
            }
        }
    }

    private func prepareAudioImport(
        for assets: [BackupAudioAsset],
        protectedAudioPaths: Set<String>
    ) throws -> PreparedAudioImport {
        guard !assets.isEmpty else {
            return PreparedAudioImport(transaction: nil, restoredAudioByAssetID: [:])
        }

        let root = documentsDirectory.appendingPathComponent(
            ".EasyNoteBackupImport-\(UUID().uuidString)",
            isDirectory: true
        )
        let stagingDirectory = root.appendingPathComponent("staging", isDirectory: true)
        let rollbackDirectory = root.appendingPathComponent("rollback", isDirectory: true)
        var transaction = AudioFileTransaction(
            rootDirectory: root,
            touchedTargets: [],
            rollbackCopies: [:]
        )
        var restoredAudioByAssetID: [UUID: URL] = [:]

        do {
            try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: rollbackDirectory, withIntermediateDirectories: true)

            for asset in assets.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
                let targetURL = restoredAudioURL(for: asset, protectedAudioPaths: protectedAudioPaths)
                let filename = targetURL.lastPathComponent
                let stagedURL = stagingDirectory.appendingPathComponent(filename)
                let rollbackURL = rollbackDirectory.appendingPathComponent(filename)

                try fileOperationHook?(.stageWrite(asset.id))
                try asset.data.write(to: stagedURL, options: .atomic)

                if fileManager.fileExists(atPath: targetURL.path) {
                    try fileOperationHook?(.preserveExisting(targetURL))
                    try fileManager.copyItem(at: targetURL, to: rollbackURL)
                    transaction.rollbackCopies[targetURL] = rollbackURL
                }

                transaction.touchedTargets.append(targetURL)
                try fileOperationHook?(.installStaged(targetURL))
                if fileManager.fileExists(atPath: targetURL.path) {
                    try fileManager.removeItem(at: targetURL)
                }
                try fileManager.moveItem(at: stagedURL, to: targetURL)
                restoredAudioByAssetID[asset.id] = targetURL
            }

            return PreparedAudioImport(
                transaction: transaction,
                restoredAudioByAssetID: restoredAudioByAssetID
            )
        } catch {
            do {
                try rollbackAudioImport(transaction)
            } catch let rollbackError {
                throw BackupServiceError.fileOperationFailed(
                    "\(error.localizedDescription)；录音回滚失败: \(rollbackError.localizedDescription)"
                )
            }
            throw BackupServiceError.fileOperationFailed(error.localizedDescription)
        }
    }

    private func rollbackAudioImport(_ transaction: AudioFileTransaction?) throws {
        guard let transaction else { return }

        for targetURL in transaction.touchedTargets.reversed() {
            if let rollbackURL = transaction.rollbackCopies[targetURL],
               fileManager.fileExists(atPath: rollbackURL.path) {
                if fileManager.fileExists(atPath: targetURL.path) {
                    _ = try fileManager.replaceItemAt(targetURL, withItemAt: rollbackURL)
                } else {
                    try fileManager.moveItem(at: rollbackURL, to: targetURL)
                }
            } else if fileManager.fileExists(atPath: targetURL.path) {
                try fileManager.removeItem(at: targetURL)
            }
        }

        if fileManager.fileExists(atPath: transaction.rootDirectory.path) {
            try fileManager.removeItem(at: transaction.rootDirectory)
        }
    }

    private func finalizeAudioImport(_ transaction: AudioFileTransaction?) throws {
        guard let transaction,
              fileManager.fileExists(atPath: transaction.rootDirectory.path) else { return }
        try fileManager.removeItem(at: transaction.rootDirectory)
    }

    private func removeUnreferencedManagedRecordings(referencedPaths: Set<String>) throws {
        guard fileManager.fileExists(atPath: documentsDirectory.path) else { return }

        let children = try fileManager.contentsOfDirectory(
            at: documentsDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        for url in children where isManagedRecording(url) {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                continue
            }
            let path = url.standardizedFileURL.path
            guard !referencedPaths.contains(path) else { continue }
            try fileOperationHook?(.cleanupManaged(url))
            try fileManager.removeItem(at: url)
        }
    }

    private func isManagedRecording(_ url: URL) -> Bool {
        let filename = url.lastPathComponent
        let supportedExtension = Self.supportedAudioExtensions.contains(url.pathExtension.lowercased())
        return supportedExtension
            && (filename.hasPrefix("recording_") || filename.hasPrefix("restored_recording_"))
    }

    @MainActor
    private func referencedAudioPaths(
        in modelContext: ModelContext,
        excludingDiaryIDs excludedDiaryIDs: Set<UUID> = []
    ) throws -> Set<String> {
        let entries = try modelContext.fetch(FetchDescriptor<DiaryEntry>())
        return Set(entries.compactMap { entry in
            guard !excludedDiaryIDs.contains(entry.id) else { return nil }
            return entry.audioURL?.standardizedFileURL.path
        })
    }

    private func restoredAudioURL(
        for asset: BackupAudioAsset,
        protectedAudioPaths: Set<String>
    ) -> URL {
        let stem = "restored_recording_\(asset.id.uuidString)"
        let pathExtension = asset.pathExtension.lowercased()
        var collisionIndex = 0

        while true {
            let suffix: String
            switch collisionIndex {
            case 0:
                suffix = ""
            case 1:
                suffix = "_imported"
            default:
                suffix = "_imported_\(collisionIndex)"
            }
            let candidate = documentsDirectory
                .appendingPathComponent("\(stem)\(suffix).\(pathExtension)")
            if !protectedAudioPaths.contains(candidate.standardizedFileURL.path) {
                return candidate
            }
            collisionIndex += 1
        }
    }

    private func validateRawFileSize(_ byteCount: Int) throws {
        try validateCount(byteCount, maximum: limits.maxFileBytes, limit: .fileBytes)
    }

    private func validateCount(_ actual: Int, maximum: Int, limit: BackupResourceLimit) throws {
        guard actual <= maximum else {
            throw BackupServiceError.resourceLimitExceeded(limit, maximum: maximum, actual: actual)
        }
    }

    private func overflowProbeLimit(for maximum: Int) -> Int {
        maximum == .max ? .max : maximum + 1
    }

    private func addingWithoutOverflow(_ lhs: Int, _ rhs: Int) throws -> Int {
        let (value, overflow) = lhs.addingReportingOverflow(rhs)
        guard !overflow else {
            throw BackupServiceError.resourceLimitExceeded(.totalAudioBytes, maximum: limits.maxTotalAudioBytes, actual: .max)
        }
        return value
    }

    private func performBackground<T>(_ operation: @escaping () throws -> T) async throws -> T {
        let observer = backgroundWorkObserver
        return try await Task.detached(priority: .userInitiated) {
            observer?()
            return try operation()
        }.value
    }

    private struct BackupAudioSource {
        var assetID: UUID
        var url: URL
    }

    private struct BackupDiarySnapshot {
        var entry: BackupDiaryEntry
        var audioSource: BackupAudioSource?
    }

    private struct BackupSnapshot {
        var exportedAt: Date
        var diarySnapshots: [BackupDiarySnapshot]
        var todoItems: [BackupTodoItem]
        var chatSessions: [BackupChatSession]
        var sessionMessages: [BackupSessionMessage]
    }

    private struct AudioFileTransaction {
        var rootDirectory: URL
        var touchedTargets: [URL]
        var rollbackCopies: [URL: URL]
    }

    private struct PreparedAudioImport {
        var transaction: AudioFileTransaction?
        var restoredAudioByAssetID: [UUID: URL]
    }

    private func exportChatData(
        from sessions: [ChatSession]
    ) throws -> (sessions: [BackupChatSession], messages: [BackupSessionMessage]) {
        var reachableMessageCount = 0
        for session in sessions {
            let (projectedCount, overflow) = reachableMessageCount.addingReportingOverflow(session.messages.count)
            guard !overflow else {
                throw BackupServiceError.resourceLimitExceeded(
                    .sessionMessages,
                    maximum: limits.maxSessionMessages,
                    actual: .max
                )
            }
            reachableMessageCount = min(projectedCount, overflowProbeLimit(for: limits.maxSessionMessages))
            try validateCount(
                reachableMessageCount,
                maximum: limits.maxSessionMessages,
                limit: .sessionMessages
            )
        }

        let normalizedMessageIDs = Self.normalizedMessageIDs(
            for: sessions.map { $0.messages.map(\.id) }
        )
        var exportedMessages: [BackupSessionMessage] = []

        let exportedSessions = zip(sessions, normalizedMessageIDs).map { session, messageIDs in
            exportedMessages.append(contentsOf: zip(session.messages, messageIDs).map { message, messageID in
                BackupSessionMessage(
                    id: messageID,
                    content: message.content,
                    isUser: message.isUser,
                    timestamp: message.timestamp,
                    relatedEntryIds: message.relatedEntryIds
                )
            })
            return BackupChatSession(
                id: session.id,
                title: session.title,
                creationDate: session.creationDate,
                lastModifiedDate: session.lastModifiedDate,
                messageIds: messageIDs
            )
        }

        exportedMessages.sort { lhs, rhs in
            if lhs.timestamp == rhs.timestamp {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.timestamp < rhs.timestamp
        }
        return (exportedSessions, exportedMessages)
    }

    static func normalizedMessageIDs(
        for sessionMessageIDs: [[UUID]],
        makeDuplicateID: () -> UUID = UUID.init
    ) -> [[UUID]] {
        var messageIDsClaimedByPriorSessions = Set<UUID>()
        var allocatedMessageIDs = Set(sessionMessageIDs.joined())

        return sessionMessageIDs.map { messageIDs in
            let normalizedIDs = messageIDs.map { messageID in
                guard messageIDsClaimedByPriorSessions.contains(messageID) else {
                    return messageID
                }

                var duplicateID = makeDuplicateID()
                while !allocatedMessageIDs.insert(duplicateID).inserted {
                    duplicateID = makeDuplicateID()
                }
                return duplicateID
            }
            messageIDsClaimedByPriorSessions.formUnion(messageIDs)
            return normalizedIDs
        }
    }

    static func normalizedLegacySharedMessages(
        in backup: EasyNoteBackupV1,
        makeDuplicateID: () -> UUID = UUID.init
    ) -> EasyNoteBackupV1 {
        let normalizedMessageIDs = normalizedMessageIDs(
            for: backup.chatSessions.map(\.messageIds),
            makeDuplicateID: makeDuplicateID
        )
        var messagesByID: [UUID: BackupSessionMessage] = [:]
        for message in backup.sessionMessages where messagesByID[message.id] == nil {
            messagesByID[message.id] = message
        }
        var messages = backup.sessionMessages

        let sessions = zip(backup.chatSessions, normalizedMessageIDs).map { session, messageIDs in
            for (originalID, normalizedID) in zip(session.messageIds, messageIDs)
                where originalID != normalizedID {
                guard let original = messagesByID[originalID] else { continue }
                messages.append(BackupSessionMessage(
                    id: normalizedID,
                    content: original.content,
                    isUser: original.isUser,
                    timestamp: original.timestamp,
                    relatedEntryIds: original.relatedEntryIds
                ))
            }

            return BackupChatSession(
                id: session.id,
                title: session.title,
                creationDate: session.creationDate,
                lastModifiedDate: session.lastModifiedDate,
                messageIds: messageIDs
            )
        }

        return EasyNoteBackupV1(
            version: backup.version,
            exportedAt: backup.exportedAt,
            diaryEntries: backup.diaryEntries,
            todoItems: backup.todoItems,
            chatSessions: sessions,
            sessionMessages: messages,
            audioAssets: backup.audioAssets
        )
    }

    private func mergedSessionMessages(
        importedMessageIDs: [UUID],
        messagesByID: [UUID: SessionMessage],
        existingSession: ChatSession?
    ) -> [SessionMessage] {
        let importedIDSet = Set(importedMessageIDs)
        let importedMessages = importedMessageIDs.compactMap { messagesByID[$0] }
        let localMessages = existingSession?.messages.filter { !importedIDSet.contains($0.id) } ?? []

        return (importedMessages + localMessages).sorted { lhs, rhs in
            if lhs.timestamp == rhs.timestamp {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.timestamp < rhs.timestamp
        }
    }

    private func mergedLastModifiedDate(
        importedLastModifiedDate: Date,
        existingSession: ChatSession?,
        messages: [SessionMessage]
    ) -> Date {
        var dates = [importedLastModifiedDate]
        if let existingSession {
            dates.append(existingSession.lastModifiedDate)
        }
        dates.append(contentsOf: messages.map(\.timestamp))
        return dates.max() ?? importedLastModifiedDate
    }

    private func fetchByID<T: PersistentModel & Identifiable>(
        _ type: T.Type,
        modelContext: ModelContext
    ) throws -> [UUID: T] where T.ID == UUID {
        let values = try modelContext.fetch(FetchDescriptor<T>())
        return Dictionary(uniqueKeysWithValues: values.map { ($0.id, $0) })
    }

    private func ensureUnique<T: Hashable>(_ values: [T], name: String) throws {
        if Set(values).count != values.count {
            throw BackupServiceError.invalidBackup("\(name) 重复")
        }
    }

    private static func encodeBackupDate(_ date: Date, encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(fractionalDateFormatter().string(from: date))
    }

    private static func decodeBackupDate(_ decoder: Decoder) throws -> Date {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)

        if let date = fractionalDateFormatter().date(from: value)
            ?? wholeSecondDateFormatter().date(from: value) {
            return date
        }

        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Invalid backup date: \(value)"
        )
    }

    private static func fractionalDateFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    private static func wholeSecondDateFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }
}

extension BackupService: BackupServiceProviding {}
