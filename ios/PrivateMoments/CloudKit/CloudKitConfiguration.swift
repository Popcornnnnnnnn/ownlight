import Foundation

struct CloudKitConfiguration: Equatable {
    private static let containerInfoKey = "PrivateMomentsCloudKitContainerIdentifier"
    private static let sourceBuildPlaceholderContainers: Set<String> = [
        "iCloud.dev.privatemoments.app",
        "iCloud.dev.privatemoments.app.uat"
    ]

    let containerIdentifier: String?

    var isConfigured: Bool {
        containerIdentifier != nil
    }

    init(infoDictionary: [String: Any]? = Bundle.main.infoDictionary) {
        guard let rawValue = infoDictionary?[Self.containerInfoKey] as? String else {
            containerIdentifier = nil
            return
        }

        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("iCloud."),
              !trimmed.contains("$("),
              !Self.sourceBuildPlaceholderContainers.contains(trimmed) else {
            containerIdentifier = nil
            return
        }

        containerIdentifier = trimmed
    }
}
