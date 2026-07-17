import CloudKit
import Foundation

struct CloudKitSyncUserMessage: Equatable {
    var titleKey: String
    var bodyKey: String

    func title(language: AppResolvedLanguage) -> String {
        L10n.t(titleKey, language)
    }

    func body(language: AppResolvedLanguage) -> String {
        L10n.t(bodyKey, language)
    }

    static func message(for error: Error) -> CloudKitSyncUserMessage {
        if let coordinatorError = error as? CloudKitSyncCoordinatorError {
            switch coordinatorError {
            case .nonEmptyLocalLibraryWithExistingCloudArchive:
                return CloudKitSyncUserMessage(
                    titleKey: "iCloud Sync paused to protect data",
                    bodyKey: coordinatorError.errorDescription ?? genericBodyKey
                )
            case .iCloudSyncDisabled:
                return CloudKitSyncUserMessage(
                    titleKey: "iCloud Sync is off",
                    bodyKey: coordinatorError.errorDescription ?? genericBodyKey
                )
            case .notConfigured:
                return CloudKitSyncUserMessage(
                    titleKey: "iCloud Sync unavailable",
                    bodyKey: coordinatorError.errorDescription ?? genericBodyKey
                )
            }
        }

        if let code = firstCloudKitCode(in: error) {
            switch code {
            case .notAuthenticated:
                return CloudKitSyncUserMessage(
                    titleKey: "Sign in to iCloud",
                    bodyKey: "Sign in to iCloud in iOS Settings, then return to Ownlight and try Sync Now again."
                )
            case .networkUnavailable, .networkFailure:
                return CloudKitSyncUserMessage(
                    titleKey: "iCloud Sync is offline",
                    bodyKey: "Check your connection. Ownlight will keep working locally and will retry later."
                )
            case .quotaExceeded, .limitExceeded:
                return CloudKitSyncUserMessage(
                    titleKey: "iCloud storage is full",
                    bodyKey: "Free up iCloud storage or change your iCloud plan, then try Sync Now again. Your local data remains on this device."
                )
            case .serviceUnavailable,
                 .requestRateLimited,
                 .zoneBusy,
                 .accountTemporarilyUnavailable,
                 .serverResponseLost,
                 .serverRejectedRequest,
                 .internalError:
                return CloudKitSyncUserMessage(
                    titleKey: "iCloud is temporarily unavailable",
                    bodyKey: "Your local data remains on this device. Try again later; Ownlight will retry automatically when iCloud recovers."
                )
            case .badContainer, .missingEntitlement, .badDatabase:
                return CloudKitSyncUserMessage(
                    titleKey: "iCloud Sync unavailable",
                    bodyKey: "This build cannot access the configured iCloud container. Your local data remains on this device."
                )
            case .permissionFailure, .managedAccountRestricted:
                return CloudKitSyncUserMessage(
                    titleKey: "iCloud Sync is restricted",
                    bodyKey: "iCloud is restricted for this Apple Account or device. Ownlight remains available locally."
                )
            default:
                break
            }
        }

        return CloudKitSyncUserMessage(titleKey: genericTitleKey, bodyKey: genericBodyKey)
    }

    private static let genericTitleKey = "iCloud Sync did not finish"
    private static let genericBodyKey = "Ownlight remains available locally. Try again later, or use Sync Now after checking your connection."

    private static func firstCloudKitCode(in error: Error) -> CKError.Code? {
        if let operationError = error as? CloudKitOperationError,
           let code = firstCloudKitCode(in: operationError.underlying) {
            return code
        }

        let nsError = error as NSError
        if nsError.domain == CKError.errorDomain,
           let code = CKError.Code(rawValue: nsError.code) {
            return code
        }

        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            return firstCloudKitCode(in: underlying)
        }

        return nil
    }
}
