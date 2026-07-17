import Foundation

struct TranscriptionProviderConnectionWorkflow {
    var client: LocalTranscriptionGatewayClient = LocalTranscriptionGatewayClient()

    func testAndSave(
        mode: TranscriptionProviderMode,
        settings: LocalTranscriptionGatewaySettings,
        apiKey: String
    ) async throws -> TranscriptionProviderConnectionInfo {
        let info: TranscriptionProviderConnectionInfo
        switch mode.normalizedForSettingsUI {
        case .customOpenAICompatible:
            info = try await client.testOpenAICompatibleConnection(
                urlString: settings.normalizedURLString,
                token: apiKey
            )
        case .iPhoneOnDevice:
            info = TranscriptionProviderConnectionInfo(model: nil)
        case .localGateway:
            info = try await client.testOpenAICompatibleConnection(
                urlString: settings.normalizedURLString,
                token: apiKey
            )
        }

        try save(settings: settings, apiKey: apiKey)
        return info
    }

    func save(settings: LocalTranscriptionGatewaySettings, apiKey: String) throws {
        AppSettings.localTranscriptionGatewaySettings = settings
        if apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try KeychainStore.clearTranscriptionProviderAPIKey()
        } else {
            try KeychainStore.saveTranscriptionProviderAPIKey(apiKey)
        }
    }
}
