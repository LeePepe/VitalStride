import Foundation
import Security
import OSLog

private let logger = Logger(subsystem: "com.vitalstride.aiservice", category: "Keychain")

public enum KeychainError: Error, Sendable, LocalizedError {
    case saveFailed(status: OSStatus)
    case loadFailed(status: OSStatus)
    case deleteFailed(status: OSStatus)
    case itemNotFound
    case unexpectedData

    public var errorDescription: String? {
        switch self {
        case let .saveFailed(status):
            String(localized: "Failed to save to Keychain (status: \(status)).")
        case let .loadFailed(status):
            String(localized: "Failed to load from Keychain (status: \(status)).")
        case let .deleteFailed(status):
            String(localized: "Failed to delete from Keychain (status: \(status)).")
        case .itemNotFound:
            String(localized: "Keychain item not found.")
        case .unexpectedData:
            String(localized: "Unexpected Keychain data format.")
        }
    }
}

public struct KeychainHelper: Sendable {
    public static let defaultServicePrefix = "com.vitalstride.aiservice"

    public init() {}

    public func save(key: String, service: String) throws {
        let data = Data(key.utf8)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: service,
        ]

        let deleteStatus = SecItemDelete(query as CFDictionary)
        if deleteStatus != errSecSuccess && deleteStatus != errSecItemNotFound {
            logger.error("Keychain pre-delete failed: status=\(deleteStatus)")
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            logger.error("Keychain save failed: status=\(status)")
            throw KeychainError.saveFailed(status: status)
        }
        logger.info("Keychain item saved for service=\(service)")
    }

    public func load(service: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status != errSecItemNotFound else {
            throw KeychainError.itemNotFound
        }
        guard status == errSecSuccess else {
            logger.error("Keychain load failed: status=\(status)")
            throw KeychainError.loadFailed(status: status)
        }
        guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            logger.error("Keychain data format unexpected for service=\(service)")
            throw KeychainError.unexpectedData
        }
        return value
    }

    public func delete(service: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: service,
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            logger.error("Keychain delete failed: status=\(status)")
            throw KeychainError.deleteFailed(status: status)
        }
        logger.info("Keychain item deleted for service=\(service)")
    }
}
