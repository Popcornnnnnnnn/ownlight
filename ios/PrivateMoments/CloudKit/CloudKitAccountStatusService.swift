import CloudKit
import Foundation

protocol CloudKitAccountStatusChecking: AnyObject {
    func accountStatus() async throws -> CKAccountStatus
}

final class DefaultCloudKitAccountStatusChecker: CloudKitAccountStatusChecking {
    private let container: CKContainer

    init(containerIdentifier: String) {
        container = CKContainer(identifier: containerIdentifier)
    }

    func accountStatus() async throws -> CKAccountStatus {
        try await container.accountStatus()
    }
}

final class CloudKitAccountStatusService {
    private let configuration: CloudKitConfiguration
    private let checker: CloudKitAccountStatusChecking?
    private let now: () -> Date

    init(
        configuration: CloudKitConfiguration = CloudKitConfiguration(),
        checker: CloudKitAccountStatusChecking? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.configuration = configuration
        if let checker {
            self.checker = checker
        } else if let containerIdentifier = configuration.containerIdentifier {
            self.checker = DefaultCloudKitAccountStatusChecker(containerIdentifier: containerIdentifier)
        } else {
            self.checker = nil
        }
        self.now = now
    }

    func loadAccountStatus() async -> CloudKitAccountStatusSnapshot {
        guard configuration.isConfigured, let checker else {
            return .notConfigured
        }

        do {
            let status = try await checker.accountStatus()
            return CloudKitAccountStatusSnapshot(
                configuration: configuration,
                accountStatus: status,
                checkedAt: now()
            )
        } catch {
            return CloudKitAccountStatusSnapshot(
                configuration: configuration,
                state: .couldNotDetermine,
                checkedAt: now()
            )
        }
    }
}
