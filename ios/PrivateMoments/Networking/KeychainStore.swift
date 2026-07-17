import Foundation
import Security

enum KeychainStore {
    private static let service = "PrivateMoments"
    private static let account = "deviceToken"
    private static let simulatorFallbackKey = "simulator.deviceToken"
    private static let missingEntitlementStatus: OSStatus = -34018
    static let localTranscriptionGatewayTokenAccount = "localTranscriptionGateway.bearerToken"
    static let transcriptionProviderAPIKeyAccount = localTranscriptionGatewayTokenAccount

    static func deviceToken() throws -> String? {
        try string(account: account, simulatorFallbackKey: simulatorFallbackKey)
    }

    static func saveDeviceToken(_ token: String) throws {
        try saveString(token, account: account, simulatorFallbackKey: simulatorFallbackKey)
    }

    static func clearDeviceToken() throws {
        try clearString(account: account, simulatorFallbackKey: simulatorFallbackKey)
    }

    static func aiProviderAPIKeyAccount(profileId: String) -> String {
        "aiProvider.apiKey.\(profileId)"
    }

    static func aiProviderAPIKey(profileId: String) throws -> String? {
        let account = aiProviderAPIKeyAccount(profileId: profileId)
        return try string(account: account, simulatorFallbackKey: "simulator.\(account)")
    }

    static func saveAIProviderAPIKey(_ apiKey: String, profileId: String) throws {
        let account = aiProviderAPIKeyAccount(profileId: profileId)
        try saveString(apiKey, account: account, simulatorFallbackKey: "simulator.\(account)")
    }

    static func clearAIProviderAPIKey(profileId: String) throws {
        let account = aiProviderAPIKeyAccount(profileId: profileId)
        try clearString(account: account, simulatorFallbackKey: "simulator.\(account)")
    }

    static func localTranscriptionGatewayToken() throws -> String? {
        try string(
            account: localTranscriptionGatewayTokenAccount,
            simulatorFallbackKey: "simulator.\(localTranscriptionGatewayTokenAccount)"
        )
    }

    static func saveLocalTranscriptionGatewayToken(_ token: String) throws {
        try saveString(
            token,
            account: localTranscriptionGatewayTokenAccount,
            simulatorFallbackKey: "simulator.\(localTranscriptionGatewayTokenAccount)"
        )
    }

    static func clearLocalTranscriptionGatewayToken() throws {
        try clearString(
            account: localTranscriptionGatewayTokenAccount,
            simulatorFallbackKey: "simulator.\(localTranscriptionGatewayTokenAccount)"
        )
    }

    static func transcriptionProviderAPIKey() throws -> String? {
        try localTranscriptionGatewayToken()
    }

    static func saveTranscriptionProviderAPIKey(_ apiKey: String) throws {
        try saveLocalTranscriptionGatewayToken(apiKey)
    }

    static func clearTranscriptionProviderAPIKey() throws {
        try clearLocalTranscriptionGatewayToken()
    }

    private static func string(account: String, simulatorFallbackKey: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            if shouldUseSimulatorFallback(for: status) {
                return UserDefaults.standard.string(forKey: simulatorFallbackKey)
            }

            throw KeychainError.status(status)
        }

        guard let data = result as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    private static func saveString(
        _ value: String,
        account: String,
        simulatorFallbackKey: String
    ) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }

        if shouldUseSimulatorFallback(for: updateStatus) {
            UserDefaults.standard.set(value, forKey: simulatorFallbackKey)
            return
        }

        guard updateStatus == errSecItemNotFound else {
            throw KeychainError.status(updateStatus)
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            if shouldUseSimulatorFallback(for: addStatus) {
                UserDefaults.standard.set(value, forKey: simulatorFallbackKey)
                return
            }

            throw KeychainError.status(addStatus)
        }
    }

    private static func clearString(account: String, simulatorFallbackKey: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        UserDefaults.standard.removeObject(forKey: simulatorFallbackKey)

        if status != errSecSuccess && status != errSecItemNotFound {
            if shouldUseSimulatorFallback(for: status) {
                return
            }

            throw KeychainError.status(status)
        }
    }

    private static func shouldUseSimulatorFallback(for status: OSStatus) -> Bool {
        #if targetEnvironment(simulator)
        return status == missingEntitlementStatus
        #else
        return false
        #endif
    }
}

enum KeychainError: LocalizedError {
    case status(OSStatus)

    var errorDescription: String? {
        switch self {
        case .status(let status):
            return "Keychain error \(status)"
        }
    }
}
