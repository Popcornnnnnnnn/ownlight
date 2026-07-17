import CloudKit
import XCTest
@testable import PrivateMoments

final class CloudKitSyncUserMessageTests: XCTestCase {
    func testNetworkFailureUsesHumanReadableRetryMessage() {
        let error = CloudKitOperationError(
            operation: "Save CloudKit record",
            recordType: "PMMoment",
            recordName: "pm.moment.test",
            zoneName: CloudKitSyncDefaults.zoneName,
            fieldNames: ["text"],
            underlying: NSError(
                domain: CKError.errorDomain,
                code: CKError.Code.networkUnavailable.rawValue
            )
        )

        let message = CloudKitSyncUserMessage.message(for: error)

        XCTAssertEqual(message.titleKey, "iCloud Sync is offline")
        XCTAssertEqual(
            message.bodyKey,
            "Check your connection. Moments will keep working locally and will retry later."
        )
        XCTAssertFalse(message.bodyKey.contains("PMMoment"))
    }

    func testQuotaExceededPointsToICloudStorageWithoutRawDiagnostics() {
        let error = NSError(
            domain: CKError.errorDomain,
            code: CKError.Code.quotaExceeded.rawValue
        )

        let message = CloudKitSyncUserMessage.message(for: error)

        XCTAssertEqual(message.titleKey, "iCloud storage is full")
        XCTAssertEqual(
            message.bodyKey,
            "Free up iCloud storage or change your iCloud plan, then try Sync Now again. Local Moments remain on this device."
        )
    }

    func testNonEmptyDeviceConflictExplainsDataProtection() {
        let message = CloudKitSyncUserMessage.message(
            for: CloudKitSyncCoordinatorError.nonEmptyLocalLibraryWithExistingCloudArchive
        )

        XCTAssertEqual(message.titleKey, "iCloud Sync paused to protect data")
        XCTAssertEqual(
            message.bodyKey,
            "iCloud already has a Moments library, and this device also has local Moments data. To avoid silently merging or overwriting private data, export or clear this device before turning on iCloud Sync."
        )
    }
}
