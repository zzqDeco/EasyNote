import Foundation
import SwiftData
import Testing
@testable import EasyNote

@MainActor
struct PersistenceBootstrapTests {
    @Test func legacyStoreIsAdoptedAsV1ThenReopensWithMigrationPlan() throws {
        let paths = try makeStoreFiles(components: [:])
        defer { try? FileManager.default.removeItem(at: paths.root) }

        let legacySchema = LegacyUnversionedSchema.schema
        let expectedEntityNames = ["ChatSession", "DiaryEntry", "SessionMessage", "TodoItem"]
        #expect(legacySchema.entities.map(\.name).sorted() == expectedEntityNames)
        #expect(EasyNoteSchemaV1.schema.entities.map(\.name).sorted() == expectedEntityNames)

        try createLegacyStore(at: paths.store, schema: legacySchema)
        #expect(try adoptLegacyStoreAsV1(at: paths.store) == ["Existing entry"])
        #expect(try reopenAdoptedStoreWithMigrationPlan(at: paths.store) == ["Existing entry"])
        #expect(FileManager.default.fileExists(atPath: paths.store.path))
        #expect(!FileManager.default.fileExists(atPath: paths.recoveryRoot.path))
    }

    @Test func existingStoreOpensWithoutRecoveryOrDeletion() throws {
        let paths = try makeStoreFiles(components: ["EasyNote.store": "existing"])
        defer { try? FileManager.default.removeItem(at: paths.root) }
        var attempts = 0
        let bootstrap = makeBootstrap(paths: paths) { _, _ in
            attempts += 1
            return try makeInMemoryContainer()
        }

        bootstrap.loadIfNeeded()

        guard case .ready = bootstrap.state else {
            Issue.record("Expected existing store to open")
            return
        }
        #expect(attempts == 1)
        #expect(FileManager.default.fileExists(atPath: paths.store.path))
        #expect(!FileManager.default.fileExists(atPath: paths.recoveryRoot.path))
    }

    @Test func startupFailureExposesFailedStateAndRetryCanSucceed() throws {
        let paths = try makeStoreFiles(components: [:])
        defer { try? FileManager.default.removeItem(at: paths.root) }
        var attempts = 0
        let bootstrap = makeBootstrap(paths: paths) { _, _ in
            attempts += 1
            if attempts == 1 { throw PersistenceTestError.openFailed }
            return try makeInMemoryContainer()
        }

        bootstrap.loadIfNeeded()
        guard case .failed(let failure) = bootstrap.state else {
            Issue.record("Expected startup failure")
            return
        }
        #expect(failure.recoveryURL == nil)
        #expect(!FileManager.default.fileExists(atPath: paths.recoveryRoot.path))

        bootstrap.retry()

        guard case .ready = bootstrap.state else {
            Issue.record("Expected retry to succeed")
            return
        }
        #expect(attempts == 2)
    }

    @Test func recoveryCopiesStoreAndSQLiteSidecarsBeforeRebuild() throws {
        let components = [
            "EasyNote.store": "store",
            "EasyNote.store-wal": "wal",
            "EasyNote.store-shm": "shm"
        ]
        let paths = try makeStoreFiles(components: components)
        defer { try? FileManager.default.removeItem(at: paths.root) }
        var attempts = 0
        let bootstrap = makeBootstrap(paths: paths) { _, _ in
            attempts += 1
            if attempts == 1 { throw PersistenceTestError.openFailed }
            return try makeInMemoryContainer()
        }

        bootstrap.loadIfNeeded()
        bootstrap.createRecoveryCopyAndRebuild()

        guard case .ready = bootstrap.state else {
            Issue.record("Expected rebuild to succeed")
            return
        }
        let recoveryDirectory = try #require(
            FileManager.default.contentsOfDirectory(
                at: paths.recoveryRoot,
                includingPropertiesForKeys: nil
            ).first
        )
        for (filename, expectedContent) in components {
            let copiedURL = recoveryDirectory.appendingPathComponent(filename)
            #expect(try String(contentsOf: copiedURL, encoding: .utf8) == expectedContent)
            #expect(!FileManager.default.fileExists(atPath: paths.root.appendingPathComponent(filename).path))
        }
    }

    @Test func rebuildFailureKeepsRecoveryCopyAndReportsItsLocation() throws {
        let paths = try makeStoreFiles(components: ["EasyNote.store": "preserve me"])
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let bootstrap = makeBootstrap(paths: paths) { _, _ in
            throw PersistenceTestError.openFailed
        }

        bootstrap.loadIfNeeded()
        bootstrap.createRecoveryCopyAndRebuild()

        guard case .failed(let failure) = bootstrap.state else {
            Issue.record("Expected rebuild failure")
            return
        }
        let recoveryURL = try #require(failure.recoveryURL)
        let copiedStore = recoveryURL.appendingPathComponent("EasyNote.store")
        #expect(try String(contentsOf: copiedStore, encoding: .utf8) == "preserve me")
        #expect(!FileManager.default.fileExists(atPath: paths.store.path))
    }

    @Test func recoveryCopyFailureNeverRemovesSourceStoreComponents() throws {
        let paths = try makeStoreFiles(components: [
            "EasyNote.store": "store",
            "EasyNote.store-wal": "wal"
        ])
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let fileOperations = FailingCopyFileOperations(failingFilename: "EasyNote.store-wal")
        let bootstrap = PersistenceBootstrap(
            storeURL: paths.store,
            recoveryRootURL: paths.recoveryRoot,
            dependencies: PersistenceBootstrapDependencies(
                fileOperations: fileOperations,
                makeContainer: { _, _ in throw PersistenceTestError.openFailed },
                now: { Date(timeIntervalSince1970: 1_750_000_000) }
            )
        )

        bootstrap.loadIfNeeded()
        bootstrap.createRecoveryCopyAndRebuild()

        guard case .failed(let failure) = bootstrap.state else {
            Issue.record("Expected recovery copy failure")
            return
        }
        #expect(failure.recoveryURL == nil)
        #expect(fileOperations.removedURLs.isEmpty)
        #expect(FileManager.default.fileExists(atPath: paths.store.path))
        #expect(FileManager.default.fileExists(atPath: paths.store.path + "-wal"))
    }

    private func makeBootstrap(
        paths: StorePaths,
        makeContainer: @escaping PersistenceBootstrapDependencies.ContainerFactory
    ) -> PersistenceBootstrap {
        PersistenceBootstrap(
            storeURL: paths.store,
            recoveryRootURL: paths.recoveryRoot,
            dependencies: PersistenceBootstrapDependencies(
                fileOperations: FileManager.default,
                makeContainer: makeContainer,
                now: { Date(timeIntervalSince1970: 1_750_000_000) }
            )
        )
    }

    private func makeStoreFiles(components: [String: String]) throws -> StorePaths {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("EasyNotePersistenceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for (filename, content) in components {
            try Data(content.utf8).write(to: root.appendingPathComponent(filename))
        }
        return StorePaths(
            root: root,
            store: root.appendingPathComponent("EasyNote.store"),
            recoveryRoot: root.appendingPathComponent("EasyNoteRecovery", isDirectory: true)
        )
    }

    private func makeInMemoryContainer() throws -> ModelContainer {
        try ModelContainer(
            for: EasyNoteSchemaV1.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    private func createLegacyStore(at storeURL: URL, schema: Schema) throws {
        try autoreleasepool {
            let configuration = persistentConfiguration(at: storeURL, schema: schema)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            container.mainContext.insert(LegacyUnversionedSchema.DiaryEntry(title: "Existing entry"))
            try container.mainContext.save()
        }
    }

    private func adoptLegacyStoreAsV1(at storeURL: URL) throws -> [String] {
        try autoreleasepool {
            let configuration = persistentConfiguration(at: storeURL, schema: EasyNoteSchemaV1.schema)
            let container = try ModelContainer(
                for: EasyNoteSchemaV1.schema,
                configurations: [configuration]
            )
            return try container.mainContext.fetch(FetchDescriptor<DiaryEntry>()).map(\.title)
        }
    }

    private func reopenAdoptedStoreWithMigrationPlan(at storeURL: URL) throws -> [String] {
        try autoreleasepool {
            let configuration = persistentConfiguration(at: storeURL, schema: EasyNoteSchemaV1.schema)
            let container = try ModelContainer(
                for: EasyNoteSchemaV1.schema,
                migrationPlan: EasyNoteMigrationPlan.self,
                configurations: [configuration]
            )
            return try container.mainContext.fetch(FetchDescriptor<DiaryEntry>()).map(\.title)
        }
    }

    private func persistentConfiguration(at storeURL: URL, schema: Schema) -> ModelConfiguration {
        ModelConfiguration(
            "EasyNote",
            schema: schema,
            url: storeURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )
    }
}

private enum LegacyUnversionedSchema {
    static let schema = Schema([
        DiaryEntry.self,
        TodoItem.self,
        ChatSession.self,
        SessionMessage.self
    ])

    @Model
    final class DiaryEntry {
        var id: UUID
        var title: String
        var content: String
        var mood: String?
        var tags: [String]
        var creationDate: Date
        var lastModified: Date
        var isFavorite: Bool
        var audioURL: URL?
        var aiSummary: String?

        init(
            id: UUID = UUID(),
            title: String,
            content: String = "",
            mood: String? = nil,
            tags: [String] = [],
            isFavorite: Bool = false
        ) {
            self.id = id
            self.title = title
            self.content = content
            self.mood = mood
            self.tags = tags
            self.creationDate = Date()
            self.lastModified = Date()
            self.isFavorite = isFavorite
        }
    }

    @Model
    final class TodoItem {
        var id: UUID
        var title: String
        var isCompleted: Bool
        var priority: PriorityLevel
        var deadline: Date?
        var notes: String?
        var isRecurring: Bool
        var recurringInterval: String?
        var creationDate: Date

        init(
            id: UUID = UUID(),
            title: String,
            isCompleted: Bool = false,
            priority: PriorityLevel = .medium,
            deadline: Date? = nil,
            notes: String? = nil,
            isRecurring: Bool = false,
            recurringInterval: String? = nil
        ) {
            self.id = id
            self.title = title
            self.isCompleted = isCompleted
            self.priority = priority
            self.deadline = deadline
            self.notes = notes
            self.isRecurring = isRecurring
            self.recurringInterval = recurringInterval
            self.creationDate = Date()
        }

        enum PriorityLevel: String, Codable, Equatable {
            case high, medium, low
        }
    }

    @Model
    final class ChatSession {
        var id: UUID
        var title: String
        var creationDate: Date
        var lastModifiedDate: Date
        var messages: [LegacyUnversionedSchema.SessionMessage] = []

        init(
            id: UUID = UUID(),
            title: String = "New session",
            messages: [LegacyUnversionedSchema.SessionMessage] = []
        ) {
            self.id = id
            self.title = title
            self.creationDate = Date()
            self.lastModifiedDate = Date()
            self.messages = messages
        }
    }

    @Model
    final class SessionMessage {
        var id: UUID
        var content: String
        var isUser: Bool
        var timestamp: Date
        var relatedEntryIds: [String]

        init(
            id: UUID = UUID(),
            content: String,
            isUser: Bool,
            timestamp: Date = Date(),
            relatedEntryIds: [String] = []
        ) {
            self.id = id
            self.content = content
            self.isUser = isUser
            self.timestamp = timestamp
            self.relatedEntryIds = relatedEntryIds
        }
    }
}

private struct StorePaths {
    let root: URL
    let store: URL
    let recoveryRoot: URL
}

private enum PersistenceTestError: Error {
    case openFailed
    case copyFailed
}

private final class FailingCopyFileOperations: PersistenceFileOperating {
    let failingFilename: String
    private(set) var removedURLs: [URL] = []

    init(failingFilename: String) {
        self.failingFilename = failingFilename
    }

    func fileExists(atPath path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    func createDirectory(
        at url: URL,
        withIntermediateDirectories createIntermediates: Bool,
        attributes: [FileAttributeKey: Any]?
    ) throws {
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: createIntermediates,
            attributes: attributes
        )
    }

    func copyItem(at sourceURL: URL, to destinationURL: URL) throws {
        if sourceURL.lastPathComponent == failingFilename {
            throw PersistenceTestError.copyFailed
        }
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
    }

    func removeItem(at url: URL) throws {
        removedURLs.append(url)
        try FileManager.default.removeItem(at: url)
    }
}
