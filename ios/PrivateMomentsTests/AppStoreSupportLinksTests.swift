import XCTest
@testable import PrivateMoments

final class AppStoreSupportLinksTests: XCTestCase {
    func testUsesExplicitPrivacyAndSupportURLs() {
        let links = AppStoreSupportLinks(
            infoDictionary: [
                "PrivateMomentsPrivacyPolicyURL": "https://example.com/privacy",
                "PrivateMomentsPrivacyPolicyURLSimplifiedChinese": "https://example.com/privacy/zh-Hans",
                "PrivateMomentsPrivacyPolicyURLEnglish": "https://example.com/privacy/en",
                "PrivateMomentsSupportURL": "https://example.com/support",
                "PrivateMomentsFallbackServerURL": "https://moments.example.com"
            ],
            language: .english
        )

        XCTAssertEqual(links.privacyPolicyURL?.absoluteString, "https://example.com/privacy/en")
        XCTAssertEqual(links.supportURL?.absoluteString, "https://example.com/support")
    }

    func testUsesSimplifiedChinesePrivacyURLForSimplifiedChineseLanguage() {
        let links = AppStoreSupportLinks(
            infoDictionary: [
                "PrivateMomentsPrivacyPolicyURL": "https://example.com/privacy",
                "PrivateMomentsPrivacyPolicyURLSimplifiedChinese": "https://example.com/privacy/zh-Hans",
                "PrivateMomentsPrivacyPolicyURLEnglish": "https://example.com/privacy/en"
            ],
            language: .simplifiedChinese
        )

        XCTAssertEqual(links.privacyPolicyURL?.absoluteString, "https://example.com/privacy/zh-Hans")
    }

    func testFallsBackToServerRootPagesWhenExplicitURLsAreMissing() {
        let links = AppStoreSupportLinks(
            infoDictionary: [
                "PrivateMomentsFallbackServerURL": "https://moments.example.com/"
            ]
        )

        XCTAssertEqual(links.privacyPolicyURL?.absoluteString, "https://moments.example.com/privacy")
        XCTAssertEqual(links.supportURL?.absoluteString, "https://moments.example.com/support")
    }

    func testRejectsNonHTTPSPublicLinks() {
        let links = AppStoreSupportLinks(
            infoDictionary: [
                "PrivateMomentsPrivacyPolicyURL": "http://example.com/privacy",
                "PrivateMomentsSupportURL": "ftp://example.com/support",
                "PrivateMomentsFallbackServerURL": "http://moments.example.com"
            ]
        )

        XCTAssertNil(links.privacyPolicyURL)
        XCTAssertNil(links.supportURL)
    }
}
