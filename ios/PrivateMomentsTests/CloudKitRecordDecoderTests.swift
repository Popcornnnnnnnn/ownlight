import CloudKit
import XCTest
@testable import PrivateMoments

final class CloudKitRecordDecoderTests: XCTestCase {
    func testDecodesSupportedRecordIntoPayload() throws {
        let occurredAt = Date(timeIntervalSince1970: 7_000)
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

        let decoded = try CloudKitRecordDecoder.payload(from: record)

        XCTAssertEqual(decoded, payload)
    }

    func testRejectsUnsupportedRecordType() throws {
        let recordID = CKRecord.ID(
            recordName: "pm.moment.post-1",
            zoneID: CKRecordZone.ID(zoneName: CloudKitSyncDefaults.zoneName, ownerName: CKCurrentUserDefaultName)
        )
        let record = CKRecord(recordType: "PMUnknown", recordID: recordID)

        XCTAssertThrowsError(try CloudKitRecordDecoder.payload(from: record)) { error in
            XCTAssertEqual(error as? CloudKitRecordDecoderError, .unsupportedRecordType("PMUnknown"))
        }
    }

    func testRejectsUnexpectedRecordNamePrefix() throws {
        let recordID = CKRecord.ID(
            recordName: "post-1",
            zoneID: CKRecordZone.ID(zoneName: CloudKitSyncDefaults.zoneName, ownerName: CKCurrentUserDefaultName)
        )
        let record = CKRecord(recordType: "PMMoment", recordID: recordID)

        XCTAssertThrowsError(try CloudKitRecordDecoder.payload(from: record)) { error in
            XCTAssertEqual(error as? CloudKitRecordDecoderError, .invalidRecordName("post-1"))
        }
    }

    func testSkipsAssetFieldsWhenDecodingMetadataPayload() throws {
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("jpg")
        try Data("image".utf8).write(to: temporaryURL)
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        let recordID = CKRecord.ID(
            recordName: "pm.media.media-1",
            zoneID: CKRecordZone.ID(zoneName: CloudKitSyncDefaults.zoneName, ownerName: CKCurrentUserDefaultName)
        )
        let record = CKRecord(recordType: "PMMedia", recordID: recordID)
        record["postId"] = "post-1" as CKRecordValue
        record["compressedAsset"] = CKAsset(fileURL: temporaryURL)

        let decoded = try CloudKitRecordDecoder.payload(from: record)

        XCTAssertEqual(decoded.entityType, .media)
        XCTAssertEqual(decoded.entityId, "media-1")
        XCTAssertEqual(decoded.fields, ["postId": .string("post-1")])
    }

    func testDecodesSanitizedEditDraftRecordNameToCanonicalEntityId() throws {
        let occurredAt = Date(timeIntervalSince1970: 8_200)
        let recordID = CKRecord.ID(
            recordName: "pm.draft.edit_post-1",
            zoneID: CKRecordZone.ID(zoneName: CloudKitSyncDefaults.zoneName, ownerName: CKCurrentUserDefaultName)
        )
        let record = CKRecord(recordType: "PMDraft", recordID: recordID)
        record["schemaVersion"] = CloudKitDraftSnapshot.schemaVersion as CKRecordValue
        record["draftKind"] = CloudKitDraftSnapshot.Kind.editMoment.rawValue as CKRecordValue
        record["postId"] = "post-1" as CKRecordValue
        record["text"] = "Remote edit" as CKRecordValue
        record["occurredAt"] = occurredAt as CKRecordValue
        record["updatedAt"] = occurredAt as CKRecordValue
        record["existingMediaIds"] = ["media-1"] as NSArray
        record["hasUnsupportedMediaDrafts"] = false as CKRecordValue

        let decoded = try CloudKitRecordDecoder.payload(from: record)

        XCTAssertEqual(decoded.entityType, .draft)
        XCTAssertEqual(decoded.entityId, "edit:post-1")
        XCTAssertEqual(decoded.recordName, "pm.draft.edit_post-1")
        XCTAssertEqual(decoded.fields["postId"], .string("post-1"))
    }
}
