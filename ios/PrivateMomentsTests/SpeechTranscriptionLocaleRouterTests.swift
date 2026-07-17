import XCTest
@testable import PrivateMoments

final class SpeechTranscriptionLocaleRouterTests: XCTestCase {
    private var savedPreferredLocaleIdentifier: String?
    private var savedAILanguageMode: AILanguageMode!
    private var savedAppLanguageMode: AppLanguageMode!

    override func setUp() {
        super.setUp()
        savedPreferredLocaleIdentifier = AppSettings.preferredSpeechTranscriptionLocaleIdentifier
        savedAILanguageMode = AppSettings.aiLanguageMode
        savedAppLanguageMode = AppSettings.appLanguageMode
        AppSettings.preferredSpeechTranscriptionLocaleIdentifier = nil
    }

    override func tearDown() {
        AppSettings.preferredSpeechTranscriptionLocaleIdentifier = savedPreferredLocaleIdentifier
        AppSettings.aiLanguageMode = savedAILanguageMode
        AppSettings.appLanguageMode = savedAppLanguageMode
        savedAILanguageMode = nil
        savedAppLanguageMode = nil
        super.tearDown()
    }

    func testSuccessfulFallbackLocaleIsRememberedAsNextDefault() async throws {
        let audioURL = URL(fileURLWithPath: "/tmp/private-moments-test.m4a")
        var attemptedLocaleIdentifiers: [String] = []

        let transcript = try await SpeechTranscriptionLocaleRouter.transcribe(
            url: audioURL,
            aiLanguageMode: .chinese,
            appLanguageMode: .english,
            currentLocale: Locale(identifier: "en-US")
        ) { _, locale in
            attemptedLocaleIdentifiers.append(locale.identifier)
            if locale.identifier == "zh-CN" {
                throw LocalSpeechTranscriptionError.emptyTranscript
            }
            return "hello"
        }

        XCTAssertEqual(transcript, "hello")
        XCTAssertEqual(attemptedLocaleIdentifiers, ["zh-CN", "en-US"])
        XCTAssertEqual(AppSettings.preferredSpeechTranscriptionLocaleIdentifier, "en-US")

        attemptedLocaleIdentifiers = []
        _ = try await SpeechTranscriptionLocaleRouter.transcribe(
            url: audioURL,
            aiLanguageMode: .chinese,
            appLanguageMode: .english,
            currentLocale: Locale(identifier: "en-US")
        ) { _, locale in
            attemptedLocaleIdentifiers.append(locale.identifier)
            return "hello again"
        }

        XCTAssertEqual(attemptedLocaleIdentifiers, ["en-US"])
    }

    func testAutoLanguageUsesAppLanguageBeforeSystemLocale() {
        let candidates = SpeechTranscriptionLocaleRouter.candidateLocaleIdentifiers(
            aiLanguageMode: .auto,
            appLanguageMode: .simplifiedChinese,
            currentLocale: Locale(identifier: "en-US")
        )

        XCTAssertEqual(candidates.prefix(2), ["zh-CN", "en-US"])
    }
}
