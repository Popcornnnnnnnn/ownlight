import XCTest
@testable import PrivateMoments

final class AIProviderRoutingTests: XCTestCase {
    func testDefaultPresetsMatchFirstReleaseProviderSet() {
        let presets = AIProviderPreset.defaultTextAnalysisPresets

        XCTAssertEqual(
            presets.map(\.kind),
            [.openAI, .anthropic, .gemini, .deepSeek, .qwen, .kimi, .customOpenAICompatible]
        )
        XCTAssertTrue(presets.first { $0.kind == .openAI }?.supportsSpeechTranscription == true)
        XCTAssertTrue(presets.first { $0.kind == .gemini }?.supportsAudioInput == true)
        XCTAssertFalse(presets.first { $0.kind == .deepSeek }?.supportsSpeechTranscription ?? true)
    }

    func testRouterSkipsProviderDuringTransientCooldownAndReturnsAfterExpiry() {
        let now = Date(timeIntervalSince1970: 1_000)
        let profiles = [
            AIProviderProfile(
                id: "primary",
                kind: .openAI,
                displayName: "OpenAI",
                baseURLString: "https://api.openai.com/v1",
                model: "gpt-4o-mini",
                isEnabled: true,
                sortOrder: 0
            ),
            AIProviderProfile(
                id: "fallback",
                kind: .deepSeek,
                displayName: "DeepSeek",
                baseURLString: "https://api.deepseek.com",
                model: "deepseek-chat",
                isEnabled: true,
                sortOrder: 1
            )
        ]
        var state = AIProviderFallbackState()
        state.recordFailure(profileId: "primary", category: .transient, now: now)

        XCTAssertEqual(
            AIProviderRouter.selectProfile(profiles: profiles, fallbackState: state, now: now)?.id,
            "fallback"
        )
        XCTAssertEqual(
            AIProviderRouter.selectProfile(
                profiles: profiles,
                fallbackState: state,
                now: now.addingTimeInterval(121)
            )?.id,
            "primary"
        )
    }

    func testConfigurationFailuresNeedAttentionInsteadOfCooldownFallback() {
        let now = Date(timeIntervalSince1970: 1_000)
        var state = AIProviderFallbackState()
        state.recordFailure(profileId: "primary", category: .needsAttention, now: now)

        XCTAssertTrue(state.needsAttention(profileId: "primary"))
        XCTAssertFalse(state.isCoolingDown(profileId: "primary", now: now))
    }

    func testArtifactResponseFailuresDoNotDisableConfiguredProvider() {
        let now = Date(timeIntervalSince1970: 1_000)
        let profile = AIProviderProfile(
            id: "primary",
            kind: .deepSeek,
            displayName: "DeepSeek",
            baseURLString: "https://api.deepseek.com",
            model: "deepseek-chat",
            isEnabled: true,
            sortOrder: 0
        )
        var state = AIProviderFallbackState()

        state.recordFailure(
            profileId: profile.id,
            category: AITextAnalysisError.unsupportedResponse.failureCategory,
            now: now,
            message: AITextAnalysisError.unsupportedResponse.localizedDescription
        )

        XCTAssertFalse(state.needsAttention(profileId: profile.id))
        XCTAssertFalse(state.isCoolingDown(profileId: profile.id, now: now))
        XCTAssertEqual(
            AIProviderRouter.selectProfile(profiles: [profile], fallbackState: state, now: now)?.id,
            profile.id
        )
    }

    func testReadingFallbackStateClearsLegacyArtifactNeedsAttentionRecord() {
        defer {
            AppSettings.aiProviderFallbackState = AIProviderFallbackState()
        }

        let now = Date(timeIntervalSince1970: 1_000)
        let profile = AIProviderProfile(
            id: "primary",
            kind: .deepSeek,
            displayName: "DeepSeek",
            baseURLString: "https://api.deepseek.com",
            model: "deepseek-chat",
            isEnabled: true,
            sortOrder: 0
        )
        var legacyState = AIProviderFallbackState()
        legacyState.recordFailure(
            profileId: profile.id,
            category: .needsAttention,
            now: now,
            message: AITextAnalysisError.unsupportedResponse.localizedDescription
        )

        AppSettings.aiProviderFallbackState = legacyState
        let loadedState = AppSettings.aiProviderFallbackState

        XCTAssertFalse(loadedState.needsAttention(profileId: profile.id))
        XCTAssertFalse(loadedState.isCoolingDown(profileId: profile.id, now: now))
        XCTAssertEqual(
            AIProviderRouter.selectProfile(profiles: [profile], fallbackState: loadedState, now: now)?.id,
            profile.id
        )
    }
}
