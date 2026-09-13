import Foundation
import Security

public enum KeychainError: Error, LocalizedError {
    case unexpectedStatus(OSStatus)
    case dataCorrupted

    public var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
            return "Keychain error: \(message)"
        case .dataCorrupted:
            return "Keychain item could not be decoded as UTF-8 text."
        }
    }
}

/// Stores the API key as a generic password in the login keychain — never in
/// UserDefaults and never in a dotfile.
public enum APIKeyStore {
    public static let defaultService = "dev.locao.DeepSeekUsage"
    public static let defaultAccount = "DEEPSEEK_API_KEY"
    /// Convenience fallback so `--check` and CI can run without touching the keychain.
    public static let environmentVariable = "DEEPSEEK_API_KEY"

    public static func read(
        service: String = APIKeyStore.defaultService,
        account: String = APIKeyStore.defaultAccount
    ) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let text = String(data: data, encoding: .utf8) else {
                throw KeychainError.dataCorrupted
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    public static func save(
        _ secret: String,
        service: String = APIKeyStore.defaultService,
        account: String = APIKeyStore.defaultAccount
    ) throws {
        let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            try delete(service: service, account: account)
            return
        }

        let data = Data(trimmed.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )

        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var insert = query
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(insert as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(addStatus)
            }
        default:
            throw KeychainError.unexpectedStatus(updateStatus)
        }
    }

    public static func delete(
        service: String = APIKeyStore.defaultService,
        account: String = APIKeyStore.defaultAccount
    ) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Environment variable first (dev/CI), then the login keychain.
    public static func resolve() throws -> String? {
        if let raw = ProcessInfo.processInfo.environment[environmentVariable] {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return try read()
    }

    public static func hasStoredKey() -> Bool {
        guard let stored = try? read() else { return false }
        return !stored.isEmpty
    }
}
