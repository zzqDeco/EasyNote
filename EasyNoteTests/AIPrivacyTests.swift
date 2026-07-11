import Combine
import Foundation
import Security
import Testing
@testable import EasyNote

struct AIPrivacyTests {
    @Test func keychainCredentialStoreSupportsCRUDWithRequiredAttributes() throws {
        let adapter = InMemorySecurityItemAdapter()
        let defaults = makeUserDefaults()
        let store = KeychainCredentialStore(security: adapter, userDefaults: defaults.instance)
        defer { defaults.remove() }

        #expect(try store.readAPIKey() == nil)

        try store.saveAPIKey("first-key")
        #expect(try store.readAPIKey() == "first-key")
        #expect(adapter.addCallCount == 1)
        #expect(adapter.lastAddedAttributes?[kSecAttrService as String] as? String == KeychainCredentialStore.service)
        #expect(adapter.lastAddedAttributes?[kSecAttrAccount as String] as? String == KeychainCredentialStore.account)
        #expect(
            adapter.lastAddedAttributes?[kSecAttrAccessible as String] as? String
                == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String
        )

        try store.saveAPIKey("updated-key")
        #expect(try store.readAPIKey() == "updated-key")
        #expect(adapter.updateCallCount == 1)

        try store.deleteAPIKey()
        #expect(try store.readAPIKey() == nil)
    }

    @Test func legacyCredentialMigrationIsVerifiedAndIdempotent() throws {
        let adapter = InMemorySecurityItemAdapter()
        let defaults = makeUserDefaults()
        defaults.instance.set("legacy-key", forKey: KeychainCredentialStore.legacyDefaultsKey)
        let store = KeychainCredentialStore(security: adapter, userDefaults: defaults.instance)
        defer { defaults.remove() }

        #expect(try store.migrateLegacyAPIKeyIfNeeded() == .migrated)
        #expect(try store.readAPIKey() == "legacy-key")
        #expect(defaults.instance.object(forKey: KeychainCredentialStore.legacyDefaultsKey) == nil)

        let addCallCount = adapter.addCallCount
        #expect(try store.migrateLegacyAPIKeyIfNeeded() == .noLegacyCredential)
        #expect(adapter.addCallCount == addCallCount)
    }

    @Test func migrationKeepsLegacyCredentialWhenKeychainWriteFails() {
        let adapter = InMemorySecurityItemAdapter()
        adapter.forcedAddStatus = errSecInteractionNotAllowed
        let defaults = makeUserDefaults()
        defaults.instance.set("legacy-key", forKey: KeychainCredentialStore.legacyDefaultsKey)
        let store = KeychainCredentialStore(security: adapter, userDefaults: defaults.instance)
        defer { defaults.remove() }

        #expect(throws: CredentialStoreError.self) {
            try store.migrateLegacyAPIKeyIfNeeded()
        }
        #expect(defaults.instance.string(forKey: KeychainCredentialStore.legacyDefaultsKey) == "legacy-key")
    }

    @Test func migrationKeepsLegacyCredentialWhenReadBackDoesNotMatch() {
        let adapter = InMemorySecurityItemAdapter()
        adapter.readResultAfterAdd = Data("different-key".utf8)
        let defaults = makeUserDefaults()
        defaults.instance.set("legacy-key", forKey: KeychainCredentialStore.legacyDefaultsKey)
        let store = KeychainCredentialStore(security: adapter, userDefaults: defaults.instance)
        defer { defaults.remove() }

        #expect(throws: CredentialStoreError.verificationFailed) {
            try store.migrateLegacyAPIKeyIfNeeded()
        }
        #expect(defaults.instance.string(forKey: KeychainCredentialStore.legacyDefaultsKey) == "legacy-key")
    }

    @Test func consentDefaultsDeniedAndSupportsGrantAndRevoke() {
        let defaults = makeUserDefaults()
        let store = AIContentConsentStore(userDefaults: defaults.instance)
        defer { defaults.remove() }

        #expect(store.isGranted == false)
        store.grant()
        #expect(store.isGranted)
        store.revoke()
        #expect(store.isGranted == false)
    }

    @Test func unconsentedRequestFailsBeforeHTTPClient() async throws {
        let credentials = InMemoryCredentialStore(apiKey: "configured-key")
        let consent = InMemoryConsentStore(isGranted: false)
        let httpClient = RecordingAIHTTPClient()
        let service = OpenAIService(
            credentialStore: credentials,
            consentStore: consent,
            httpClient: httpClient
        )

        let error = await publisherFailure(service.generateSummary(from: "private diary"))

        guard case let .apiError(message) = try #require(error) else {
            Issue.record("Expected consent denial to produce OpenAIError.apiError")
            return
        }
        #expect(message == AIContentConsentPolicy.requiredMessage)
        #expect(httpClient.requestCount == 0)
    }

    @Test func emptyCredentialFailsBeforeHTTPClient() async throws {
        let credentials = InMemoryCredentialStore(apiKey: nil)
        let consent = InMemoryConsentStore(isGranted: true)
        let httpClient = RecordingAIHTTPClient()
        let service = OpenAIService(
            credentialStore: credentials,
            consentStore: consent,
            httpClient: httpClient
        )

        let error = await publisherFailure(service.generateSummary(from: "private diary"))

        guard case let .apiError(message) = try #require(error) else {
            Issue.record("Expected empty credential to produce OpenAIError.apiError")
            return
        }
        #expect(message == "请在设置中添加DeepSeek API密钥后再使用AI功能")
        #expect(httpClient.requestCount == 0)
    }

    private func makeUserDefaults() -> (instance: UserDefaults, remove: () -> Void) {
        let suiteName = "AIPrivacyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, { defaults.removePersistentDomain(forName: suiteName) })
    }

    private func publisherFailure<T>(
        _ publisher: AnyPublisher<T, OpenAIError>
    ) async -> OpenAIError? {
        await withCheckedContinuation { continuation in
            var cancellable: AnyCancellable?
            cancellable = publisher.sink(
                receiveCompletion: { completion in
                    if case let .failure(error) = completion {
                        continuation.resume(returning: error)
                    } else {
                        continuation.resume(returning: nil)
                    }
                    cancellable?.cancel()
                },
                receiveValue: { _ in
                    continuation.resume(returning: nil)
                    cancellable?.cancel()
                }
            )
        }
    }
}

private final class InMemorySecurityItemAdapter: SecurityItemAdapting {
    var forcedAddStatus: OSStatus?
    var readResultAfterAdd: Data?
    private(set) var addCallCount = 0
    private(set) var updateCallCount = 0
    private(set) var lastAddedAttributes: [String: Any]?
    private var storedData: Data?

    func add(_ attributes: [String: Any]) -> OSStatus {
        addCallCount += 1
        lastAddedAttributes = attributes
        if let forcedAddStatus {
            return forcedAddStatus
        }
        guard storedData == nil else {
            return errSecDuplicateItem
        }
        storedData = attributes[kSecValueData as String] as? Data
        return errSecSuccess
    }

    func copyMatching(_ query: [String: Any]) -> (status: OSStatus, result: Any?) {
        if addCallCount > 0, let readResultAfterAdd {
            return (errSecSuccess, readResultAfterAdd)
        }
        guard let storedData else {
            return (errSecItemNotFound, nil)
        }
        return (errSecSuccess, storedData)
    }

    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        updateCallCount += 1
        guard storedData != nil else {
            return errSecItemNotFound
        }
        storedData = attributes[kSecValueData as String] as? Data
        return errSecSuccess
    }

    func delete(_ query: [String: Any]) -> OSStatus {
        guard storedData != nil else {
            return errSecItemNotFound
        }
        storedData = nil
        return errSecSuccess
    }
}

final class InMemoryCredentialStore: CredentialStoreProviding {
    private var storedAPIKey: String?

    init(apiKey: String?) {
        storedAPIKey = apiKey
    }

    func readAPIKey() throws -> String? {
        storedAPIKey
    }

    func saveAPIKey(_ apiKey: String) throws {
        storedAPIKey = apiKey
    }

    func deleteAPIKey() throws {
        storedAPIKey = nil
    }

    func migrateLegacyAPIKeyIfNeeded() throws -> CredentialMigrationResult {
        .noLegacyCredential
    }
}

final class InMemoryConsentStore: AIContentConsentProviding {
    private(set) var isGranted: Bool

    init(isGranted: Bool) {
        self.isGranted = isGranted
    }

    func grant() {
        isGranted = true
    }

    func revoke() {
        isGranted = false
    }
}

final class RecordingAIHTTPClient: AIHTTPClientProviding {
    private(set) var requestCount = 0

    func dataTaskPublisher(
        for request: URLRequest
    ) -> AnyPublisher<(data: Data, response: URLResponse), URLError> {
        requestCount += 1
        return Fail(error: URLError(.badServerResponse))
            .eraseToAnyPublisher()
    }
}
