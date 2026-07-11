import Foundation
import SwiftData

protocol PersistenceFileOperating {
    func fileExists(atPath path: String) -> Bool
    func createDirectory(
        at url: URL,
        withIntermediateDirectories createIntermediates: Bool,
        attributes: [FileAttributeKey: Any]?
    ) throws
    func copyItem(at sourceURL: URL, to destinationURL: URL) throws
    func removeItem(at URL: URL) throws
}

extension FileManager: PersistenceFileOperating {}

struct PersistenceBootstrapDependencies {
    typealias ContainerFactory = (Schema, ModelConfiguration) throws -> ModelContainer

    var fileOperations: any PersistenceFileOperating
    var makeContainer: ContainerFactory
    var now: () -> Date

    static let live = PersistenceBootstrapDependencies(
        fileOperations: FileManager.default,
        makeContainer: { schema, configuration in
            try ModelContainer(
                for: schema,
                migrationPlan: EasyNoteMigrationPlan.self,
                configurations: [configuration]
            )
        },
        now: Date.init
    )
}

struct PersistenceBootstrapFailure: Identifiable {
    let id = UUID()
    let message: String
    let recoveryURL: URL?
}

@MainActor
final class PersistenceBootstrap: ObservableObject {
    enum State {
        case loading
        case ready(ModelContainer)
        case failed(PersistenceBootstrapFailure)
    }

    @Published private(set) var state: State = .loading

    let storeURL: URL
    let recoveryRootURL: URL
    let isStoredInMemoryOnly: Bool

    private let dependencies: PersistenceBootstrapDependencies
    private var hasAttemptedLoad = false

    var modelContainer: ModelContainer? {
        guard case .ready(let container) = state else { return nil }
        return container
    }

    var canCreateRecoveryCopy: Bool {
        !isStoredInMemoryOnly
    }

    init(
        storeURL: URL = URL.documentsDirectory.appending(path: "EasyNote.store"),
        recoveryRootURL: URL? = nil,
        isStoredInMemoryOnly: Bool = false,
        dependencies: PersistenceBootstrapDependencies = .live
    ) {
        self.storeURL = storeURL
        self.recoveryRootURL = recoveryRootURL
            ?? storeURL.deletingLastPathComponent().appending(path: "EasyNoteRecovery", directoryHint: .isDirectory)
        self.isStoredInMemoryOnly = isStoredInMemoryOnly
        self.dependencies = dependencies
    }

    func loadIfNeeded() {
        guard !hasAttemptedLoad else { return }
        hasAttemptedLoad = true
        openStore()
    }

    func retry() {
        openStore()
    }

    func createRecoveryCopyAndRebuild() {
        guard canCreateRecoveryCopy else { return }
        state = .loading

        let recoveryURL: URL
        do {
            recoveryURL = try createRecoveryCopy()
        } catch {
            state = .failed(PersistenceBootstrapFailure(
                message: "无法创建恢复副本，原数据库未被删除。\n\(error.localizedDescription)",
                recoveryURL: nil
            ))
            return
        }

        do {
            try removeStoreComponents()
            let container = try makeContainer()
            state = .ready(container)
        } catch {
            state = .failed(PersistenceBootstrapFailure(
                message: "恢复副本已创建，但无法重建数据库。\n\(error.localizedDescription)",
                recoveryURL: recoveryURL
            ))
        }
    }

    private func openStore() {
        state = .loading
        do {
            state = .ready(try makeContainer())
        } catch {
            state = .failed(PersistenceBootstrapFailure(
                message: "无法打开本地数据库。请重试，或先创建恢复副本再重建。\n\(error.localizedDescription)",
                recoveryURL: nil
            ))
        }
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = EasyNoteSchemaV1.schema
        let configuration: ModelConfiguration
        if isStoredInMemoryOnly {
            configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        } else {
            configuration = ModelConfiguration(
                "EasyNote",
                schema: schema,
                url: storeURL,
                allowsSave: true,
                cloudKitDatabase: .none
            )
        }
        return try dependencies.makeContainer(schema, configuration)
    }

    private func createRecoveryCopy() throws -> URL {
        try dependencies.fileOperations.createDirectory(
            at: recoveryRootURL,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let timestamp = Self.recoveryTimestamp.string(from: dependencies.now())
        let recoveryURL = uniqueRecoveryDirectory(for: timestamp)
        try dependencies.fileOperations.createDirectory(
            at: recoveryURL,
            withIntermediateDirectories: false,
            attributes: nil
        )

        for sourceURL in storeComponentURLs where fileExists(at: sourceURL) {
            let destinationURL = recoveryURL.appendingPathComponent(sourceURL.lastPathComponent)
            try dependencies.fileOperations.copyItem(at: sourceURL, to: destinationURL)
        }
        return recoveryURL
    }

    private func removeStoreComponents() throws {
        for url in storeComponentURLs where fileExists(at: url) {
            try dependencies.fileOperations.removeItem(at: url)
        }
    }

    private var storeComponentURLs: [URL] {
        [
            storeURL,
            URL(fileURLWithPath: storeURL.path + "-wal"),
            URL(fileURLWithPath: storeURL.path + "-shm")
        ]
    }

    private func fileExists(at url: URL) -> Bool {
        dependencies.fileOperations.fileExists(atPath: url.path)
    }

    private func uniqueRecoveryDirectory(for timestamp: String) -> URL {
        var candidate = recoveryRootURL.appending(path: timestamp, directoryHint: .isDirectory)
        var suffix = 1
        while fileExists(at: candidate) {
            candidate = recoveryRootURL.appending(path: "\(timestamp)-\(suffix)", directoryHint: .isDirectory)
            suffix += 1
        }
        return candidate
    }

    private static let recoveryTimestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return formatter
    }()
}
