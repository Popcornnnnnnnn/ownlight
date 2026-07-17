import CloudKit
import XCTest
@testable import PrivateMoments

final class CloudKitDefaultSyncTransportTests: XCTestCase {
    func testZonePreparerCreatesEachZoneOnlyOnce() async throws {
        let database = FakeCloudKitDatabaseWriter()
        let preparer = CloudKitZonePreparer(database: database)

        try await preparer.prepareZone(named: "PrivateMomentsV1")
        try await preparer.prepareZone(named: "PrivateMomentsV1")

        XCTAssertEqual(database.savedZoneNames, ["PrivateMomentsV1"])
    }

    func testZonePreparerTreatsExistingRemoteZoneAsPrepared() async throws {
        let database = FakeCloudKitDatabaseWriter()
        database.saveZoneError = NSError(
            domain: CKError.errorDomain,
            code: CKError.Code.serverRejectedRequest.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "Zone already exists"]
        )
        database.fetchedZoneNames.insert("PrivateMomentsV1")
        let preparer = CloudKitZonePreparer(database: database)

        try await preparer.prepareZone(named: "PrivateMomentsV1")
        try await preparer.prepareZone(named: "PrivateMomentsV1")

        XCTAssertEqual(database.events, [
            .saveZone("PrivateMomentsV1"),
            .fetchRecordZone("PrivateMomentsV1")
        ])
    }

    func testSavePreparesZoneThenSavesEncodedRecordAndReturnsSnapshotMetadata() async throws {
        let database = FakeCloudKitDatabaseWriter()
        let transport = CloudKitDefaultSyncTransport(database: database)
        let capturedAt = Date(timeIntervalSince1970: 2_000)
        let payload = CloudKitRecordPayload(
            entityType: .moment,
            entityId: "post-1",
            fields: [
                "text": .string("Hello CloudKit"),
                "favorite": .bool(true),
                "createdAt": .date(capturedAt),
                "topics": .stringList(["技术", "生活记录"])
            ]
        )

        let metadata = try await transport.save(payload)

        XCTAssertEqual(database.events, [
            .saveZone("PrivateMomentsV1"),
            .saveRecord("PMMoment", "pm.moment.post-1", "PrivateMomentsV1")
        ])
        XCTAssertNil(metadata.recordChangeTag)

        let json = try XCTUnwrap(metadata.lastKnownRecordJson?.data(using: .utf8))
        let snapshot = try XCTUnwrap(JSONSerialization.jsonObject(with: json) as? [String: Any])
        XCTAssertEqual(snapshot["recordType"] as? String, "PMMoment")
        XCTAssertEqual(snapshot["recordName"] as? String, "pm.moment.post-1")
        XCTAssertEqual(snapshot["zoneName"] as? String, "PrivateMomentsV1")
        let fields = try XCTUnwrap(snapshot["fields"] as? [String: Any])
        XCTAssertEqual(fields["text"] as? String, "Hello CloudKit")
        XCTAssertEqual(fields["favorite"] as? Bool, true)
        XCTAssertEqual(fields["topics"] as? [String], ["技术", "生活记录"])
        XCTAssertEqual(fields["createdAt"] as? String, "1970-01-01T00:33:20.000Z")
    }

    func testSaveWrapsRecordErrorsWithCloudKitContext() async throws {
        let database = FakeCloudKitDatabaseWriter()
        database.saveRecordError = NSError(
            domain: CKError.errorDomain,
            code: CKError.Code.serverRejectedRequest.rawValue,
            userInfo: [
                NSLocalizedDescriptionKey: "Server rejected the request",
                "ServerErrorDescription": "field text rejected"
            ]
        )
        let transport = CloudKitDefaultSyncTransport(database: database)
        let payload = CloudKitRecordPayload(
            entityType: .moment,
            entityId: "post-1",
            fields: ["text": .string("Hello CloudKit")]
        )

        do {
            _ = try await transport.save(payload)
            XCTFail("Expected save to throw")
        } catch {
            let message = error.localizedDescription
            XCTAssertTrue(message.contains("Save CloudKit record failed."))
            XCTAssertTrue(message.contains("Record: PMMoment / pm.moment.post-1"))
            XCTAssertTrue(message.contains("Zone: PrivateMomentsV1"))
            XCTAssertTrue(message.contains("Fields: text"))
            XCTAssertTrue(message.contains("serverRejectedRequest"))
            XCTAssertTrue(message.contains("field text rejected"))
        }
    }

    func testSaveUpdatesServerRecordWhenRecordAlreadyExists() async throws {
        let database = FakeCloudKitDatabaseWriter()
        let zoneID = CKRecordZone.ID(zoneName: CloudKitSyncDefaults.zoneName, ownerName: CKCurrentUserDefaultName)
        let serverRecord = CKRecord(
            recordType: "PMMoment",
            recordID: CKRecord.ID(recordName: "pm.moment.post-1", zoneID: zoneID)
        )
        serverRecord["text"] = "Old text" as NSString
        database.saveRecordErrors = [
            NSError(
                domain: CKError.errorDomain,
                code: CKError.Code.serverRecordChanged.rawValue,
                userInfo: [CKRecordChangedErrorServerRecordKey: serverRecord]
            )
        ]
        let transport = CloudKitDefaultSyncTransport(database: database)
        let payload = CloudKitRecordPayload(
            entityType: .moment,
            entityId: "post-1",
            fields: ["text": .string("New text")]
        )

        _ = try await transport.save(payload)

        XCTAssertEqual(database.events, [
            .saveZone("PrivateMomentsV1"),
            .saveRecord("PMMoment", "pm.moment.post-1", "PrivateMomentsV1"),
            .saveRecord("PMMoment", "pm.moment.post-1", "PrivateMomentsV1")
        ])
        XCTAssertEqual(database.savedRecords.last?["text"] as? String, "New text")
    }

    func testSaveAssetsUpdatesServerRecordWhenRecordAlreadyExists() async throws {
        let database = FakeCloudKitDatabaseWriter()
        let zoneID = CKRecordZone.ID(zoneName: CloudKitSyncDefaults.zoneName, ownerName: CKCurrentUserDefaultName)
        let serverRecord = CKRecord(
            recordType: "PMMedia",
            recordID: CKRecord.ID(recordName: "pm.media.media-1", zoneID: zoneID)
        )
        serverRecord["kind"] = "image" as NSString
        database.saveRecordErrors = [
            NSError(
                domain: CKError.errorDomain,
                code: CKError.Code.serverRecordChanged.rawValue,
                userInfo: [CKRecordChangedErrorServerRecordKey: serverRecord]
            )
        ]
        let assetURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("jpg")
        try Data([0x01, 0x02, 0x03]).write(to: assetURL)
        defer {
            try? FileManager.default.removeItem(at: assetURL)
        }
        let transport = CloudKitDefaultSyncTransport(database: database)
        let payload = CloudKitAssetRecordPayload(
            metadataPayload: CloudKitRecordPayload(
                entityType: .media,
                entityId: "media-1",
                fields: [
                    "postId": .string("post-1"),
                    "kind": .string("image")
                ]
            ),
            assetFields: [.init(fieldName: "compressedAsset", fileURL: assetURL)]
        )

        _ = try await transport.saveAssets(payload)

        XCTAssertEqual(database.savedRecords.count, 2)
        XCTAssertEqual(database.savedRecords.last?["kind"] as? String, "image")
        XCTAssertNotNil(database.savedRecords.last?["compressedAsset"] as? CKAsset)
    }

    func testDefaultZoneProbeSavesRecordInDefaultZoneAndCleansUp() async throws {
        let database = FakeCloudKitDatabaseWriter()
        let probe = CloudKitDefaultZoneProbe(
            database: database,
            now: { Date(timeIntervalSince1970: 3_000) },
            idGenerator: { "probe-1" }
        )

        let result = try await probe.run()

        XCTAssertEqual(result.recordName, "pm.probe.probe-1")
        XCTAssertEqual(result.recordIDStrategy, .custom)
        XCTAssertEqual(database.events, [
            .saveRecord("PMCloudKitProbe", "pm.probe.probe-1", CKRecordZone.default().zoneID.zoneName),
            .deleteRecord("pm.probe.probe-1", CKRecordZone.default().zoneID.zoneName)
        ])
    }

    func testDefaultZoneProbeFallsBackToAutomaticRecordID() async throws {
        let database = FakeCloudKitDatabaseWriter()
        database.saveRecordErrors = [
            NSError(
                domain: CKError.errorDomain,
                code: CKError.Code.serverRejectedRequest.rawValue,
                userInfo: [NSLocalizedDescriptionKey: "Custom ID rejected"]
            )
        ]
        let probe = CloudKitDefaultZoneProbe(
            database: database,
            now: { Date(timeIntervalSince1970: 3_000) },
            idGenerator: { "probe-1" }
        )

        let result = try await probe.run()

        XCTAssertEqual(result.recordIDStrategy, .automatic)
        XCTAssertFalse(result.recordName.hasPrefix("pm.probe."))
        XCTAssertEqual(database.events.count, 3)
        XCTAssertEqual(database.events[0], .saveRecord("PMCloudKitProbe", "pm.probe.probe-1", CKRecordZone.default().zoneID.zoneName))
    }

    func testDefaultZoneProbeWrapsSaveErrorsWithDiagnosticContext() async throws {
        let database = FakeCloudKitDatabaseWriter()
        database.saveRecordErrors = [
            NSError(
                domain: CKError.errorDomain,
                code: CKError.Code.serverRejectedRequest.rawValue,
                userInfo: [NSLocalizedDescriptionKey: "Custom ID rejected"]
            ),
            NSError(
                domain: CKError.errorDomain,
                code: CKError.Code.serverRejectedRequest.rawValue,
                userInfo: [NSLocalizedDescriptionKey: "Automatic ID rejected"]
            )
        ]
        let probe = CloudKitDefaultZoneProbe(
            database: database,
            idGenerator: { "probe-1" }
        )

        do {
            _ = try await probe.run()
            XCTFail("Expected probe to throw")
        } catch let error as CloudKitDefaultZoneProbeError {
            XCTAssertEqual(error.localizedDescription, "CloudKit private database is not accepting writes right now.")
            let message = error.diagnosticDescription
            XCTAssertTrue(message.contains("CloudKit default-zone probe failed for both custom and automatic record IDs."))
            XCTAssertTrue(message.contains("Custom record ID:"))
            XCTAssertTrue(message.contains("Automatic record ID:"))
            XCTAssertTrue(message.contains("Record: PMCloudKitProbe / pm.probe.probe-1"))
            XCTAssertTrue(message.contains("Zone: \(CKRecordZone.default().zoneID.zoneName)"))
            XCTAssertTrue(message.contains("serverRejectedRequest"))
        } catch {
            XCTFail("Expected CloudKitDefaultZoneProbeError, got \(error)")
        }
    }

    func testDeletePreparesZoneThenDeletesRecordID() async throws {
        let database = FakeCloudKitDatabaseWriter()
        let transport = CloudKitDefaultSyncTransport(database: database)

        try await transport.delete(
            recordType: "PMMoment",
            recordName: "pm.moment.post-1",
            zoneName: "PrivateMomentsV1"
        )

        XCTAssertEqual(database.events, [
            .saveZone("PrivateMomentsV1"),
            .deleteRecord("pm.moment.post-1", "PrivateMomentsV1")
        ])
    }

    func testFetchRecordPreparesZoneThenDecodesRequestedEntityRecord() async throws {
        let database = FakeCloudKitDatabaseWriter()
        let transport = CloudKitDefaultSyncTransport(database: database)
        let payload = CloudKitRecordPayload(
            entityType: .checkInItem,
            entityId: "checkin-item-cloudkit",
            fields: [
                "name": .string("Hydration"),
                "createdAt": .date(Date(timeIntervalSince1970: 2_500))
            ]
        )
        database.fetchedRecords[payload.recordName] = CloudKitRecordEncoder.record(from: payload)

        let fetched = try await transport.fetchRecord(
            entityType: .checkInItem,
            entityId: "checkin-item-cloudkit",
            zoneName: CloudKitSyncDefaults.zoneName
        )

        XCTAssertEqual(database.events, [
            .saveZone("PrivateMomentsV1"),
            .fetchRecord("pm.checkin_item.checkin-item-cloudkit", "PrivateMomentsV1")
        ])
        XCTAssertEqual(fetched, payload)
    }

    func testFetchChangesPreparesZoneThenDecodesModifiedPayloadsAndDeletedRecordIdentities() async throws {
        let database = FakeCloudKitDatabaseWriter()
        let transport = CloudKitDefaultSyncTransport(database: database)
        let modifiedPayload = CloudKitRecordPayload(
            entityType: .moment,
            entityId: "post-1",
            fields: ["text": .string("Remote edit")]
        )
        let zoneID = CKRecordZone.ID(zoneName: CloudKitSyncDefaults.zoneName, ownerName: CKCurrentUserDefaultName)
        database.zoneChangesResult = .init(
            modifiedRecords: [CloudKitRecordEncoder.record(from: modifiedPayload)],
            deletedRecords: [
                .init(
                    recordID: CKRecord.ID(recordName: "pm.comment.comment-1", zoneID: zoneID),
                    recordType: "PMComment"
                )
            ],
            serverChangeTokenData: Data([1, 2, 3]),
            moreComing: false
        )

        let changes = try await transport.fetchChanges(
            zoneName: CloudKitSyncDefaults.zoneName,
            sinceChangeTokenData: Data([9]),
            resultsLimit: 100
        )

        XCTAssertEqual(database.events, [
            .saveZone("PrivateMomentsV1"),
            .fetchRecordZoneChanges("PrivateMomentsV1", Data([9]), 100)
        ])
        XCTAssertEqual(changes.modifiedPayloads, [modifiedPayload])
        XCTAssertEqual(changes.deletedRecords, [
            .init(
                entityType: .comment,
                entityId: "comment-1",
                recordType: "PMComment",
                recordName: "pm.comment.comment-1",
                zoneName: CloudKitSyncDefaults.zoneName
            )
        ])
        XCTAssertEqual(changes.serverChangeTokenData, Data([1, 2, 3]))
        XCTAssertFalse(changes.moreComing)
    }

    func testFetchChangesIncludesDownloadedAssetRecords() async throws {
        let database = FakeCloudKitDatabaseWriter()
        let transport = CloudKitDefaultSyncTransport(database: database)
        let assetURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appendingPathExtension("jpg")
        try Data([0x11, 0x12]).write(to: assetURL)
        defer { try? FileManager.default.removeItem(at: assetURL) }
        let mediaPayload = CloudKitRecordPayload(
            entityType: .media,
            entityId: "media-asset-1",
            fields: ["postId": .string("post-1")]
        )
        let assetRecord = CloudKitRecordEncoder.record(from: CloudKitAssetRecordPayload(
            metadataPayload: mediaPayload,
            assetFields: [.init(fieldName: "compressedAsset", fileURL: assetURL)]
        ))
        database.zoneChangesResult = .init(
            modifiedRecords: [assetRecord],
            deletedRecords: [],
            serverChangeTokenData: Data([4, 5]),
            moreComing: false
        )

        let changes = try await transport.fetchChanges(
            zoneName: CloudKitSyncDefaults.zoneName,
            sinceChangeTokenData: nil,
            resultsLimit: nil
        )

        XCTAssertEqual(changes.modifiedPayloads, [mediaPayload])
        XCTAssertEqual(changes.modifiedAssetRecords, [
            CloudKitDownloadedAssetRecord(
                payload: mediaPayload,
                assetFields: [.init(fieldName: "compressedAsset", fileURL: assetURL)]
            )
        ])
    }

    func testFetchChangesRejectsUnsupportedModifiedRecordType() async throws {
        let database = FakeCloudKitDatabaseWriter()
        let transport = CloudKitDefaultSyncTransport(database: database)
        let recordID = CKRecord.ID(
            recordName: "pm.moment.post-1",
            zoneID: CKRecordZone.ID(zoneName: CloudKitSyncDefaults.zoneName, ownerName: CKCurrentUserDefaultName)
        )
        database.zoneChangesResult = .init(
            modifiedRecords: [CKRecord(recordType: "PMUnknown", recordID: recordID)],
            deletedRecords: [],
            serverChangeTokenData: nil,
            moreComing: false
        )

        do {
            _ = try await transport.fetchChanges(
                zoneName: CloudKitSyncDefaults.zoneName,
                sinceChangeTokenData: nil,
                resultsLimit: nil
            )
            XCTFail("Expected unsupported record type to throw")
        } catch {
            XCTAssertEqual(error as? CloudKitRecordDecoderError, .unsupportedRecordType("PMUnknown"))
        }
    }
}

private final class FakeCloudKitDatabaseWriter: CloudKitDatabaseWriting {
    enum Event: Equatable {
        case saveZone(String)
        case fetchRecordZone(String)
        case saveRecord(String, String, String)
        case fetchRecord(String, String)
        case deleteRecord(String, String)
        case fetchRecordZoneChanges(String, Data?, Int?)
    }

    private(set) var events: [Event] = []
    var saveZoneError: Error?
    var saveRecordError: Error?
    var saveRecordErrors: [Error] = []
    private(set) var savedRecords: [CKRecord] = []
    var fetchedRecords: [String: CKRecord] = [:]
    var fetchedZoneNames = Set<String>()
    var zoneChangesResult = CloudKitRawZoneChanges(
        modifiedRecords: [],
        deletedRecords: [],
        serverChangeTokenData: nil,
        moreComing: false
    )

    var savedZoneNames: [String] {
        events.compactMap {
            if case .saveZone(let zoneName) = $0 {
                return zoneName
            }
            return nil
        }
    }

    func saveZone(_ zone: CKRecordZone) async throws -> CKRecordZone {
        events.append(.saveZone(zone.zoneID.zoneName))
        if let saveZoneError {
            throw saveZoneError
        }
        return zone
    }

    func fetchRecordZone(withID zoneID: CKRecordZone.ID) async throws -> CKRecordZone {
        events.append(.fetchRecordZone(zoneID.zoneName))
        guard fetchedZoneNames.contains(zoneID.zoneName) else {
            throw NSError(
                domain: CKError.errorDomain,
                code: CKError.Code.unknownItem.rawValue,
                userInfo: nil
            )
        }
        return CKRecordZone(zoneID: zoneID)
    }

    func saveRecord(_ record: CKRecord) async throws -> CKRecord {
        events.append(.saveRecord(
            record.recordType,
            record.recordID.recordName,
            record.recordID.zoneID.zoneName
        ))
        savedRecords.append(record)
        if !saveRecordErrors.isEmpty {
            throw saveRecordErrors.removeFirst()
        }
        if let saveRecordError {
            throw saveRecordError
        }
        return record
    }

    func fetchRecord(withID recordID: CKRecord.ID) async throws -> CKRecord {
        events.append(.fetchRecord(recordID.recordName, recordID.zoneID.zoneName))
        if let record = fetchedRecords[recordID.recordName] {
            return record
        }
        throw NSError(
            domain: CKError.errorDomain,
            code: CKError.Code.unknownItem.rawValue,
            userInfo: nil
        )
    }

    func deleteRecord(withID recordID: CKRecord.ID) async throws {
        events.append(.deleteRecord(recordID.recordName, recordID.zoneID.zoneName))
    }

    func fetchRecordZoneChanges(
        inZoneWith zoneID: CKRecordZone.ID,
        sinceChangeTokenData: Data?,
        desiredKeys _: [CKRecord.FieldKey]?,
        resultsLimit: Int?
    ) async throws -> CloudKitRawZoneChanges {
        events.append(.fetchRecordZoneChanges(zoneID.zoneName, sinceChangeTokenData, resultsLimit))
        return zoneChangesResult
    }
}
