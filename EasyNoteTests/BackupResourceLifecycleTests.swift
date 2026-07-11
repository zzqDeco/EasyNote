import Foundation
import SwiftData
import Testing
@testable import EasyNote

@MainActor
struct BackupResourceLifecycleTests {
    @Test func defaultLimitsMatchBackupResourceContract() {
        let limits = BackupLimits.default

        #expect(limits.maxFileBytes == 64 * 1_024 * 1_024)
        #expect(limits.maxSingleAudioBytes == 16 * 1_024 * 1_024)
        #expect(limits.maxTotalAudioBytes == 48 * 1_024 * 1_024)
        #expect(limits.maxDiaryEntries == 10_000)
        #expect(limits.maxTodoItems == 50_000)
        #expect(limits.maxChatSessions == 5_000)
        #expect(limits.maxSessionMessages == 100_000)
        #expect(limits.maxAudioAssets == 500)
    }

    @Test func rawFileSizeAcceptsExactBoundaryAndRejectsBeforeDecode() async throws {
        let backup = makeBackup(diaryCount: 1)
        let data = try await BackupService().encodeBackup(backup)
        let exactService = BackupService(limits: BackupLimits(maxFileBytes: data.count))

        #expect(try await exactService.decodeAndValidateBackup(from: data) == backup)

        let overService = BackupService(limits: BackupLimits(maxFileBytes: data.count - 1))
        await expectLimit(.fileBytes) {
            _ = try await overService.decodeAndValidateBackup(from: data)
        }

        let malformedOversizedData = Data(repeating: 0xFF, count: 2)
        await expectLimit(.fileBytes) {
            _ = try await BackupService(limits: BackupLimits(maxFileBytes: 1))
                .decodeAndValidateBackup(from: malformedOversizedData)
        }
    }

    @Test func everyDecodedEntityCountAcceptsBoundaryAndRejectsOneOver() async throws {
        try await assertDecodedCountLimit(
            .diaryEntries,
            limits: BackupLimits(maxDiaryEntries: 1),
            exact: makeBackup(diaryCount: 1),
            over: makeBackup(diaryCount: 2)
        )
        try await assertDecodedCountLimit(
            .todoItems,
            limits: BackupLimits(maxTodoItems: 1),
            exact: makeBackup(todoCount: 1),
            over: makeBackup(todoCount: 2)
        )
        try await assertDecodedCountLimit(
            .chatSessions,
            limits: BackupLimits(maxChatSessions: 1),
            exact: makeBackup(sessionCount: 1),
            over: makeBackup(sessionCount: 2)
        )
        try await assertDecodedCountLimit(
            .sessionMessages,
            limits: BackupLimits(maxSessionMessages: 1),
            exact: makeBackup(messageCount: 1),
            over: makeBackup(messageCount: 2)
        )
        try await assertDecodedCountLimit(
            .audioAssets,
            limits: BackupLimits(maxAudioAssets: 1),
            exact: makeBackup(audioDataSizes: [1]),
            over: makeBackup(audioDataSizes: [1, 1])
        )
    }

    @Test func decodedAudioLimitsAcceptExactBoundariesAndRejectOneOver() async throws {
        try await assertDecodedCountLimit(
            .singleAudioBytes,
            limits: BackupLimits(maxSingleAudioBytes: 1),
            exact: makeBackup(audioDataSizes: [1]),
            over: makeBackup(audioDataSizes: [2])
        )
        try await assertDecodedCountLimit(
            .totalAudioBytes,
            limits: BackupLimits(maxSingleAudioBytes: 2, maxTotalAudioBytes: 2),
            exact: makeBackup(audioDataSizes: [1, 1]),
            over: makeBackup(audioDataSizes: [2, 1])
        )
    }

    @Test func limitFailureCreatesNoModelsOrFiles() async throws {
        let context = try makeModelContext()
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let backup = makeAudioBackup(data: Data([0x01, 0x02]))
        let service = BackupService(
            documentsDirectory: directory,
            limits: BackupLimits(maxSingleAudioBytes: 1)
        )

        await expectLimit(.singleAudioBytes) {
            _ = try await service.importBackup(backup, into: context)
        }

        #expect(try context.fetch(FetchDescriptor<DiaryEntry>()).isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).isEmpty)
    }

    @Test func jsonAndAudioWorkRunOffMainWhileSwiftDataSaveRunsOnMain() async throws {
        let context = try makeModelContext()
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let sourceURL = directory.appendingPathComponent("recording_source.caf")
        try Data([0x01]).write(to: sourceURL)
        let diary = DiaryEntry(title: "background")
        diary.audioURL = sourceURL
        context.insert(diary)
        try context.save()

        let observation = BackgroundObservation()
        var saveWasOnMain = false
        let service = BackupService(
            documentsDirectory: directory,
            saveModelContext: { modelContext in
                saveWasOnMain = Thread.isMainThread
                try modelContext.save()
            },
            backgroundWorkObserver: {
                observation.record(isMainThread: Thread.isMainThread)
            }
        )

        let backup = try await service.exportBackup(from: context)
        let data = try await service.encodeBackup(backup)
        let decoded = try await service.decodeAndValidateBackup(from: data)
        _ = try await service.importBackup(decoded, into: context)

        #expect(observation.values.count >= 5)
        #expect(observation.values.allSatisfy { !$0 })
        #expect(saveWasOnMain)
    }

    @Test func repeatedImportUsesOneDeterministicAssetFilename() async throws {
        let context = try makeModelContext()
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let audioID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
        let diaryID = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
        let backup = makeAudioBackup(diaryID: diaryID, audioID: audioID, data: Data([0x01, 0x02]))
        let service = BackupService(documentsDirectory: directory)

        _ = try await service.importBackup(backup, into: context)
        _ = try await service.importBackup(backup, into: context)

        let diary = try #require(try context.fetch(FetchDescriptor<DiaryEntry>()).first)
        let expectedURL = directory.appendingPathComponent("restored_recording_\(audioID.uuidString).caf")
        #expect(diary.audioURL == expectedURL)
        #expect(try Data(contentsOf: expectedURL) == Data([0x01, 0x02]))
        #expect(try managedImportFiles(in: directory, audioID: audioID) == [expectedURL])
    }

    @Test func stagedFileFailureRestoresPriorFilesAndWritesNoModels() async throws {
        let context = try makeModelContext()
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000201")!
        let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000202")!
        let firstURL = directory.appendingPathComponent("restored_recording_\(firstID.uuidString).caf")
        let secondURL = directory.appendingPathComponent("restored_recording_\(secondID.uuidString).caf")
        try Data([0xA1]).write(to: firstURL)
        try Data([0xA2]).write(to: secondURL)
        let backup = makeBackup(audioAssets: [
            makeAudioAsset(id: firstID, data: Data([0xB1])),
            makeAudioAsset(id: secondID, data: Data([0xB2]))
        ])
        let service = BackupService(
            documentsDirectory: directory,
            fileOperationHook: { operation in
                if operation == .installStaged(secondURL) {
                    throw TestFailure.injected
                }
            }
        )

        do {
            _ = try await service.importBackup(backup, into: context)
            Issue.record("Expected staged install failure")
        } catch BackupServiceError.fileOperationFailed {
            // Expected: the staged transaction must restore both prior files.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(try Data(contentsOf: firstURL) == Data([0xA1]))
        #expect(try Data(contentsOf: secondURL) == Data([0xA2]))
        #expect(try context.fetch(FetchDescriptor<DiaryEntry>()).isEmpty)
        #expect(try transactionDirectories(in: directory).isEmpty)
    }

    @Test func rollbackCopyFailureNeverRemovesTheUncopiedOriginal() async throws {
        let context = try makeModelContext()
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let audioID = UUID(uuidString: "00000000-0000-0000-0000-000000000250")!
        let targetURL = directory.appendingPathComponent("restored_recording_\(audioID.uuidString).caf")
        try Data([0xD1]).write(to: targetURL)
        let backup = makeBackup(audioAssets: [makeAudioAsset(id: audioID, data: Data([0xD2]))])
        let service = BackupService(
            documentsDirectory: directory,
            fileOperationHook: { operation in
                if operation == .preserveExisting(targetURL) {
                    throw TestFailure.injected
                }
            }
        )

        do {
            _ = try await service.importBackup(backup, into: context)
            Issue.record("Expected rollback-copy failure")
        } catch BackupServiceError.fileOperationFailed {
            // Expected: the original was never marked as replaceable without a rollback copy.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(try Data(contentsOf: targetURL) == Data([0xD1]))
        #expect(try transactionDirectories(in: directory).isEmpty)
    }

    @Test func saveFailureRestoresOverwrittenAudioAndRollsBackModels() async throws {
        let context = try makeModelContext()
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let audioID = UUID(uuidString: "00000000-0000-0000-0000-000000000301")!
        let diaryID = UUID(uuidString: "00000000-0000-0000-0000-000000000302")!
        let targetURL = directory.appendingPathComponent("restored_recording_\(audioID.uuidString).caf")
        try Data([0xC1]).write(to: targetURL)
        let localDiary = DiaryEntry(id: diaryID, title: "local")
        localDiary.audioURL = targetURL
        context.insert(localDiary)
        try context.save()
        let backup = makeAudioBackup(diaryID: diaryID, audioID: audioID, data: Data([0xC2]), title: "imported")
        let service = BackupService(
            documentsDirectory: directory,
            saveModelContext: { _ in throw TestFailure.injected }
        )

        do {
            _ = try await service.importBackup(backup, into: context)
            Issue.record("Expected save failure")
        } catch BackupServiceError.saveFailed {
            // Expected: the injected save failure must trigger filesystem rollback.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        let persistedDiary = try #require(try context.fetch(FetchDescriptor<DiaryEntry>()).first)
        #expect(persistedDiary.title == "local")
        #expect(persistedDiary.audioURL == targetURL)
        #expect(try Data(contentsOf: targetURL) == Data([0xC1]))
        #expect(try transactionDirectories(in: directory).isEmpty)
    }

    @Test func successfulImportCleansOnlyUnreferencedManagedDocumentRecordings() async throws {
        let context = try makeModelContext()
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let referencedURL = directory.appendingPathComponent("recording_1.caf")
        let orphanURL = directory.appendingPathComponent("recording_2.caf")
        let restoredOrphanURL = directory.appendingPathComponent("restored_recording_00000000-0000-0000-0000-000000000401.m4a")
        let userAudioURL = directory.appendingPathComponent("voice-note.caf")
        let similarlyNamedTextURL = directory.appendingPathComponent("recording_notes.txt")
        let nestedDirectory = directory.appendingPathComponent("folder", isDirectory: true)
        let nestedRecordingURL = nestedDirectory.appendingPathComponent("recording_3.caf")
        let similarlyNamedDirectory = directory.appendingPathComponent("recording_folder.caf", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: similarlyNamedDirectory, withIntermediateDirectories: true)
        for url in [referencedURL, orphanURL, restoredOrphanURL, userAudioURL, similarlyNamedTextURL, nestedRecordingURL] {
            try Data([0x01]).write(to: url)
        }
        let diary = DiaryEntry(title: "keep referenced audio")
        diary.audioURL = referencedURL
        context.insert(diary)
        try context.save()

        _ = try await BackupService(documentsDirectory: directory)
            .importBackup(makeBackup(), into: context)

        #expect(FileManager.default.fileExists(atPath: referencedURL.path))
        #expect(!FileManager.default.fileExists(atPath: orphanURL.path))
        #expect(!FileManager.default.fileExists(atPath: restoredOrphanURL.path))
        #expect(FileManager.default.fileExists(atPath: userAudioURL.path))
        #expect(FileManager.default.fileExists(atPath: similarlyNamedTextURL.path))
        #expect(FileManager.default.fileExists(atPath: nestedRecordingURL.path))
        #expect(FileManager.default.fileExists(atPath: similarlyNamedDirectory.path))
    }

    @Test func existingV1JSONFixtureRemainsReadableWithUnchangedFields() async throws {
        let json = """
        {
          "version": 1,
          "exportedAt": "2026-06-17T10:00:00.000Z",
          "diaryEntries": [{
            "id": "00000000-0000-0000-0000-000000000501",
            "title": "V1 diary",
            "content": "compatible",
            "tags": [],
            "creationDate": "2026-06-17T10:00:00.000Z",
            "lastModified": "2026-06-17T10:00:00.000Z",
            "isFavorite": false,
            "audioAssetId": "00000000-0000-0000-0000-000000000502"
          }],
          "todoItems": [],
          "chatSessions": [],
          "sessionMessages": [],
          "audioAssets": [{
            "id": "00000000-0000-0000-0000-000000000502",
            "originalFilename": "recording.caf",
            "pathExtension": "caf",
            "byteCount": 3,
            "data": "AQID"
          }]
        }
        """

        let backup = try await BackupService().decodeAndValidateBackup(from: Data(json.utf8))

        #expect(backup.version == 1)
        #expect(backup.diaryEntries.first?.title == "V1 diary")
        #expect(backup.diaryEntries.first?.mood == nil)
        #expect(backup.diaryEntries.first?.aiSummary == nil)
        #expect(backup.audioAssets.first?.data == Data([0x01, 0x02, 0x03]))
        #expect(BackupService.fileExtension == "easynotebackup")
    }

    private func assertDecodedCountLimit(
        _ expectedLimit: BackupResourceLimit,
        limits: BackupLimits,
        exact: EasyNoteBackupV1,
        over: EasyNoteBackupV1
    ) async throws {
        let encoderService = BackupService()
        let exactData = try await encoderService.encodeBackup(exact)
        let overData = try await encoderService.encodeBackup(over)
        let service = BackupService(limits: limits)

        #expect(try await service.decodeAndValidateBackup(from: exactData) == exact)
        await expectLimit(expectedLimit) {
            _ = try await service.decodeAndValidateBackup(from: overData)
        }
    }

    private func expectLimit(
        _ expectedLimit: BackupResourceLimit,
        operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            Issue.record("Expected \(expectedLimit.rawValue) resource limit")
        } catch BackupServiceError.resourceLimitExceeded(let actualLimit, _, _) {
            #expect(actualLimit == expectedLimit)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    private func makeBackup(
        diaryCount: Int = 0,
        todoCount: Int = 0,
        sessionCount: Int = 0,
        messageCount: Int = 0,
        audioDataSizes: [Int] = [],
        audioAssets: [BackupAudioAsset]? = nil
    ) -> EasyNoteBackupV1 {
        let now = Date(timeIntervalSince1970: 1_781_694_000)
        return EasyNoteBackupV1(
            version: BackupService.supportedVersion,
            exportedAt: now,
            diaryEntries: (0..<diaryCount).map { index in
                BackupDiaryEntry(
                    id: UUID(),
                    title: "diary-\(index)",
                    content: "",
                    mood: nil,
                    tags: [],
                    creationDate: now,
                    lastModified: now,
                    isFavorite: false,
                    aiSummary: nil,
                    audioAssetId: nil
                )
            },
            todoItems: (0..<todoCount).map { index in
                BackupTodoItem(
                    id: UUID(),
                    title: "todo-\(index)",
                    isCompleted: false,
                    priority: .medium,
                    deadline: nil,
                    notes: nil,
                    isRecurring: false,
                    recurringInterval: nil,
                    creationDate: now
                )
            },
            chatSessions: (0..<sessionCount).map { index in
                BackupChatSession(
                    id: UUID(),
                    title: "session-\(index)",
                    creationDate: now,
                    lastModifiedDate: now,
                    messageIds: []
                )
            },
            sessionMessages: (0..<messageCount).map { index in
                BackupSessionMessage(
                    id: UUID(),
                    content: "message-\(index)",
                    isUser: true,
                    timestamp: now,
                    relatedEntryIds: []
                )
            },
            audioAssets: audioAssets ?? audioDataSizes.map { size in
                makeAudioAsset(id: UUID(), data: Data(repeating: 0x01, count: size))
            }
        )
    }

    private func makeAudioBackup(
        diaryID: UUID = UUID(),
        audioID: UUID = UUID(),
        data: Data,
        title: String = "audio diary"
    ) -> EasyNoteBackupV1 {
        var backup = makeBackup(audioAssets: [makeAudioAsset(id: audioID, data: data)])
        backup.diaryEntries = [
            BackupDiaryEntry(
                id: diaryID,
                title: title,
                content: "",
                mood: nil,
                tags: [],
                creationDate: backup.exportedAt,
                lastModified: backup.exportedAt,
                isFavorite: false,
                aiSummary: nil,
                audioAssetId: audioID
            )
        ]
        return backup
    }

    private func makeAudioAsset(id: UUID, data: Data) -> BackupAudioAsset {
        BackupAudioAsset(
            id: id,
            originalFilename: "recording.caf",
            pathExtension: "caf",
            byteCount: data.count,
            data: data
        )
    }

    private func makeModelContext() throws -> ModelContext {
        let schema = Schema([DiaryEntry.self, TodoItem.self, ChatSession.self, SessionMessage.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BackupResourceLifecycleTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func managedImportFiles(in directory: URL, audioID: UUID) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("restored_recording_\(audioID.uuidString)") }
    }

    private func transactionDirectories(in directory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: []
        ).filter { $0.lastPathComponent.hasPrefix(".EasyNoteBackupImport-") }
    }

    private enum TestFailure: Error {
        case injected
    }

    private final class BackgroundObservation: @unchecked Sendable {
        private let lock = NSLock()
        private var recordedValues: [Bool] = []

        var values: [Bool] {
            lock.withLock { recordedValues }
        }

        func record(isMainThread: Bool) {
            lock.withLock {
                recordedValues.append(isMainThread)
            }
        }
    }
}
