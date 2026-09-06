import Foundation
import Security

final class LocalKeyStore: CredentialStoring, @unchecked Sendable {
    private let defaults: UserDefaults
    private let keyPrefix: String

    init(defaults: UserDefaults = .standard, keyPrefix: String = "planKey.") {
        self.defaults = defaults
        self.keyPrefix = keyPrefix
    }

    func save(_ secret: String, for id: UUID) throws {
        defaults.set(secret, forKey: storageKey(for: id))
    }

    func read(for id: UUID) throws -> String? {
        defaults.string(forKey: storageKey(for: id))
    }

    func delete(for id: UUID) throws {
        defaults.removeObject(forKey: storageKey(for: id))
    }

    private func storageKey(for id: UUID) -> String {
        "\(keyPrefix)\(id.uuidString)"
    }
}

final class KeychainSecretStore: SecureCredentialStoring, @unchecked Sendable {
    private let service: String

    init(service: String = "ai.routin.usage-monitor.credentials") {
        self.service = service
    }

    func save(_ secret: String, for id: UUID) throws {
        let account = id.uuidString
        let data = Data(secret.utf8)
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemCopyMatching(baseQuery as CFDictionary, nil)
        if status == errSecSuccess {
            let updateStatus = SecItemUpdate(
                baseQuery as CFDictionary,
                [kSecValueData as String: data] as CFDictionary
            )
            guard updateStatus == errSecSuccess else {
                throw KeychainSecretStoreError.status(updateStatus)
            }
            return
        }
        guard status == errSecItemNotFound else {
            throw KeychainSecretStoreError.status(status)
        }

        var addQuery = baseQuery
        addQuery[kSecValueData as String] = data
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainSecretStoreError.status(addStatus)
        }
    }

    func read(for id: UUID) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainSecretStoreError.status(status)
        }
        return String(data: data, encoding: .utf8)
    }

    func delete(for id: UUID) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainSecretStoreError.status(status)
        }
    }
}

enum KeychainSecretStoreError: Error, Equatable, Sendable {
    case status(OSStatus)
}

enum KeychainMigration {
    static func migrate(
        ids: [UUID],
        from oldStore: any CredentialStoring,
        to newStore: any CredentialStoring
    ) throws {
        for id in ids {
            guard let secret = try oldStore.read(for: id) else {
                continue
            }
            try newStore.save(secret, for: id)
            try oldStore.delete(for: id)
        }
    }

    static func restore(
        ids: [UUID],
        from keychainStore: any CredentialStoring,
        to appStore: any CredentialStoring
    ) throws {
        for id in ids {
            guard try appStore.read(for: id) == nil,
                  let secret = try keychainStore.read(for: id)
            else {
                continue
            }
            try appStore.save(secret, for: id)
            try keychainStore.delete(for: id)
        }
    }
}
