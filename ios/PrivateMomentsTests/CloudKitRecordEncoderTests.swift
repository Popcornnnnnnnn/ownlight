import CloudKit
import XCTest
@testable import PrivateMoments

final class CloudKitRecordEncoderTests: XCTestCase {
    func testBuildsRecordIdentityFromPayload() throws {
        let payload = CloudKitRecordPayload(
            entityType: .moment,
            entityId: "post 1/unsafe",
            zoneName: "PrivateMomentsV1",
            fields: ["text": .string("Hello")]
        )

        let record = CloudKitRecordEncoder.record(from: payload)

        XCTAssertEqual(record.recordType, "PMMoment")
        XCTAssertEqual(record.recordID.recordName, "pm.moment.post_1_unsafe")
        XCTAssertEqual(record.recordID.zoneID.zoneName, "PrivateMomentsV1")
        XCTAssertEqual(record.recordID.zoneID.ownerName, CKCurrentUserDefaultName)
    }

    func testEncodesSupportedPayloadFieldTypes() throws {
        let occurredAt = Date(timeIntervalSince1970: 5_100)
        let payload = CloudKitRecordPayload(
            entityType: .checkInEntry,
            entityId: "entry-1",
            fields: [
                "note": .string("Workout"),
                "sortOrder": .int(2),
                "durationSeconds": .double(42.5),
                "showInTimeline": .bool(true),
                "occurredAt": .date(occurredAt),
                "activeWeekdays": .stringList(["1", "3", "5"])
            ]
        )

        let record = CloudKitRecordEncoder.record(from: payload)

        XCTAssertEqual(record["note"] as? String, "Workout")
        XCTAssertEqual((record["sortOrder"] as? NSNumber)?.intValue, 2)
        XCTAssertEqual((record["durationSeconds"] as? NSNumber)?.doubleValue, 42.5)
        XCTAssertEqual((record["showInTimeline"] as? NSNumber)?.boolValue, true)
        XCTAssertEqual(record["occurredAt"] as? Date, occurredAt)
        XCTAssertEqual(record["activeWeekdays"] as? [String], ["1", "3", "5"])
    }

    func testRemovesEmptyStringListFieldBecauseCloudKitRejectsEmptyListInitialization() throws {
        let payload = CloudKitRecordPayload(
            entityType: .tag,
            entityId: "tag-1",
            fields: ["aliases": .stringList([])]
        )

        let record = CloudKitRecordEncoder.record(from: payload)

        XCTAssertNil(record["aliases"])
    }

    func testClearsExistingStringListWhenPayloadListIsEmpty() throws {
        let existing = CloudKitRecordEncoder.record(from: CloudKitRecordPayload(
            entityType: .tag,
            entityId: "tag-1",
            fields: ["aliases": .stringList(["old"])]
        ))
        let payload = CloudKitRecordPayload(
            entityType: .tag,
            entityId: "tag-1",
            fields: ["aliases": .stringList([])]
        )

        let updated = CloudKitRecordEncoder.record(from: payload, updating: existing)

        XCTAssertNil(updated["aliases"])
    }

    func testEncodesAssetPayloadFieldsAsCloudKitAssets() throws {
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("jpg")
        try Data("image".utf8).write(to: temporaryURL)
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        let metadataPayload = CloudKitRecordPayload(
            entityType: .media,
            entityId: "media-1",
            fields: ["postId": .string("post-1")]
        )
        let assetPayload = CloudKitAssetRecordPayload(
            metadataPayload: metadataPayload,
            assetFields: [CloudKitAssetField(fieldName: "compressedAsset", fileURL: temporaryURL)]
        )

        let record = CloudKitRecordEncoder.record(from: assetPayload)

        XCTAssertEqual(record["postId"] as? String, "post-1")
        let asset = try XCTUnwrap(record["compressedAsset"] as? CKAsset)
        XCTAssertEqual(asset.fileURL, temporaryURL)
    }
}
