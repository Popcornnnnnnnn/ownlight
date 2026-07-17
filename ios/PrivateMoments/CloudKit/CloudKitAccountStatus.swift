import CloudKit
import Foundation

enum PrivateMomentsCloudKitAccountState: Equatable {
    case notConfigured
    case available
    case noAccount
    case restricted
    case temporarilyUnavailable
    case couldNotDetermine

    init(accountStatus: CKAccountStatus) {
        switch accountStatus {
        case .available:
            self = .available
        case .noAccount:
            self = .noAccount
        case .restricted:
            self = .restricted
        case .couldNotDetermine:
            self = .couldNotDetermine
        case .temporarilyUnavailable:
            self = .temporarilyUnavailable
        @unknown default:
            self = .couldNotDetermine
        }
    }
}

struct CloudKitAccountStatusSnapshot: Equatable {
    static let notConfigured = CloudKitAccountStatusSnapshot(
        configuration: CloudKitConfiguration(infoDictionary: [:]),
        state: .notConfigured,
        checkedAt: nil
    )

    let configuration: CloudKitConfiguration
    let state: PrivateMomentsCloudKitAccountState
    let checkedAt: Date?

    var containerIdentifier: String? {
        configuration.containerIdentifier
    }

    var canCheckCloudKit: Bool {
        configuration.isConfigured
    }

    var canEnableSync: Bool {
        state == .available
    }

    init(
        configuration: CloudKitConfiguration,
        accountStatus: CKAccountStatus,
        checkedAt: Date
    ) {
        self.configuration = configuration
        state = configuration.isConfigured ? PrivateMomentsCloudKitAccountState(accountStatus: accountStatus) : .notConfigured
        self.checkedAt = configuration.isConfigured ? checkedAt : nil
    }

    init(
        configuration: CloudKitConfiguration,
        state: PrivateMomentsCloudKitAccountState,
        checkedAt: Date?
    ) {
        self.configuration = configuration
        self.state = configuration.isConfigured ? state : .notConfigured
        self.checkedAt = configuration.isConfigured ? checkedAt : nil
    }
}
