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

enum BackupServiceError: LocalizedError, Equatable {
    case unsupportedVersion(Int)
    case invalidBackup(String)
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            return "不支持的备份版本: \(version)"
        case .invalidBackup(let message):
            return "备份文件无效: \(message)"
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

    init(
        fileManager: FileManager = .default,
        documentsDirectory: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    ) {
        self.fileManager = fileManager
        self.documentsDirectory = documentsDirectory
    }

    func exportBackup(from modelContext: ModelContext, exportedAt: Date = Date()) throws -> EasyNoteBackupV1 {
        let diaryEntries = try modelContext.fetch(FetchDescriptor<DiaryEntry>(
            sortBy: [SortDescriptor(\.creationDate, order: .forward)]
        ))
        let todoItems = try modelContext.fetch(FetchDescriptor<TodoItem>(
            sortBy: [SortDescriptor(\.creationDate, order: .forward)]
        ))
        let chatSessions = try modelContext.fetch(FetchDescriptor<ChatSession>(
            sortBy: [SortDescriptor(\.creationDate, order: .forward)]
        ))

        let audioExport = exportAudioAssets(for: diaryEntries)
        let sessionMessages = sessionMessages(from: chatSessions)

        let backup = EasyNoteBackupV1(
            version: Self.supportedVersion,
            exportedAt: exportedAt,
            diaryEntries: diaryEntries.map { entry in
                BackupDiaryEntry(
                    id: entry.id,
                    title: entry.title,
                    content: entry.content,
                    mood: entry.mood,
                    tags: entry.tags,
                    creationDate: entry.creationDate,
                    lastModified: entry.lastModified,
                    isFavorite: entry.isFavorite,
                    aiSummary: entry.aiSummary,
                    audioAssetId: audioExport.entryAudioAssetIds[entry.id]
                )
            },
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
            chatSessions: chatSessions.map { session in
                BackupChatSession(
                    id: session.id,
                    title: session.title,
                    creationDate: session.creationDate,
                    lastModifiedDate: session.lastModifiedDate,
                    messageIds: session.messages.map(\.id)
                )
            },
            sessionMessages: sessionMessages.map { message in
                BackupSessionMessage(
                    id: message.id,
                    content: message.content,
                    isUser: message.isUser,
                    timestamp: message.timestamp,
                    relatedEntryIds: message.relatedEntryIds
                )
            },
            audioAssets: audioExport.assets
        )

        try validate(backup)
        return backup
    }

    func encodeBackup(_ backup: EasyNoteBackupV1) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom(Self.encodeBackupDate)
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(backup)
    }

    func decodeAndValidateBackup(from data: Data) throws -> EasyNoteBackupV1 {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom(Self.decodeBackupDate)
        let backup = try decoder.decode(EasyNoteBackupV1.self, from: data)
        try validate(backup)
        return backup
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

    @discardableResult
    func importBackupData(_ data: Data, into modelContext: ModelContext) throws -> BackupImportResult {
        let backup = try decodeAndValidateBackup(from: data)
        return try importBackup(backup, into: modelContext)
    }

    @discardableResult
    func importBackup(_ backup: EasyNoteBackupV1, into modelContext: ModelContext) throws -> BackupImportResult {
        var restoredAudioURLs: [URL] = []

        do {
            try validate(backup)

            let existingDiaryEntries = try fetchByID(DiaryEntry.self, modelContext: modelContext)
            let existingTodoItems = try fetchByID(TodoItem.self, modelContext: modelContext)
            var messagesByID = try fetchByID(SessionMessage.self, modelContext: modelContext)
            let existingSessions = try fetchByID(ChatSession.self, modelContext: modelContext)

            var restoredAudioByAssetID: [UUID: URL] = [:]
            for asset in backup.audioAssets {
                let restoredURL = try restoreAudioAsset(asset)
                restoredAudioURLs.append(restoredURL)
                restoredAudioByAssetID[asset.id] = restoredURL
            }

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

            try modelContext.save()

            return BackupImportResult(summary: summary(for: backup))
        } catch let error as BackupServiceError {
            modelContext.rollback()
            removeRestoredAudioFiles(restoredAudioURLs)
            throw error
        } catch {
            modelContext.rollback()
            removeRestoredAudioFiles(restoredAudioURLs)
            throw BackupServiceError.saveFailed(error.localizedDescription)
        }
    }

    func validate(_ backup: EasyNoteBackupV1) throws {
        guard backup.version == Self.supportedVersion else {
            throw BackupServiceError.unsupportedVersion(backup.version)
        }

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
        for session in backup.chatSessions {
            try ensureUnique(session.messageIds, name: "会话消息 ID")

            for messageID in session.messageIds where !messageIDs.contains(messageID) {
                throw BackupServiceError.invalidBackup("会话引用了不存在的消息")
            }
        }

        for message in backup.sessionMessages where message.content.isEmpty {
            throw BackupServiceError.invalidBackup("消息内容不能为空")
        }

        for asset in backup.audioAssets {
            let pathExtension = asset.pathExtension.lowercased()
            if !Self.supportedAudioExtensions.contains(pathExtension) {
                throw BackupServiceError.invalidBackup("不支持的录音格式: \(asset.pathExtension)")
            }

            if asset.byteCount != asset.data.count {
                throw BackupServiceError.invalidBackup("录音资产大小不匹配")
            }
        }
    }

    private func exportAudioAssets(for entries: [DiaryEntry]) -> (assets: [BackupAudioAsset], entryAudioAssetIds: [UUID: UUID]) {
        var assets: [BackupAudioAsset] = []
        var entryAudioAssetIds: [UUID: UUID] = [:]

        for entry in entries {
            guard let audioURL = entry.audioURL,
                  audioURL.isFileURL,
                  Self.supportedAudioExtensions.contains(audioURL.pathExtension.lowercased()),
                  fileManager.fileExists(atPath: audioURL.path),
                  let data = try? Data(contentsOf: audioURL) else {
                continue
            }

            let assetID = UUID()
            assets.append(BackupAudioAsset(
                id: assetID,
                originalFilename: audioURL.lastPathComponent,
                pathExtension: audioURL.pathExtension.lowercased(),
                byteCount: data.count,
                data: data
            ))
            entryAudioAssetIds[entry.id] = assetID
        }

        return (assets, entryAudioAssetIds)
    }

    private func restoreAudioAsset(_ asset: BackupAudioAsset) throws -> URL {
        try fileManager.createDirectory(at: documentsDirectory, withIntermediateDirectories: true)

        let restoredURL = availableRestoredAudioURL(for: asset)

        try asset.data.write(to: restoredURL, options: .atomic)
        return restoredURL
    }

    private func removeRestoredAudioFiles(_ urls: [URL]) {
        for url in urls where fileManager.fileExists(atPath: url.path) {
            try? fileManager.removeItem(at: url)
        }
    }

    private func sessionMessages(from sessions: [ChatSession]) -> [SessionMessage] {
        var seen = Set<UUID>()
        var messages: [SessionMessage] = []

        for session in sessions {
            for message in session.messages where !seen.contains(message.id) {
                seen.insert(message.id)
                messages.append(message)
            }
        }

        return messages.sorted { lhs, rhs in
            if lhs.timestamp == rhs.timestamp {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.timestamp < rhs.timestamp
        }
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

    private func availableRestoredAudioURL(for asset: BackupAudioAsset) -> URL {
        let pathExtension = asset.pathExtension.lowercased()
        let baseFilename = "restored_recording_\(asset.id.uuidString)"
        let preferredURL = documentsDirectory.appendingPathComponent("\(baseFilename).\(pathExtension)")

        guard fileManager.fileExists(atPath: preferredURL.path) else {
            return preferredURL
        }

        return documentsDirectory.appendingPathComponent("\(baseFilename)_\(UUID().uuidString).\(pathExtension)")
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
