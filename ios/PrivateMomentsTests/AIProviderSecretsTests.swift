import XCTest
@testable import PrivateMoments

final class AIProviderSecretsTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "transcriptionProviderMode")
        super.tearDown()
    }

    func testProfileMetadataDoesNotContainAPIKey() throws {
        let profile = AIProviderProfile(
            id: "custom",
            kind: .customOpenAICompatible,
            displayName: "Local Gateway",
            baseURLString: "http://127.0.0.1:11434/v1",
            model: "qwen3",
            isEnabled: true,
            sortOrder: 0
        )
        let data = try JSONEncoder().encode(profile)
        let json = String(decoding: data, as: UTF8.self)

        XCTAssertFalse(json.localizedCaseInsensitiveContains("apiKey"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("secret"))
    }

    func testSecretAccountIsDerivedFromProfileId() {
        XCTAssertEqual(
            KeychainStore.aiProviderAPIKeyAccount(profileId: "abc-123"),
            "aiProvider.apiKey.abc-123"
        )
    }

    func testLocalTranscriptionGatewayTokenUsesDedicatedKeychainAccount() throws {
        try? KeychainStore.clearLocalTranscriptionGatewayToken()

        try KeychainStore.saveLocalTranscriptionGatewayToken("gateway-secret")
        XCTAssertEqual(try KeychainStore.localTranscriptionGatewayToken(), "gateway-secret")
        XCTAssertEqual(
            KeychainStore.localTranscriptionGatewayTokenAccount,
            "localTranscriptionGateway.bearerToken"
        )
        XCTAssertEqual(
            KeychainStore.transcriptionProviderAPIKeyAccount,
            KeychainStore.localTranscriptionGatewayTokenAccount
        )

        try KeychainStore.clearLocalTranscriptionGatewayToken()
        XCTAssertNil(try KeychainStore.localTranscriptionGatewayToken())
    }

    func testLocalTranscriptionGatewayMetadataDoesNotContainBearerToken() throws {
        let settings = LocalTranscriptionGatewaySettings(
            urlString: "https://gateway.example",
            model: "mlx-community/whisper-large-v3-turbo"
        )
        let data = try JSONEncoder().encode(settings)
        let json = String(decoding: data, as: UTF8.self)

        XCTAssertTrue(json.contains("gateway.example"))
        XCTAssertTrue(json.contains("whisper-large-v3-turbo"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("token"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("secret"))
    }

    func testLegacyLocalGatewayModeMigratesToCustomOpenAICompatible() {
        UserDefaults.standard.set("local_gateway", forKey: "transcriptionProviderMode")

        XCTAssertEqual(AppSettings.transcriptionProviderMode, .customOpenAICompatible)
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: "transcriptionProviderMode"),
            "custom_openai_compatible"
        )
    }

    func testTranscriptionProviderPickerHidesLegacyLocalGateway() {
        XCTAssertEqual(
            TranscriptionProviderMode.allCases,
            [.iPhoneOnDevice, .customOpenAICompatible]
        )
    }
}
