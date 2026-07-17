import Foundation

struct AppStoreSupportLinks {
    let privacyPolicyURL: URL?
    let supportURL: URL?

    init(
        infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:],
        language: AppResolvedLanguage = AppLanguageMode.system.resolvedLanguage
    ) {
        let fallbackRoot = Self.publicHTTPSURL(from: infoDictionary["PrivateMomentsFallbackServerURL"])

        privacyPolicyURL = Self.localizedPrivacyPolicyURL(from: infoDictionary, language: language)
            ?? Self.publicHTTPSURL(from: infoDictionary["PrivateMomentsPrivacyPolicyURL"])
            ?? fallbackRoot?.appending(path: "privacy")
        supportURL = Self.publicHTTPSURL(from: infoDictionary["PrivateMomentsSupportURL"])
            ?? fallbackRoot?.appending(path: "support")
    }

    static var current: AppStoreSupportLinks {
        AppStoreSupportLinks()
    }

    private static func localizedPrivacyPolicyURL(from infoDictionary: [String: Any], language: AppResolvedLanguage) -> URL? {
        switch language {
        case .english:
            return publicHTTPSURL(from: infoDictionary["PrivateMomentsPrivacyPolicyURLEnglish"])
        case .simplifiedChinese:
            return publicHTTPSURL(from: infoDictionary["PrivateMomentsPrivacyPolicyURLSimplifiedChinese"])
        }
    }

    private static func publicHTTPSURL(from value: Any?) -> URL? {
        guard let rawValue = value as? String else {
            return nil
        }

        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty,
              let url = URL(string: trimmedValue),
              url.scheme?.lowercased() == "https",
              url.host?.isEmpty == false else {
            return nil
        }

        return url
    }
}
