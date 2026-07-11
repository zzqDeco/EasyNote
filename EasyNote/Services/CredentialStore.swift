import Foundation
import Security

protocol CredentialStoreProviding {
    func readAPIKey() throws -> String?
    func saveAPIKey(_ apiKey: String) throws
    func deleteAPIKey() throws
    func migrateLegacyAPIKeyIfNeeded() throws -> CredentialMigrationResult
}

enum CredentialMigrationResult: Equatable {
    case noLegacyCredential
    case migrated
}

enum CredentialStoreError: LocalizedError, Equatable {
    case emptyCredential
    case invalidCredentialData
    case keychainFailure(operation: String, status: OSStatus)
    case verificationFailed

    var errorDescription: String? {
        switch self {
        case .emptyCredential:
            return "API 密钥不能为空。"
        case .invalidCredentialData:
            return "钥匙串中的 API 密钥数据无法读取。"
        case let .keychainFailure(operation, status):
            let detail = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
            return "钥匙串\(operation)失败：\(detail)"
        case .verificationFailed:
            return "API 密钥写入后校验失败，旧数据已保留。"
        }
    }
}

protocol SecurityItemAdapting {
    func add(_ attributes: [String: Any]) -> OSStatus
    func copyMatching(_ query: [String: Any]) -> (status: OSStatus, result: Any?)
    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus
    func delete(_ query: [String: Any]) -> OSStatus
}

struct SystemSecurityItemAdapter: SecurityItemAdapting {
    func add(_ attributes: [String: Any]) -> OSStatus {
        SecItemAdd(attributes as CFDictionary, nil)
    }

    func copyMatching(_ query: [String: Any]) -> (status: OSStatus, result: Any?) {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return (status, result)
    }

    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    }

    func delete(_ query: [String: Any]) -> OSStatus {
        SecItemDelete(query as CFDictionary)
    }
}

final class KeychainCredentialStore: CredentialStoreProviding {
    static let service = "io.github.zzqDeco.EasyNote"
    static let account = "deepseek_api_key"
    static let legacyDefaultsKey = "openai_api_key"

    private let security: any SecurityItemAdapting
    private let userDefaults: UserDefaults

    init(
        security: any SecurityItemAdapting = SystemSecurityItemAdapter(),
        userDefaults: UserDefaults = .standard
    ) {
        self.security = security
        self.userDefaults = userDefaults
    }

    func readAPIKey() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        let response = security.copyMatching(query)
        switch response.status {
        case errSecSuccess:
            guard let data = response.result as? Data,
                  let apiKey = String(data: data, encoding: .utf8) else {
                throw CredentialStoreError.invalidCredentialData
            }
            return apiKey
        case errSecItemNotFound:
            return nil
        default:
            throw CredentialStoreError.keychainFailure(operation: "读取", status: response.status)
        }
    }

    func saveAPIKey(_ apiKey: String) throws {
        guard !apiKey.isEmpty else {
            throw CredentialStoreError.emptyCredential
        }

        let data = Data(apiKey.utf8)
        var attributes = baseQuery
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        attributes[kSecValueData as String] = data

        let addStatus = security.add(attributes)
        if addStatus == errSecSuccess {
            return
        }

        guard addStatus == errSecDuplicateItem else {
            throw CredentialStoreError.keychainFailure(operation: "写入", status: addStatus)
        }

        let updateStatus = security.update(
            baseQuery,
            attributes: [kSecValueData as String: data]
        )
        guard updateStatus == errSecSuccess else {
            throw CredentialStoreError.keychainFailure(operation: "更新", status: updateStatus)
        }
    }

    func deleteAPIKey() throws {
        let status = security.delete(baseQuery)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialStoreError.keychainFailure(operation: "删除", status: status)
        }
    }

    func migrateLegacyAPIKeyIfNeeded() throws -> CredentialMigrationResult {
        guard let legacyAPIKey = userDefaults.string(forKey: Self.legacyDefaultsKey),
              !legacyAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .noLegacyCredential
        }

        let existingAPIKey = try readAPIKey()
        let migrationValue: String
        if let existingAPIKey,
           !existingAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            migrationValue = existingAPIKey
        } else {
            migrationValue = legacyAPIKey
        }

        try saveAPIKey(migrationValue)
        guard try readAPIKey() == migrationValue else {
            throw CredentialStoreError.verificationFailed
        }

        userDefaults.removeObject(forKey: Self.legacyDefaultsKey)
        return .migrated
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account
        ]
    }
}
