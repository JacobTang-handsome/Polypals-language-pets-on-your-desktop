import Foundation
import Security

protocol APIKeyProviding: Sendable {
    func loadAPIKey() throws -> String?
    func saveAPIKey(_ key: String) throws
    func deleteAPIKey() throws
    func loadAPIKey(for provider: ModelProvider) throws -> String?
    func saveAPIKey(_ key: String, for provider: ModelProvider) throws
    func deleteAPIKey(for provider: ModelProvider) throws
}

extension APIKeyProviding {
    func loadAPIKey(for provider: ModelProvider) throws -> String? {
        provider == .openAI ? try loadAPIKey() : nil
    }
    func saveAPIKey(_ key: String, for provider: ModelProvider) throws {
        if provider == .openAI { try saveAPIKey(key) }
    }
    func deleteAPIKey(for provider: ModelProvider) throws {
        if provider == .openAI { try deleteAPIKey() }
    }
}

enum KeychainError: LocalizedError {
    case status(OSStatus)

    var errorDescription: String? {
        switch self {
        case let .status(status): "Keychain 操作失败（\(status)）。"
        }
    }
}

struct KeychainAPIKeyStore: APIKeyProviding {
    private let account = "user-api-key"

    func loadAPIKey() throws -> String? { try loadAPIKey(for: .openAI) }
    func saveAPIKey(_ key: String) throws { try saveAPIKey(key, for: .openAI) }
    func deleteAPIKey() throws { try deleteAPIKey(for: .openAI) }

    func loadAPIKey(for provider: ModelProvider) throws -> String? {
        if let value = try loadAPIKey(from: baseQuery(provider)) { return value }
        // v0.1/v0.2 used an unscoped service name. Migrate that value into
        // the provider-scoped OpenAI slot on first read without deleting the
        // legacy entry until the new value is safely written.
        guard provider == .openAI, let legacy = try loadAPIKey(from: baseQuery(service: "com.polypals.PolyPals")) else { return nil }
        try saveAPIKey(legacy, for: .openAI)
        return legacy
    }

    private func loadAPIKey(from queryBase: [String: Any]) throws -> String? {
        var query = queryBase
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.status(status) }
        guard let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func saveAPIKey(_ key: String, for provider: ModelProvider) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            try deleteAPIKey(for: provider)
            return
        }
        let data = Data(trimmed.utf8)
        let updateStatus = SecItemUpdate(
            baseQuery(provider) as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecItemNotFound {
        var query = baseQuery(provider)
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.status(addStatus) }
        } else if updateStatus != errSecSuccess {
            throw KeychainError.status(updateStatus)
        }
    }

    func deleteAPIKey(for provider: ModelProvider) throws {
        let status = SecItemDelete(baseQuery(provider) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.status(status)
        }
    }

    private func baseQuery(_ provider: ModelProvider) -> [String: Any] {
        baseQuery(service: "com.polypals.PolyPals.\(provider.rawValue.lowercased())")
    }

    private func baseQuery(service: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any
        ]
    }
}

struct InMemoryAPIKeyStore: APIKeyProviding, @unchecked Sendable {
    private final class Storage: @unchecked Sendable {
        let lock = NSLock()
        var keys: [ModelProvider: String] = [:]
    }
    private let storage = Storage()

    init(key: String? = nil) { storage.keys[.openAI] = key }

    func loadAPIKey() throws -> String? {
        try loadAPIKey(for: .openAI)
    }

    func saveAPIKey(_ key: String) throws {
        try saveAPIKey(key, for: .openAI)
    }

    func deleteAPIKey() throws {
        try deleteAPIKey(for: .openAI)
    }

    func loadAPIKey(for provider: ModelProvider) throws -> String? {
        storage.lock.withLock { storage.keys[provider] }
    }

    func saveAPIKey(_ key: String, for provider: ModelProvider) throws {
        storage.lock.withLock { storage.keys[provider] = key }
    }

    func deleteAPIKey(for provider: ModelProvider) throws {
        storage.lock.withLock { storage.keys[provider] = nil }
    }
}
