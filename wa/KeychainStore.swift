import Foundation
import Security

enum KeychainStoreError: LocalizedError {
    case unexpectedData
    case unhandledStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unexpectedData:
            return "키체인에 저장된 데이터를 읽을 수 없습니다."
        case .unhandledStatus(let status):
            return "키체인 작업에 실패했습니다. (\(status))"
        }
    }
}

enum KeychainStore {
    private static let geminiService = "wa.gemini.api-key"
    private static let geminiAccount = "primary"

    static func saveGeminiAPIKey(_ apiKey: String) throws {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try deleteGeminiAPIKey()
            return
        }
        guard let data = trimmed.data(using: .utf8) else {
            throw KeychainStoreError.unexpectedData
        }

        let baseQuery = keyQuery()
        let status = SecItemCopyMatching(baseQuery as CFDictionary, nil)
        if status == errSecSuccess {
            let attributes: [String: Any] = [
                kSecValueData as String: data
            ]
            let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw KeychainStoreError.unhandledStatus(updateStatus)
            }
            return
        }

        if status == errSecItemNotFound {
            var addQuery = baseQuery
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainStoreError.unhandledStatus(addStatus)
            }
            return
        }

        throw KeychainStoreError.unhandledStatus(status)
    }

    static func loadGeminiAPIKey() throws -> String? {
        var query = keyQuery()
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainStoreError.unhandledStatus(status)
        }
        guard let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw KeychainStoreError.unexpectedData
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func deleteGeminiAPIKey() throws {
        let status = SecItemDelete(keyQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainStoreError.unhandledStatus(status)
        }
    }

    private static func keyQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: geminiService,
            kSecAttrAccount as String: geminiAccount
        ]
    }
}
