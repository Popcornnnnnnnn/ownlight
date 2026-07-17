import Foundation

enum StoreError: LocalizedError {
    case notReady
    case notAuthenticated
    case localOnlyModeEnabled
    case invalidServerChange(String)
    case insecureServerURL
    case commentTargetUnavailable

    var errorDescription: String? {
        switch self {
        case .notReady:
            return "Local database is not ready"
        case .notAuthenticated:
            return "Log in to the configured sync endpoint first"
        case .localOnlyModeEnabled:
            return "Automatic Sync is off. Turn it on or use Sync Now before requesting optional replication features."
        case .invalidServerChange(let message):
            return "Invalid server change: \(message)"
        case .insecureServerURL:
            return "Use HTTPS for remote servers. Plain HTTP is allowed only for localhost."
        case .commentTargetUnavailable:
            return "This moment is no longer available."
        }
    }
}
