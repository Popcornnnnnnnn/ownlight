import XCTest
@testable import PrivateMoments

final class CloudKitSyncRunnerTests: XCTestCase {
    private var temporaryRoot: URL!
    private var savedLocalWeeklyReviews: [ReviewPayload] = []
    private var savedPreferenceState: CloudKitSyncRunnerAppSettingsState!

    override func setUpWithError() throws {
        try super.setUpWithError()
        savedLocalWeeklyReviews = AppSettings.localWeeklyReviews
        savedPreferenceState = CloudKitSyncRunnerAppSettingsState.capture()
        AppSettings.localWeeklyReviews = []
        ComposerDraftStore.clear()
        EditDraftStore.clear(postId: "post-remote")
        temporaryRoot = FileManager.default.temporaryDirectory
            .appending(path: "CloudKitSyncRunnerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        ComposerDraftStore.clear()
        EditDraftStore.clear(postId: "post-remote")
        AppSettings.localWeeklyReviews = savedLocalWeeklyReviews
        savedPreferenceState.restore()
        if let temporaryRoot {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }
        try super.tearDownWithError()
    }

    func testRunOnceSavesClaimedUpsertAndMarksFinished() async throws {
        let database = try LocalDatabase.openForTesting(url: temporaryRoot.appending(path: "upsert.sqlite"))
        let mappedAt = Date(timeIntervalSince1970: 4_500)
        let runAt = mappedAt.addingTimeInterval(30)
        try database.upsertCloudKitRecordState(.init(
            entityType: .moment,
            entityId: "post-1",
            localContentHash: "hash-1",
            lastMappedAt: mappedAt
        ))
        let change = try database.enqueueCloudKitPendingChange(
            entityType: .moment,
            entityId: "post-1",
            changeKind: .upsert,
            reason: "local update",
            now: mappedAt.addingTimeInterval(1)
        )
        let payload = CloudKitRecordPayload(
            entityType: .moment,
            entityId: "post-1",
            fields: ["text": .string("Hello CloudKit")]
        )
        let resolver = FakeCloudKitPayloadResolver(payloads: [change.id: payload])
        let transport = FakeCloudKitSyncTransport()
        transport.saveResult = .init(recordChangeTag: "tag-1", lastKnownRecordJson: #"{"text":"Hello CloudKit"}"#)
        let runner = CloudKitSyncRunner(
            database: database,
            payloadResolver: resolver,
            transport: transport,
            incomingRecordApplier: FakeCloudKitIncomingRecordApplier(),
            now: { runAt },
            retryDelay: 90
        )

        let summary = await runner.runOnce(limit: 10)

        XCTAssertEqual(summary, .init(claimed: 1, saved: 1, deleted: 0, failed: 0))
        XCTAssertEqual(transport.savedPayloads, [payload])
        XCTAssertEqual(transport.deletedRecords, [])
        let finished = try XCTUnwrap(database.fetchCloudKitPendingChange(id: change.id))
        XCTAssertEqual(finished.status, .finished)
        XCTAssertEqual(finished.finishedAt, runAt)
        let state = try XCTUnwrap(database.fetchCloudKitRecordState(entityType: .moment, entityId: "post-1"))
        XCTAssertEqual(state.recordChangeTag, "tag-1")
        XCTAssertEqual(state.lastKnownRecordJson, #"{"text":"Hello CloudKit"}"#)
        XCTAssertEqual(state.lastUploadedAt, runAt)
        XCTAssertNil(state.cloudDeletedAt)
    }

    func testRunOnceSavesParentTagBeforeDependentPostTagEvenWhenClaimedLater() async throws {
        let database = try LocalDatabase.openForTesting(url: temporaryRoot.appending(path: "upload-parent-order.sqlite"))
        let mappedAt = Date(timeIntervalSince1970: 4_550)
        let runAt = mappedAt.addingTimeInterval(30)
        let assignmentChange = try database.enqueueCloudKitPendingChange(
            entityType: .postTag,
            entityId: "assignment-1",
            changeKind: .upsert,
            reason: "initial_upload",
            now: mappedAt.addingTimeInterval(1)
        )
        let tagChange = try database.enqueueCloudKitPendingChange(
            entityType: .tag,
            entityId: "topic-1",
            changeKind: .upsert,
            reason: "initial_upload",
            now: mappedAt.addingTimeInterval(2)
        )
        let tagPayload = CloudKitRecordPayload(
            entityType: .tag,
            entityId: "topic-1",
            fields: [
                "name": .string("CloudKit"),
                "normalizedName": .string("cloudkit")
            ]
        )
        let assignmentPayload = CloudKitRecordPayload(
            entityType: .postTag,
            entityId: "assignment-1",
            fields: [
                "postId": .string("post-1"),
                "tagId": .string("topic-1")
            ]
        )
        let resolver = FakeCloudKitPayloadResolver(payloads: [
            assignmentChange.id: assignmentPayload,
            tagChange.id: tagPayload
        ])
        let transport = FakeCloudKitSyncTransport()
        let runner = CloudKitSyncRunner(
            database: database,
            payloadResolver: resolver,
            transport: transport,
            incomingRecordApplier: FakeCloudKitIncomingRecordApplier(),
            now: { runAt },
            retryDelay: 90
        )

        let summary = await runner.runOnce(limit: 10)

        XCTAssertEqual(summary, .init(claimed: 2, saved: 2, deleted: 0, failed: 0))
        XCTAssertEqual(transport.savedPayloads.map(\.entityType), [.tag, .postTag])
        XCTAssertEqual(try XCTUnwrap(database.fetchCloudKitPendingChange(id: tagChange.id)).status, .finished)
        XCTAssertEqual(try XCTUnwrap(database.fetchCloudKitPendingChange(id: assignmentChange.id)).status, .finished)
    }

    func testRunOnceUploadsClaimedMediaAssetInsteadOfSavingMetadataRecord() async throws {
        let database = try LocalDatabase.openForTesting(url: temporaryRoot.appending(path: "asset-upload.sqlite"))
        let mappedAt = Date(timeIntervalSince1970: 4_600)
        let runAt = mappedAt.addingTimeInterval(30)
        let assetURL = temporaryRoot.appending(path: "asset.jpg")
        try Data([0x01, 0x02, 0x03]).write(to: assetURL)
        try database.upsertCloudKitRecordState(.init(
            entityType: .media,
            entityId: "media-1",
            localContentHash: "hash-asset",
            lastMappedAt: mappedAt
        ))
        let change = try database.enqueueCloudKitPendingChange(
            entityType: .media,
            entityId: "media-1",
            changeKind: .assetUpload,
            reason: "local media file",
            now: mappedAt.addingTimeInterval(1)
        )
        let metadataPayload = CloudKitRecordPayload(
            entityType: .media,
            entityId: "media-1",
            fields: [
                "postId": .string("post-1"),
                "kind": .string("image")
            ]
        )
        let assetPayload = CloudKitAssetRecordPayload(
            metadataPayload: metadataPayload,
            assetFields: [
                .init(fieldName: "compressedAsset", fileURL: assetURL)
            ]
        )
        let resolver = FakeCloudKitPayloadResolver(
            payloads: [:],
            assetPayloads: [change.id: assetPayload]
        )
        let transport = FakeCloudKitSyncTransport()
        transport.saveAssetsResult = .init(
            recordChangeTag: "asset-tag-1",
            lastKnownRecordJson: #"{"asset":true}"#
        )
        let runner = CloudKitSyncRunner(
            database: database,
            payloadResolver: resolver,
            transport: transport,
            incomingRecordApplier: FakeCloudKitIncomingRecordApplier(),
            now: { runAt },
            retryDelay: 90
        )

        let summary = await runner.runOnce(limit: 10)

        XCTAssertEqual(summary, .init(claimed: 1, saved: 1, deleted: 0, failed: 0))
        XCTAssertEqual(transport.savedPayloads, [])
        XCTAssertEqual(transport.savedAssetPayloads, [assetPayload])
        let finished = try XCTUnwrap(database.fetchCloudKitPendingChange(id: change.id))
        XCTAssertEqual(finished.status, .finished)
        let state = try XCTUnwrap(database.fetchCloudKitRecordState(entityType: .media, entityId: "media-1"))
        XCTAssertEqual(state.recordChangeTag, "asset-tag-1")
        XCTAssertEqual(state.lastKnownRecordJson, #"{"asset":true}"#)
        XCTAssertEqual(state.lastUploadedAt, runAt)
        XCTAssertNil(state.cloudDeletedAt)
    }

    func testRunOnceDeletesClaimedRecordAndMarksCloudDeleted() async throws {
        let database = try LocalDatabase.openForTesting(url: temporaryRoot.appending(path: "delete.sqlite"))
        let mappedAt = Date(timeIntervalSince1970: 4_700)
        let runAt = mappedAt.addingTimeInterval(30)
        try database.upsertCloudKitRecordState(.init(
            entityType: .moment,
            entityId: "post-1",
            recordChangeTag: "old-tag",
            lastMappedAt: mappedAt,
            lastUploadedAt: mappedAt.addingTimeInterval(1)
        ))
        let change = try database.enqueueCloudKitPendingChange(
            entityType: .moment,
            entityId: "post-1",
            changeKind: .delete,
            reason: "local delete",
            now: mappedAt.addingTimeInterval(2)
        )
        let resolver = FakeCloudKitPayloadResolver(payloads: [:])
        let transport = FakeCloudKitSyncTransport()
        let runner = CloudKitSyncRunner(
            database: database,
            payloadResolver: resolver,
            transport: transport,
            incomingRecordApplier: FakeCloudKitIncomingRecordApplier(),
            now: { runAt },
            retryDelay: 90
        )

        let summary = await runner.runOnce(limit: 10)

        XCTAssertEqual(summary, .init(claimed: 1, saved: 0, deleted: 1, failed: 0))
        XCTAssertEqual(transport.savedPayloads, [])
        XCTAssertEqual(transport.deletedRecords, [
            .init(recordType: "PMMoment", recordName: "pm.moment.post-1", zoneName: CloudKitSyncDefaults.zoneName)
        ])
        let finished = try XCTUnwrap(database.fetchCloudKitPendingChange(id: change.id))
        XCTAssertEqual(finished.status, .finished)
        let state = try XCTUnwrap(database.fetchCloudKitRecordState(entityType: .moment, entityId: "post-1"))
        XCTAssertEqual(state.cloudDeletedAt, runAt)
        XCTAssertEqual(state.lastUploadedAt, runAt)
        XCTAssertEqual(state.recordChangeTag, "old-tag")
    }

    func testRunOnceMarksFailedAndSchedulesRetryWhenTransportThrows() async throws {
        let database = try LocalDatabase.openForTesting(url: temporaryRoot.appending(path: "failure.sqlite"))
        let mappedAt = Date(timeIntervalSince1970: 4_900)
        let runAt = mappedAt.addingTimeInterval(30)
        try database.upsertCloudKitRecordState(.init(entityType: .moment, entityId: "post-1", lastMappedAt: mappedAt))
        let change = try database.enqueueCloudKitPendingChange(
            entityType: .moment,
            entityId: "post-1",
            changeKind: .upsert,
            reason: "local update",
            now: mappedAt.addingTimeInterval(1)
        )
        let payload = CloudKitRecordPayload(
            entityType: .moment,
            entityId: "post-1",
            fields: ["text": .string("Needs retry")]
        )
        let resolver = FakeCloudKitPayloadResolver(payloads: [change.id: payload])
        let transport = FakeCloudKitSyncTransport()
        transport.saveError = TestCloudKitSyncError.networkDown
        let runner = CloudKitSyncRunner(
            database: database,
            payloadResolver: resolver,
            transport: transport,
            incomingRecordApplier: FakeCloudKitIncomingRecordApplier(),
            now: { runAt },
            retryDelay: 90
        )

        let summary = await runner.runOnce(limit: 10)

        XCTAssertEqual(summary, .init(claimed: 1, saved: 0, deleted: 0, failed: 1))
        let failed = try XCTUnwrap(database.fetchCloudKitPendingChange(id: change.id))
        XCTAssertEqual(failed.status, .failed)
        XCTAssertEqual(failed.attemptCount, 1)
        XCTAssertEqual(failed.lastErrorCode, "cloudkit_sync_failed")
        XCTAssertTrue(failed.lastErrorMessage?.contains("networkDown") == true)
        XCTAssertEqual(failed.nextAttemptAt, runAt.addingTimeInterval(90))
        XCTAssertEqual(try database.claimDueCloudKitPendingChanges(limit: 10, now: runAt.addingTimeInterval(89)), [])
    }

    func testPullOnceAppliesRemoteUpsertAndAdvancesCursorAfterSuccess() async throws {
        let database = try LocalDatabase.openForTesting(url: temporaryRoot.appending(path: "pull-upsert.sqlite"))
        let previousToken = Data([1, 2, 3])
        let nextToken = Data([4, 5, 6])
        let previousSyncAt = Date(timeIntervalSince1970: 5_100)
        let runAt = previousSyncAt.addingTimeInterval(40)
        try database.upsertCloudKitSyncState(.init(
            scope: CloudKitSyncDefaults.zoneName,
            serverChangeTokenData: previousToken,
            lastAccountStatus: "available",
            lastSyncStartedAt: previousSyncAt.addingTimeInterval(-5),
            lastSyncFinishedAt: previousSyncAt,
            lastErrorCode: nil,
            updatedAt: previousSyncAt
        ))
        let payload = CloudKitRecordPayload(
            entityType: .moment,
            entityId: "remote-post",
            fields: ["text": .string("Remote update")]
        )
        let resolver = FakeCloudKitPayloadResolver(payloads: [:])
        let transport = FakeCloudKitSyncTransport()
        transport.downloadedChanges = .init(
            modifiedPayloads: [payload],
            deletedRecords: [],
            serverChangeTokenData: nextToken,
            moreComing: false
        )
        let applier = FakeCloudKitIncomingRecordApplier()
        let runner = CloudKitSyncRunner(
            database: database,
            payloadResolver: resolver,
            transport: transport,
            incomingRecordApplier: applier,
            now: { runAt },
            retryDelay: 90
        )

        let summary = await runner.pullOnce(resultsLimit: 100)

        XCTAssertEqual(summary, .init(
            fetchedModified: 1,
            fetchedDeleted: 0,
            appliedUpserts: 1,
            appliedDeletes: 0,
            deferred: 0,
            ignored: 0,
            failed: 0,
            moreComing: false
        ))
        XCTAssertEqual(transport.fetchRequests, [
            .init(zoneName: CloudKitSyncDefaults.zoneName, sinceChangeTokenData: previousToken, resultsLimit: 100)
        ])
        XCTAssertEqual(applier.appliedUpserts, [.init(payload: payload, downloadedAt: runAt)])
        let recordState = try XCTUnwrap(database.fetchCloudKitRecordState(entityType: .moment, entityId: "remote-post"))
        XCTAssertEqual(recordState.lastKnownRecordJson, try CloudKitRecordPayloadSnapshot.json(from: payload))
        XCTAssertEqual(recordState.lastDownloadedAt, runAt)
        XCTAssertNil(recordState.cloudDeletedAt)
        let syncState = try XCTUnwrap(database.fetchCloudKitSyncState(scope: CloudKitSyncDefaults.zoneName))
        XCTAssertEqual(syncState.serverChangeTokenData, nextToken)
        XCTAssertEqual(syncState.lastSyncStartedAt, runAt)
        XCTAssertEqual(syncState.lastSyncFinishedAt, runAt)
        XCTAssertNil(syncState.lastErrorCode)
    }

    func testPullOnceAppliesRemoteDeleteAndAdvancesCursorAfterSuccess() async throws {
        let database = try LocalDatabase.openForTesting(url: temporaryRoot.appending(path: "pull-delete.sqlite"))
        let previousToken = Data([9])
        let nextToken = Data([10])
        let mappedAt = Date(timeIntervalSince1970: 5_300)
        let runAt = mappedAt.addingTimeInterval(20)
        try database.upsertCloudKitSyncState(.init(
            scope: CloudKitSyncDefaults.zoneName,
            serverChangeTokenData: previousToken,
            lastAccountStatus: "available",
            lastSyncStartedAt: mappedAt.addingTimeInterval(-20),
            lastSyncFinishedAt: mappedAt,
            lastErrorCode: nil,
            updatedAt: mappedAt
        ))
        try database.upsertCloudKitRecordState(.init(
            entityType: .moment,
            entityId: "remote-post",
            recordChangeTag: "old",
            lastKnownRecordJson: #"{"old":true}"#,
            lastMappedAt: mappedAt,
            lastUploadedAt: mappedAt
        ))
        let deletedRecord = CloudKitDeletedRecordIdentity(
            entityType: .moment,
            entityId: "remote-post",
            recordType: CloudKitSyncEntityType.moment.recordType,
            recordName: CloudKitSyncEntityType.moment.recordName(entityId: "remote-post"),
            zoneName: CloudKitSyncDefaults.zoneName
        )
        let transport = FakeCloudKitSyncTransport()
        transport.downloadedChanges = .init(
            modifiedPayloads: [],
            deletedRecords: [deletedRecord],
            serverChangeTokenData: nextToken,
            moreComing: false
        )
        let applier = FakeCloudKitIncomingRecordApplier()
        let runner = CloudKitSyncRunner(
            database: database,
            payloadResolver: FakeCloudKitPayloadResolver(payloads: [:]),
            transport: transport,
            incomingRecordApplier: applier,
            now: { runAt },
            retryDelay: 90
        )

        let summary = await runner.pullOnce(resultsLimit: nil)

        XCTAssertEqual(summary.appliedDeletes, 1)
        XCTAssertEqual(applier.appliedDeletes, [
            .init(entityType: .moment, entityId: "remote-post", cloudDeletedAt: runAt, downloadedAt: runAt)
        ])
        let recordState = try XCTUnwrap(database.fetchCloudKitRecordState(entityType: .moment, entityId: "remote-post"))
        XCTAssertEqual(recordState.cloudDeletedAt, runAt)
        XCTAssertEqual(recordState.lastDownloadedAt, runAt)
        let syncState = try XCTUnwrap(database.fetchCloudKitSyncState(scope: CloudKitSyncDefaults.zoneName))
        XCTAssertEqual(syncState.serverChangeTokenData, nextToken)
    }

    func testPullOnceDefersRemoteUpsertWhenLocalChangeIsPendingAndKeepsCursor() async throws {
        let database = try LocalDatabase.openForTesting(url: temporaryRoot.appending(path: "pull-defer.sqlite"))
        let previousToken = Data([7])
        let nextToken = Data([8])
        let mappedAt = Date(timeIntervalSince1970: 5_500)
        let runAt = mappedAt.addingTimeInterval(40)
        try database.upsertCloudKitSyncState(.init(
            scope: CloudKitSyncDefaults.zoneName,
            serverChangeTokenData: previousToken,
            lastAccountStatus: "available",
            lastSyncStartedAt: mappedAt.addingTimeInterval(-20),
            lastSyncFinishedAt: mappedAt,
            lastErrorCode: nil,
            updatedAt: mappedAt
        ))
        try database.upsertCloudKitRecordState(.init(
            entityType: .moment,
            entityId: "remote-post",
            lastKnownRecordJson: #"{"text":"local"}"#,
            lastMappedAt: mappedAt,
            lastUploadedAt: mappedAt
        ))
        _ = try database.enqueueCloudKitPendingChange(
            entityType: .moment,
            entityId: "remote-post",
            changeKind: .upsert,
            reason: "local edit",
            now: mappedAt.addingTimeInterval(1)
        )
        let payload = CloudKitRecordPayload(
            entityType: .moment,
            entityId: "remote-post",
            fields: ["text": .string("Remote update")]
        )
        let transport = FakeCloudKitSyncTransport()
        transport.downloadedChanges = .init(
            modifiedPayloads: [payload],
            deletedRecords: [],
            serverChangeTokenData: nextToken,
            moreComing: false
        )
        let applier = FakeCloudKitIncomingRecordApplier()
        let runner = CloudKitSyncRunner(
            database: database,
            payloadResolver: FakeCloudKitPayloadResolver(payloads: [:]),
            transport: transport,
            incomingRecordApplier: applier,
            now: { runAt },
            retryDelay: 90
        )

        let summary = await runner.pullOnce(resultsLimit: 100)

        XCTAssertEqual(summary.deferred, 1)
        XCTAssertEqual(summary.appliedUpserts, 0)
        XCTAssertEqual(applier.appliedUpserts, [])
        let recordState = try XCTUnwrap(database.fetchCloudKitRecordState(entityType: .moment, entityId: "remote-post"))
        XCTAssertEqual(recordState.lastKnownRecordJson, #"{"text":"local"}"#)
        XCTAssertNil(recordState.lastDownloadedAt)
        let syncState = try XCTUnwrap(database.fetchCloudKitSyncState(scope: CloudKitSyncDefaults.zoneName))
        XCTAssertEqual(syncState.serverChangeTokenData, previousToken)
        XCTAssertEqual(syncState.lastSyncFinishedAt, runAt)
        XCTAssertNil(syncState.lastErrorCode)
    }

    func testPullOnceKeepsPreviousCursorWhenDownloadReturnsNoNewToken() async throws {
        let database = try LocalDatabase.openForTesting(url: temporaryRoot.appending(path: "pull-no-token.sqlite"))
        let previousToken = Data([11, 12])
        let previousSyncAt = Date(timeIntervalSince1970: 5_700)
        let runAt = previousSyncAt.addingTimeInterval(60)
        try database.upsertCloudKitSyncState(.init(
            scope: CloudKitSyncDefaults.zoneName,
            serverChangeTokenData: previousToken,
            lastAccountStatus: "available",
            lastSyncStartedAt: previousSyncAt.addingTimeInterval(-20),
            lastSyncFinishedAt: previousSyncAt,
            lastErrorCode: nil,
            updatedAt: previousSyncAt
        ))
        let transport = FakeCloudKitSyncTransport()
        transport.downloadedChanges = .init(
            modifiedPayloads: [],
            deletedRecords: [],
            serverChangeTokenData: nil,
            moreComing: false
        )
        let runner = CloudKitSyncRunner(
            database: database,
            payloadResolver: FakeCloudKitPayloadResolver(payloads: [:]),
            transport: transport,
            incomingRecordApplier: FakeCloudKitIncomingRecordApplier(),
            now: { runAt },
            retryDelay: 90
        )

        let summary = await runner.pullOnce(resultsLimit: 10)

        XCTAssertEqual(summary.failed, 0)
        let syncState = try XCTUnwrap(database.fetchCloudKitSyncState(scope: CloudKitSyncDefaults.zoneName))
        XCTAssertEqual(syncState.serverChangeTokenData, previousToken)
        XCTAssertEqual(syncState.lastSyncFinishedAt, runAt)
    }

    func testPullOnceAppliesRemoteMomentPayloadToLocalDatabaseWithoutOutbox() async throws {
        let database = try LocalDatabase.openForTesting(url: temporaryRoot.appending(path: "pull-local-moment.sqlite"))
        let previousToken = Data([13])
        let nextToken = Data([14])
        let createdAt = Date(timeIntervalSince1970: 5_900)
        let updatedAt = createdAt.addingTimeInterval(20)
        let downloadedAt = updatedAt.addingTimeInterval(40)
        try database.upsertCloudKitSyncState(.init(
            scope: CloudKitSyncDefaults.zoneName,
            serverChangeTokenData: previousToken,
            lastAccountStatus: "available",
            lastSyncStartedAt: nil,
            lastSyncFinishedAt: nil,
            lastErrorCode: nil,
            updatedAt: createdAt
        ))
        let payload = CloudKitRecordPayload(
            entityType: .moment,
            entityId: "remote-moment-1",
            fields: [
                "text": .string("Remote moment body"),
                "isFavorite": .bool(true),
                "isPinned": .bool(true),
                "pinnedAt": .date(updatedAt),
                "occurredAt": .date(createdAt.addingTimeInterval(-600)),
                "localCreatedAt": .date(createdAt),
                "localUpdatedAt": .date(updatedAt),
                "localEditedAt": .date(updatedAt)
            ]
        )
        let transport = FakeCloudKitSyncTransport()
        transport.downloadedChanges = .init(
            modifiedPayloads: [payload],
            deletedRecords: [],
            serverChangeTokenData: nextToken,
            moreComing: false
        )
        let runner = CloudKitSyncRunner(
            database: database,
            payloadResolver: FakeCloudKitPayloadResolver(payloads: [:]),
            transport: transport,
            incomingRecordApplier: CloudKitLocalRecordApplier(database: database),
            now: { downloadedAt },
            retryDelay: 90
        )

        let summary = await runner.pullOnce(resultsLimit: 10)

        XCTAssertEqual(summary.failed, 0)
        XCTAssertEqual(summary.appliedUpserts, 1)
        let post = try XCTUnwrap(database.fetchPost(id: "remote-moment-1"))
        XCTAssertEqual(post.text, "Remote moment body")
        XCTAssertTrue(post.isFavorite)
        XCTAssertTrue(post.isPinned)
        XCTAssertEqual(post.pinnedAt, updatedAt)
        XCTAssertEqual(post.occurredAt, createdAt.addingTimeInterval(-600))
        XCTAssertEqual(post.localCreatedAt, createdAt)
        XCTAssertEqual(post.localUpdatedAt, updatedAt)
        XCTAssertEqual(post.localEditedAt, updatedAt)
        XCTAssertEqual(post.syncStatus, "synced")
        XCTAssertNil(post.deletedAt)
        XCTAssertEqual(try database.count("SELECT COUNT(*) FROM outbox_operations"), 0)
        XCTAssertEqual(try database.fetchCloudKitSyncState(scope: CloudKitSyncDefaults.zoneName)?.serverChangeTokenData, nextToken)
    }

    func testPullOnceAppliesRemoteCommentPayloadToLocalDatabaseWithoutOutbox() async throws {
        let database = try LocalDatabase.openForTesting(url: temporaryRoot.appending(path: "pull-local-comment.sqlite"))
        let previousToken = Data([15])
        let nextToken = Data([16])
        let createdAt = Date(timeIntervalSince1970: 6_100)
        let updatedAt = createdAt.addingTimeInterval(30)
        let downloadedAt = updatedAt.addingTimeInterval(45)
        try database.upsertCloudKitSyncState(.init(
            scope: CloudKitSyncDefaults.zoneName,
            serverChangeTokenData: previousToken,
            lastAccountStatus: "available",
            lastSyncStartedAt: nil,
            lastSyncFinishedAt: nil,
            lastErrorCode: nil,
            updatedAt: createdAt
        ))
        try database.insert(TimelinePost(
            id: "remote-moment-1",
            text: "Existing post",
            isFavorite: false,
            isPinned: false,
            pinnedAt: nil,
            aiTagProcessedAt: nil,
            tagsUserEditedAt: nil,
            occurredAt: createdAt,
            localCreatedAt: createdAt,
            localUpdatedAt: createdAt,
            localEditedAt: nil,
            serverVersion: nil,
            syncStatus: "synced",
            deletedAt: nil
        ))
        let payload = CloudKitRecordPayload(
            entityType: .comment,
            entityId: "remote-comment-1",
            fields: [
                "postId": .string("remote-moment-1"),
                "text": .string("Remote comment"),
                "createdAt": .date(createdAt),
                "updatedAt": .date(updatedAt)
            ]
        )
        let transport = FakeCloudKitSyncTransport()
        transport.downloadedChanges = .init(
            modifiedPayloads: [payload],
            deletedRecords: [],
            serverChangeTokenData: nextToken,
            moreComing: false
        )
        let runner = CloudKitSyncRunner(
            database: database,
            payloadResolver: FakeCloudKitPayloadResolver(payloads: [:]),
            transport: transport,
            incomingRecordApplier: CloudKitLocalRecordApplier(database: database),
            now: { downloadedAt },
            retryDelay: 90
        )

        let summary = await runner.pullOnce(resultsLimit: 10)

        XCTAssertEqual(summary.failed, 0)
        XCTAssertEqual(summary.appliedUpserts, 1)
        let comment = try XCTUnwrap(database.fetchComment(id: "remote-comment-1"))
        XCTAssertEqual(comment.postId, "remote-moment-1")
        XCTAssertEqual(comment.text, "Remote comment")
        XCTAssertEqual(comment.createdAt, createdAt)
        XCTAssertEqual(comment.updatedAt, updatedAt)
        XCTAssertNil(comment.deletedAt)
        XCTAssertEqual(try database.count("SELECT COUNT(*) FROM outbox_operations"), 0)
        XCTAssertEqual(try database.fetchCloudKitSyncState(scope: CloudKitSyncDefaults.zoneName)?.serverChangeTokenData, nextToken)
    }

    func testPullOnceFetchesMissingMomentParentBeforeApplyingDependentComment() async throws {
        let database = try LocalDatabase.openForTesting(url: temporaryRoot.appending(path: "pull-missing-comment-parent.sqlite"))
        let previousToken = Data([16, 1])
        let nextToken = Data([16, 2])
        let createdAt = Date(timeIntervalSince1970: 6_160)
        let updatedAt = createdAt.addingTimeInterval(30)
        let downloadedAt = updatedAt.addingTimeInterval(45)
        try database.upsertCloudKitSyncState(.init(
            scope: CloudKitSyncDefaults.zoneName,
            serverChangeTokenData: previousToken,
            lastAccountStatus: "available",
            lastSyncStartedAt: nil,
            lastSyncFinishedAt: nil,
            lastErrorCode: nil,
            updatedAt: createdAt
        ))
        let parentPayload = CloudKitRecordPayload(
            entityType: .moment,
            entityId: "comment-parent-moment",
            fields: [
                "text": .string("Fetched parent"),
                "isFavorite": .bool(false),
                "isPinned": .bool(false),
                "occurredAt": .date(createdAt.addingTimeInterval(-120)),
                "localCreatedAt": .date(createdAt),
                "localUpdatedAt": .date(updatedAt)
            ]
        )
        let commentPayload = CloudKitRecordPayload(
            entityType: .comment,
            entityId: "dependent-comment",
            fields: [
                "postId": .string("comment-parent-moment"),
                "text": .string("Comment arrived first"),
                "createdAt": .date(createdAt),
                "updatedAt": .date(updatedAt)
            ]
        )
        let transport = FakeCloudKitSyncTransport()
        transport.downloadedChanges = .init(
            modifiedPayloads: [commentPayload],
            deletedRecords: [],
            serverChangeTokenData: nextToken,
            moreComing: false
        )
        transport.fetchRecordPayloads = [
            CloudKitSyncEntityType.moment.localRecordStateId(entityId: "comment-parent-moment"): parentPayload
        ]
        let runner = CloudKitSyncRunner(
            database: database,
            payloadResolver: FakeCloudKitPayloadResolver(payloads: [:]),
            transport: transport,
            incomingRecordApplier: CloudKitLocalRecordApplier(database: database),
            now: { downloadedAt },
            retryDelay: 90
        )

        let summary = await runner.pullOnce(resultsLimit: 10)

        XCTAssertEqual(summary.failed, 0)
        XCTAssertEqual(summary.appliedUpserts, 2)
        XCTAssertEqual(transport.fetchRecordRequests, [
            .init(entityType: .moment, entityId: "comment-parent-moment", zoneName: CloudKitSyncDefaults.zoneName)
        ])
        XCTAssertNotNil(try database.fetchPost(id: "comment-parent-moment"))
        let comment = try XCTUnwrap(database.fetchComment(id: "dependent-comment"))
        XCTAssertEqual(comment.postId, "comment-parent-moment")
        XCTAssertEqual(comment.text, "Comment arrived first")
        XCTAssertEqual(try database.fetchCloudKitSyncState(scope: CloudKitSyncDefaults.zoneName)?.serverChangeTokenData, nextToken)
    }

    func testPullOnceAppliesRemoteMomentDeleteToLocalDatabaseWithoutOutbox() async throws {
        let database = try LocalDatabase.openForTesting(url: temporaryRoot.appending(path: "pull-local-moment-delete.sqlite"))
        let previousToken = Data([17])
        let nextToken = Data([18])
        let createdAt = Date(timeIntervalSince1970: 6_300)
        let deletedAt = createdAt.addingTimeInterval(90)
        try database.upsertCloudKitSyncState(.init(
            scope: CloudKitSyncDefaults.zoneName,
            serverChangeTokenData: previousToken,
            lastAccountStatus: "available",
            lastSyncStartedAt: nil,
            lastSyncFinishedAt: nil,
            lastErrorCode: nil,
            updatedAt: createdAt
        ))
        try database.insert(TimelinePost(
            id: "remote-moment-1",
            text: "Will be deleted",
            isFavorite: false,
            isPinned: false,
            pinnedAt: nil,
            aiTagProcessedAt: nil,
            tagsUserEditedAt: nil,
            occurredAt: createdAt,
            localCreatedAt: createdAt,
            localUpdatedAt: createdAt,
            localEditedAt: nil,
            serverVersion: nil,
            syncStatus: "synced",
            deletedAt: nil
        ))
        try database.upsertCloudKitRecordState(.init(
            entityType: .moment,
            entityId: "remote-moment-1",
            recordChangeTag: "remote-tag",
            lastKnownRecordJson: #"{"text":"Will be deleted"}"#,
            lastMappedAt: createdAt,
            lastDownloadedAt: createdAt
        ))
        let deletedRecord = CloudKitDeletedRecordIdentity(
            entityType: .moment,
            entityId: "remote-moment-1",
            recordType: CloudKitSyncEntityType.moment.recordType,
            recordName: CloudKitSyncEntityType.moment.recordName(entityId: "remote-moment-1"),
            zoneName: CloudKitSyncDefaults.zoneName
        )
        let transport = FakeCloudKitSyncTransport()
        transport.downloadedChanges = .init(
            modifiedPayloads: [],
            deletedRecords: [deletedRecord],
            serverChangeTokenData: nextToken,
            moreComing: false
        )
        let runner = CloudKitSyncRunner(
            database: database,
            payloadResolver: FakeCloudKitPayloadResolver(payloads: [:]),
            transport: transport,
            incomingRecordApplier: CloudKitLocalRecordApplier(database: database),
            now: { deletedAt },
            retryDelay: 90
        )

        let summary = await runner.pullOnce(resultsLimit: 10)

        XCTAssertEqual(summary.failed, 0)
        XCTAssertEqual(summary.appliedDeletes, 1)
        let post = try XCTUnwrap(database.fetchPost(id: "remote-moment-1"))
        XCTAssertEqual(post.deletedAt, deletedAt)
        XCTAssertEqual(post.localUpdatedAt, deletedAt)
        XCTAssertEqual(post.syncStatus, "synced")
        XCTAssertEqual(try database.count("SELECT COUNT(*) FROM outbox_operations"), 0)
        XCTAssertEqual(try database.fetchCloudKitSyncState(scope: CloudKitSyncDefaults.zoneName)?.serverChangeTokenData, nextToken)
    }

    func testPullOnceAppliesRemoteCommentDeleteToLocalDatabaseWithoutOutbox() async throws {
        let database = try LocalDatabase.openForTesting(url: temporaryRoot.appending(path: "pull-local-comment-delete.sqlite"))
        let previousToken = Data([19])
        let nextToken = Data([20])
        let createdAt = Date(timeIntervalSince1970: 6_500)
        let deletedAt = createdAt.addingTimeInterval(120)
        try database.upsertCloudKitSyncState(.init(
            scope: CloudKitSyncDefaults.zoneName,
            serverChangeTokenData: previousToken,
            lastAccountStatus: "available",
            lastSyncStartedAt: nil,
            lastSyncFinishedAt: nil,
            lastErrorCode: nil,
            updatedAt: createdAt
        ))
        try database.insert(TimelinePost(
            id: "remote-moment-1",
            text: "Existing post",
            isFavorite: false,
            isPinned: false,
            pinnedAt: nil,
            aiTagProcessedAt: nil,
            tagsUserEditedAt: nil,
            occurredAt: createdAt,
            localCreatedAt: createdAt,
            localUpdatedAt: createdAt,
            localEditedAt: nil,
            serverVersion: nil,
            syncStatus: "synced",
            deletedAt: nil
        ))
        try database.insert(TimelineComment(
            id: "remote-comment-1",
            postId: "remote-moment-1",
            text: "Will be deleted",
            createdAt: createdAt,
            updatedAt: createdAt,
            serverVersion: nil,
            deletedAt: nil
        ))
        try database.upsertCloudKitRecordState(.init(
            entityType: .comment,
            entityId: "remote-comment-1",
            recordChangeTag: "remote-tag",
            lastKnownRecordJson: #"{"text":"Will be deleted"}"#,
            lastMappedAt: createdAt,
            lastDownloadedAt: createdAt
        ))
        let deletedRecord = CloudKitDeletedRecordIdentity(
            entityType: .comment,
            entityId: "remote-comment-1",
            recordType: CloudKitSyncEntityType.comment.recordType,
            recordName: CloudKitSyncEntityType.comment.recordName(entityId: "remote-comment-1"),
            zoneName: CloudKitSyncDefaults.zoneName
        )
        let transport = FakeCloudKitSyncTransport()
        transport.downloadedChanges = .init(
            modifiedPayloads: [],
            deletedRecords: [deletedRecord],
            serverChangeTokenData: nextToken,
            moreComing: false
        )
        let runner = CloudKitSyncRunner(
            database: database,
            payloadResolver: FakeCloudKitPayloadResolver(payloads: [:]),
            transport: transport,
            incomingRecordApplier: CloudKitLocalRecordApplier(database: database),
            now: { deletedAt },
            retryDelay: 90
        )

        let summary = await runner.pullOnce(resultsLimit: 10)

        XCTAssertEqual(summary.failed, 0)
        XCTAssertEqual(summary.appliedDeletes, 1)
        let comment = try XCTUnwrap(database.fetchComment(id: "remote-comment-1"))
        XCTAssertEqual(comment.deletedAt, deletedAt)
        XCTAssertEqual(comment.updatedAt, deletedAt)
        XCTAssertEqual(
            try database.count("SELECT COUNT(*) FROM local_comments WHERE id = 'remote-comment-1' AND syncStatus = 'synced'"),
            1
        )
        XCTAssertEqual(try database.count("SELECT COUNT(*) FROM outbox_operations"), 0)
        XCTAssertEqual(try database.fetchCloudKitSyncState(scope: CloudKitSyncDefaults.zoneName)?.serverChangeTokenData, nextToken)
    }

    func testPullOnceAppliesRemoteMediaMetadataPayloadToLocalDatabaseWithoutOutbox() async throws {
        let database = try LocalDatabase.openForTesting(url: temporaryRoot.appending(path: "pull-local-media-metadata.sqlite"))
        let previousToken = Data([25])
        let nextToken = Data([26])
        let createdAt = Date(timeIntervalSince1970: 7_200)
        let updatedAt = createdAt.addingTimeInterval(45)
        let downloadedAt = updatedAt.addingTimeInterval(30)
        try database.upsertCloudKitSyncState(.init(
            scope: CloudKitSyncDefaults.zoneName,
            serverChangeTokenData: previousToken,
            lastAccountStatus: "available",
            lastSyncStartedAt: nil,
            lastSyncFinishedAt: nil,
            lastErrorCode: nil,
            updatedAt: createdAt
        ))
        try database.insert(TimelinePost(
            id: "remote-moment-1",
            text: "Existing post",
            isFavorite: false,
            isPinned: false,
            pinnedAt: nil,
            aiTagProcessedAt: nil,
            tagsUserEditedAt: nil,
            occurredAt: createdAt,
            localCreatedAt: createdAt,
            localUpdatedAt: createdAt,
            localEditedAt: nil,
            serverVersion: nil,
            syncStatus: "synced",
            deletedAt: nil
        ))
        let mediaPayload = CloudKitRecordPayload(
            entityType: .media,
            entityId: "media-cloudkit",
            fields: [
                "postId": .string("remote-moment-1"),
                "kind": .string("audio"),
                "originalPreserved": .bool(true),
                "mimeType": .string("audio/mp4"),
                "durationSeconds": .double(38.5),
                "sortOrder": .int(2),
                "checksum": .string("sha256:cloudkit-media"),
                "createdAt": .date(createdAt),
                "updatedAt": .date(updatedAt)
            ]
        )
        let transport = FakeCloudKitSyncTransport()
        transport.downloadedChanges = .init(
            modifiedPayloads: [mediaPayload],
            deletedRecords: [],
            serverChangeTokenData: nextToken,
            moreComing: false
        )
        let runner = CloudKitSyncRunner(
            database: database,
            payloadResolver: FakeCloudKitPayloadResolver(payloads: [:]),
            transport: transport,
            incomingRecordApplier: CloudKitLocalRecordApplier(database: database),
            now: { downloadedAt },
            retryDelay: 90
        )

        let summary = await runner.pullOnce(resultsLimit: 10)

        XCTAssertEqual(summary.failed, 0)
        XCTAssertEqual(summary.appliedUpserts, 1)
        let media = try XCTUnwrap(database.fetchMedia(id: "media-cloudkit"))
        XCTAssertEqual(media.postId, "remote-moment-1")
        XCTAssertEqual(media.kind, "audio")
        XCTAssertEqual(media.localCompressedPath, "")
        XCTAssertNil(media.localOriginalStagingPath)
        XCTAssertNil(media.localThumbnailPath)
        XCTAssertNil(media.remoteCompressedPath)
        XCTAssertNil(media.remoteOriginalPath)
        XCTAssertNil(media.remoteThumbnailPath)
        XCTAssertEqual(media.originalPreserved, true)
        XCTAssertEqual(media.uploadStatus, "uploaded")
        XCTAssertEqual(media.mimeType, "audio/mp4")
        XCTAssertEqual(media.durationSeconds, 38.5)
        XCTAssertEqual(media.transcriptionStatus, "not_requested")
        XCTAssertNil(media.transcriptionText)
        XCTAssertNil(media.transcriptionError)
        XCTAssertNil(media.transcriptionUpdatedAt)
        XCTAssertEqual(media.sortOrder, 2)
        XCTAssertEqual(media.checksum, "sha256:cloudkit-media")
        XCTAssertEqual(media.createdAt, createdAt)
        XCTAssertEqual(media.updatedAt, updatedAt)
        XCTAssertEqual(try database.count("SELECT COUNT(*) FROM outbox_operations"), 0)
        XCTAssertEqual(try database.fetchCloudKitSyncState(scope: CloudKitSyncDefaults.zoneName)?.serverChangeTokenData, nextToken)
    }

    func testPullOnceAppliesRemoteMomentBeforeDependentMediaWhenDownloadedOutOfOrder() async throws {
        let database = try LocalDatabase.openForTesting(url: temporaryRoot.appending(path: "pull-local-media-out-of-order.sqlite"))
        let previousToken = Data([26, 1])
        let nextToken = Data([26, 2])
        let createdAt = Date(timeIntervalSince1970: 7_230)
        let updatedAt = createdAt.addingTimeInterval(45)
        let downloadedAt = updatedAt.addingTimeInterval(30)
        try database.upsertCloudKitSyncState(.init(
            scope: CloudKitSyncDefaults.zoneName,
            serverChangeTokenData: previousToken,
            lastAccountStatus: "available",
            lastSyncStartedAt: nil,
            lastSyncFinishedAt: nil,
            lastErrorCode: nil,
            updatedAt: createdAt
        ))
        let momentPayload = CloudKitRecordPayload(
            entityType: .moment,
            entityId: "remote-moment-with-media",
            fields: [
                "text": .string("Remote voice note"),
                "isFavorite": .bool(false),
                "isPinned": .bool(false),
                "occurredAt": .date(createdAt.addingTimeInterval(-120)),
                "localCreatedAt": .date(createdAt),
                "localUpdatedAt": .date(updatedAt)
            ]
        )
        let mediaPayload = CloudKitRecordPayload(
            entityType: .media,
            entityId: "remote-audio-out-of-order",
            fields: [
                "postId": .string("remote-moment-with-media"),
                "kind": .string("audio"),
                "originalPreserved": .bool(false),
                "mimeType": .string("audio/mp4"),
                "durationSeconds": .double(12.5),
                "sortOrder": .int(0),
                "checksum": .string("sha256:out-of-order-audio"),
                "createdAt": .date(createdAt),
                "updatedAt": .date(updatedAt)
            ]
        )
        let transport = FakeCloudKitSyncTransport()
        transport.downloadedChanges = .init(
            modifiedPayloads: [mediaPayload, momentPayload],
            deletedRecords: [],
            serverChangeTokenData: nextToken,
            moreComing: false
        )
        let runner = CloudKitSyncRunner(
            database: database,
            payloadResolver: FakeCloudKitPayloadResolver(payloads: [:]),
            transport: transport,
            incomingRecordApplier: CloudKitLocalRecordApplier(database: database),
            now: { downloadedAt },
            retryDelay: 90
        )

        let summary = await runner.pullOnce(resultsLimit: 10)

        XCTAssertEqual(summary.failed, 0)
        XCTAssertEqual(summary.appliedUpserts, 2)
        let post = try XCTUnwrap(database.fetchPost(id: "remote-moment-with-media"))
        XCTAssertEqual(post.text, "Remote voice note")
        let media = try XCTUnwrap(database.fetchMedia(id: "remote-audio-out-of-order"))
        XCTAssertEqual(media.postId, post.id)
        XCTAssertEqual(media.kind, "audio")
        XCTAssertEqual(media.durationSeconds, 12.5)
        XCTAssertEqual(try database.count("SELECT COUNT(*) FROM outbox_operations"), 0)
        XCTAssertEqual(try database.fetchCloudKitSyncState(scope: CloudKitSyncDefaults.zoneName)?.serverChangeTokenData, nextToken)
    }

    func testPullOnceMaterializesRemoteMediaAssetsAfterMetadataApply() async throws {
        let database = try LocalDatabase.openForTesting(url: temporaryRoot.appending(path: "pull-local-media-assets.sqlite"))
        let previousToken = Data([27])
        let nextToken = Data([28])
        let createdAt = Date(timeIntervalSince1970: 7_260)
        let updatedAt = createdAt.addingTimeInterval(45)
        let downloadedAt = updatedAt.addingTimeInterval(30)
        try database.upsertCloudKitSyncState(.init(
            scope: CloudKitSyncDefaults.zoneName,
            serverChangeTokenData: previousToken,
            lastAccountStatus: "available",
            lastSyncStartedAt: nil,
            lastSyncFinishedAt: nil,
            lastErrorCode: nil,
            updatedAt: createdAt
        ))
        try database.insert(Self.timelinePost(id: "remote-moment-asset", now: createdAt))
        let compressedURL = temporaryRoot.appending(path: "downloaded-compressed.jpg")
        let thumbnailURL = temporaryRoot.appending(path: "downloaded-thumbnail.jpg")
        let originalURL = temporaryRoot.appending(path: "downloaded-original.heic")
        let compressedData = Data([0x21, 0x22, 0x23])
        let thumbnailData = Data([0x31])
        let originalData = Data([0x41, 0x42])
        try compressedData.write(to: compressedURL)
        try thumbnailData.write(to: thumbnailURL)
        try originalData.write(to: originalURL)
        let mediaPayload = CloudKitRecordPayload(
            entityType: .media,
            entityId: "media-cloudkit-assets",
            fields: [
                "postId": .string("remote-moment-asset"),
                "kind": .string("image"),
                "originalPreserved": .bool(true),
                "mimeType": .string("image/heic"),
                "sortOrder": .int(1),
                "checksum": .string("sha256:remote-media"),
                "createdAt": .date(createdAt),
                "updatedAt": .date(updatedAt)
            ]
        )
        let transport = FakeCloudKitSyncTransport()
        transport.downloadedChanges = .init(
            modifiedPayloads: [mediaPayload],
            modifiedAssetRecords: [
                .init(
                    payload: mediaPayload,
                    assetFields: [
                        .init(fieldName: "compressedAsset", fileURL: compressedURL),
                        .init(fieldName: "thumbnailAsset", fileURL: thumbnailURL),
                        .init(fieldName: "originalAsset", fileURL: originalURL)
                    ]
                )
            ],
            deletedRecords: [],
            serverChangeTokenData: nextToken,
            moreComing: false
        )
        let runner = CloudKitSyncRunner(
            database: database,
            payloadResolver: FakeCloudKitPayloadResolver(payloads: [:]),
            transport: transport,
            incomingRecordApplier: CloudKitLocalRecordApplier(database: database),
            now: { downloadedAt },
            retryDelay: 90
        )
        defer {
            if let media = try? database.fetchMedia(id: "media-cloudkit-assets") {
                if !media.localCompressedPath.isEmpty {
                    try? FileManager.default.removeItem(atPath: media.localCompressedPath)
                }
                if let thumbnailPath = media.localThumbnailPath, !thumbnailPath.isEmpty {
                    try? FileManager.default.removeItem(atPath: thumbnailPath)
                }
                if let originalPath = media.localOriginalStagingPath, !originalPath.isEmpty {
                    try? FileManager.default.removeItem(atPath: originalPath)
                }
            }
        }

        let summary = await runner.pullOnce(resultsLimit: 10)

        XCTAssertEqual(summary.failed, 0)
        XCTAssertEqual(summary.appliedUpserts, 1)
        let media = try XCTUnwrap(database.fetchMedia(id: "media-cloudkit-assets"))
        XCTAssertEqual(media.postId, "remote-moment-asset")
        XCTAssertFalse(media.localCompressedPath.isEmpty)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: media.localCompressedPath)), compressedData)
        let thumbnailPath = try XCTUnwrap(media.localThumbnailPath)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: thumbnailPath)), thumbnailData)
        let originalPath = try XCTUnwrap(media.localOriginalStagingPath)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: originalPath)), originalData)
        XCTAssertEqual(try database.count("SELECT COUNT(*) FROM outbox_operations"), 0)
        XCTAssertEqual(try database.fetchCloudKitSyncState(scope: CloudKitSyncDefaults.zoneName)?.serverChangeTokenData, nextToken)
    }

    func testPullOnceAppliesRemoteMediaMetadataDeleteToLocalDatabaseWithoutOutbox() async throws {
        let database = try LocalDatabase.openForTesting(url: temporaryRoot.appending(path: "pull-local-media-metadata-delete.sqlite"))
        let previousToken = Data([27])
        let nextToken = Data([28])
        let createdAt = Date(timeIntervalSince1970: 7_300)
        let deletedAt = createdAt.addingTimeInterval(180)
        try database.upsertCloudKitSyncState(.init(
            scope: CloudKitSyncDefaults.zoneName,
            serverChangeTokenData: previousToken,
            lastAccountStatus: "available",
            lastSyncStartedAt: nil,
            lastSyncFinishedAt: nil,
            lastErrorCode: nil,
            updatedAt: createdAt
        ))
        try database.insert(TimelinePost(
            id: "remote-moment-1",
            text: "Existing post",
            isFavorite: false,
            isPinned: false,
            pinnedAt: nil,
            aiTagProcessedAt: nil,
            tagsUserEditedAt: nil,
            occurredAt: createdAt,
            localCreatedAt: createdAt,
            localUpdatedAt: createdAt,
            localEditedAt: nil,
            serverVersion: nil,
            syncStatus: "synced",
            deletedAt: nil
        ))
        try database.insert(TimelineMedia(
            id: "media-cloudkit",
            postId: "remote-moment-1",
            kind: "audio",
            localCompressedPath: "",
            localOriginalStagingPath: nil,
            localThumbnailPath: nil,
            remoteCompressedPath: nil,
            remoteOriginalPath: nil,
            remoteThumbnailPath: nil,
            originalPreserved: true,
            uploadStatus: "uploaded",
            mimeType: "audio/mp4",
            durationSeconds: 38.5,
            transcriptionText: nil,
            transcriptionStatus: "not_requested",
            transcriptionError: nil,
            transcriptionUpdatedAt: nil,
            sortOrder: 0,
            checksum: "sha256:cloudkit-media",
            createdAt: createdAt,
            updatedAt: createdAt
        ))
        try database.upsertCloudKitRecordState(.init(
            entityType: .media,
            entityId: "media-cloudkit",
            recordChangeTag: "remote-tag",
            lastKnownRecordJson: #"{"kind":"audio"}"#,
            lastMappedAt: createdAt,
            lastDownloadedAt: createdAt
        ))
        let deletedRecord = CloudKitDeletedRecordIdentity(
            entityType: .media,
            entityId: "media-cloudkit",
            recordType: CloudKitSyncEntityType.media.recordType,
            recordName: CloudKitSyncEntityType.media.recordName(entityId: "media-cloudkit"),
            zoneName: CloudKitSyncDefaults.zoneName
        )
        let transport = FakeCloudKitSyncTransport()
        transport.downloadedChanges = .init(
            modifiedPayloads: [],
            deletedRecords: [deletedRecord],
            serverChangeTokenData: nextToken,
            moreComing: false
        )
        let runner = CloudKitSyncRunner(
            database: database,
            payloadResolver: FakeCloudKitPayloadResolver(payloads: [:]),
            transport: transport,
            incomingRecordApplier: CloudKitLocalRecordApplier(database: database),
            now: { deletedAt },
            retryDelay: 90
        )

        let summary = await runner.pullOnce(resultsLimit: 10)

        XCTAssertEqual(summary.failed, 0)
        XCTAssertEqual(summary.appliedDeletes, 1)
        XCTAssertTrue(try database.fetchMedia(postId: "remote-moment-1").isEmpty)
        XCTAssertEqual(
            try database.count("SELECT COUNT(*) FROM local_media WHERE id = 'media-cloudkit' AND deletedAt IS NOT NULL AND uploadStatus = 'deleted'"),
            1
        )
        XCTAssertEqual(try database.count("SELECT COUNT(*) FROM outbox_operations"), 0)
        XCTAssertEqual(try database.fetchCloudKitSyncState(scope: CloudKitSyncDefaults.zoneName)?.serverChangeTokenData, nextToken)
    }

    func testPullOnceAppliesRemoteCheckInMetadataPayloadsToLocalDatabaseWithoutOutbox() async throws {
        let database = try LocalDatabase.openForTesting(url: temporaryRoot.appending(path: "pull-local-checkin-metadata.sqlite"))
        let previousToken = Data([29])
        let nextToken = Data([30])
        let createdAt = Date(timeIntervalSince1970: 7_500)
        let occurredAt = createdAt.addingTimeInterval(3_600)
        let updatedAt = occurredAt.addingTimeInterval(90)
        let downloadedAt = updatedAt.addingTimeInterval(45)
        try database.upsertCloudKitSyncState(.init(
            scope: CloudKitSyncDefaults.zoneName,
            serverChangeTokenData: previousToken,
            lastAccountStatus: "available",
            lastSyncStartedAt: nil,
            lastSyncFinishedAt: nil,
            lastErrorCode: nil,
            updatedAt: createdAt
        ))
        try database.upsertTag(TimelineTag(
            id: "tag-hydration",
            type: "topic",
            name: "Hydration",
            normalizedName: "hydration",
            colorHex: nil,
            isDefault: false,
            isArchived: false,
            aiUsableAsPrimary: false,
            createdAt: createdAt,
            updatedAt: createdAt,
            archivedAt: nil,
            areaId: TopicTagArea.healthFitness.rawValue
        ))
        let itemPayload = CloudKitRecordPayload(
            entityType: .checkInItem,
            entityId: "checkin-item-cloudkit",
            fields: [
                "name": .string("Hydration"),
                "symbolName": .string("drop"),
                "colorHex": .string("#4FA3FF"),
                "recordMode": .string(CheckInRecordMode.multiplePerDay.rawValue),
                "timeVisualization": .string(CheckInTimeVisualization.timeHeatmap.rawValue),
                "dayStartHour": .int(6),
                "activeWeekdays": .stringList(["2", "3", "4", "5", "6"]),
                "sortOrder": .int(4),
                "defaultShowInTimeline": .bool(false),
                "tagId": .string("tag-hydration"),
                "createdAt": .date(createdAt),
                "updatedAt": .date(updatedAt)
            ]
        )
        let entryPayload = CloudKitRecordPayload(
            entityType: .checkInEntry,
            entityId: "checkin-entry-cloudkit",
            fields: [
                "itemId": .string("checkin-item-cloudkit"),
                "occurredAt": .date(occurredAt),
                "note": .string("Two glasses before lunch"),
                "showInTimeline": .bool(true),
                "createdAt": .date(createdAt.addingTimeInterval(5)),
                "updatedAt": .date(updatedAt)
            ]
        )
        let mediaPayload = CloudKitRecordPayload(
            entityType: .checkInMedia,
            entityId: "checkin-media-cloudkit",
            fields: [
                "entryId": .string("checkin-entry-cloudkit"),
                "kind": .string("image"),
                "mimeType": .string("image/jpeg"),
                "durationSeconds": .double(0),
                "sortOrder": .int(1),
                "checksum": .string("sha256:checkin-media"),
                "createdAt": .date(createdAt.addingTimeInterval(10)),
                "updatedAt": .date(updatedAt)
            ]
        )
        let transport = FakeCloudKitSyncTransport()
        transport.downloadedChanges = .init(
            modifiedPayloads: [itemPayload, entryPayload, mediaPayload],
            deletedRecords: [],
            serverChangeTokenData: nextToken,
            moreComing: false
        )
        let runner = CloudKitSyncRunner(
            database: database,
            payloadResolver: FakeCloudKitPayloadResolver(payloads: [:]),
            transport: transport,
            incomingRecordApplier: CloudKitLocalRecordApplier(database: database),
            now: { downloadedAt },
            retryDelay: 90
        )

        let summary = await runner.pullOnce(resultsLimit: 10)

        XCTAssertEqual(summary.failed, 0)
        XCTAssertEqual(summary.appliedUpserts, 3)
        let item = try XCTUnwrap(database.fetchCheckInItem(id: "checkin-item-cloudkit"))
        XCTAssertEqual(item.name, "Hydration")
        XCTAssertEqual(item.symbolName, "drop")
        XCTAssertEqual(item.colorHex, "#4FA3FF")
        XCTAssertEqual(item.recordMode, .multiplePerDay)
        XCTAssertEqual(item.timeVisualization, .timeHeatmap)
        XCTAssertEqual(item.dayStartHour, 6)
        XCTAssertEqual(item.activeWeekdays, [2, 3, 4, 5, 6])
        XCTAssertEqual(item.sortOrder, 4)
        XCTAssertFalse(item.defaultShowInTimeline)
        XCTAssertEqual(item.tagId, "tag-hydration")
        XCTAssertEqual(item.createdAt, createdAt)
        XCTAssertEqual(item.updatedAt, updatedAt)
        XCTAssertEqual(item.syncStatus, "synced")
        XCTAssertNil(item.deletedAt)

        let entry = try XCTUnwrap(database.fetchCheckInEntry(id: "checkin-entry-cloudkit"))
        XCTAssertEqual(entry.itemId, item.id)
        XCTAssertEqual(entry.occurredAt, occurredAt)
        XCTAssertEqual(entry.note, "Two glasses before lunch")
        XCTAssertTrue(entry.showInTimeline)
        XCTAssertEqual(entry.syncStatus, "synced")
        XCTAssertNil(entry.deletedAt)

        let media = try XCTUnwrap(database.fetchCheckInMedia(id: "checkin-media-cloudkit"))
        XCTAssertEqual(media.entryId, entry.id)
        XCTAssertEqual(media.kind, "image")
        XCTAssertEqual(media.localCompressedPath, "")
        XCTAssertNil(media.remoteCompressedPath)
        XCTAssertEqual(media.uploadStatus, "uploaded")
        XCTAssertNil(media.uploadError)
        XCTAssertEqual(media.mimeType, "image/jpeg")
        XCTAssertEqual(media.durationSeconds, 0)
        XCTAssertNil(media.transcriptionText)
        XCTAssertEqual(media.transcriptionStatus, "not_requested")
        XCTAssertNil(media.transcriptionError)
        XCTAssertNil(media.transcriptionUpdatedAt)
        XCTAssertEqual(media.sortOrder, 1)
        XCTAssertEqual(media.checksum, "sha256:checkin-media")
        XCTAssertEqual(media.createdAt, createdAt.addingTimeInterval(10))
        XCTAssertEqual(media.updatedAt, updatedAt)
        XCTAssertNil(media.deletedAt)
        XCTAssertEqual(try database.count("SELECT COUNT(*) FROM outbox_operations"), 0)
        XCTAssertEqual(try database.fetchCloudKitSyncState(scope: CloudKitSyncDefaults.zoneName)?.serverChangeTokenData, nextToken)
    }

    func testPullOnceFetchesMissingCheckInParentBeforeApplyingDependentEntry() async throws {
        let database = try LocalDatabase.openForTesting(url: temporaryRoot.appending(path: "pull-missing-checkin-parent.sqlite"))
        let previousToken = Data([30])
        let nextToken = Data([31])
        let createdAt = Date(timeIntervalSince1970: 7_620)
        let occurredAt = createdAt.addingTimeInterval(3_600)
        let updatedAt = occurredAt.addingTimeInterval(90)
        let downloadedAt = updatedAt.addingTimeInterval(45)
        try database.upsertCloudKitSyncState(.init(
            scope: CloudKitSyncDefaults.zoneName,
            serverChangeTokenData: previousToken,
            lastAccountStatus: "available",
            lastSyncStartedAt: nil,
            lastSyncFinishedAt: nil,
            lastErrorCode: nil,
            updatedAt: createdAt
        ))
        let itemPayload = CloudKitRecordPayload(
            entityType: .checkInItem,
            entityId: "checkin-item-cloudkit",
            fields: [
                "name": .string("Hydration"),
                "symbolName": .string("drop"),
                "colorHex": .string("#4FA3FF"),
                "recordMode": .string(CheckInRecordMode.multiplePerDay.rawValue),
                "timeVisualization": .string(CheckInTimeVisualization.timeHeatmap.rawValue),
                "dayStartHour": .int(6),
                "activeWeekdays": .stringList(["2", "3", "4", "5", "6"]),
                "sortOrder": .int(4),
                "defaultShowInTimeline": .bool(false),
                "createdAt": .date(createdAt),
                "updatedAt": .date(updatedAt)
            ]
        )
        let entryPayload = CloudKitRecordPayload(
            entityType: .checkInEntry,
            entityId: "checkin-entry-cloudkit",
            fields: [
                "itemId": .string("checkin-item-cloudkit"),
                "occurredAt": .date(occurredAt),
                "note": .string("Two glasses before lunch"),
                "showInTimeline": .bool(true),
                "createdAt": .date(createdAt.addingTimeInterval(5)),
                "updatedAt": .date(updatedAt)
            ]
        )
        let transport = FakeCloudKitSyncTransport()
        transport.downloadedChanges = .init(
            modifiedPayloads: [entryPayload],
            deletedRecords: [],
            serverChangeTokenData: nextToken,
            moreComing: false
        )
        transport.fetchRecordPayloads = [
            CloudKitSyncEntityType.checkInItem.localRecordStateId(entityId: "checkin-item-cloudkit"): itemPayload
        ]
        let runner = CloudKitSyncRunner(
            database: database,
            payloadResolver: FakeCloudKitPayloadResolver(payloads: [:]),
            transport: transport,
            incomingRecordApplier: CloudKitLocalRecordApplier(database: database),
            now: { downloadedAt },
            retryDelay: 90
        )

        let summary = await runner.pullOnce(resultsLimit: 10)

        XCTAssertEqual(summary.failed, 0)
        XCTAssertEqual(summary.appliedUpserts, 2)
        XCTAssertEqual(transport.fetchRecordRequests, [
            .init(entityType: .checkInItem, entityId: "checkin-item-cloudkit", zoneName: CloudKitSyncDefaults.zoneName)
        ])
        XCTAssertNotNil(try database.fetchCheckInItem(id: "checkin-item-cloudkit"))
        XCTAssertNotNil(try database.fetchCheckInEntry(id: "checkin-entry-cloudkit"))
        XCTAssertEqual(try database.count("SELECT COUNT(*) FROM outbox_operations"), 0)
        XCTAssertEqual(try database.fetchCloudKitSyncState(scope: CloudKitSyncDefaults.zoneName)?.serverChangeTokenData, nextToken)
    }

    func testPullOnceMaterializesRemoteCheckInMediaAssetAfterMetadataApply() async throws {
        let database = try LocalDatabase.openForTesting(url: temporaryRoot.appending(path: "pull-local-checkin-media-assets.sqlite"))
        let previousToken = Data([30])
        let nextToken = Data([31])
        let createdAt = Date(timeIntervalSince1970: 7_520)
        let updatedAt = createdAt.addingTimeInterval(45)
        let downloadedAt = updatedAt.addingTimeInterval(30)
        try database.upsertCloudKitSyncState(.init(
            scope: CloudKitSyncDefaults.zoneName,
            serverChangeTokenData: previousToken,
            lastAccountStatus: "available",
            lastSyncStartedAt: nil,
            lastSyncFinishedAt: nil,
            lastErrorCode: nil,
            updatedAt: createdAt
        ))
        try database.upsertCheckInItemOnly(CheckInItem(
            id: "checkin-item-asset",
            name: "Hydration",
            symbolName: "drop",
            colorHex: "#4FA3FF",
            recordMode: .multiplePerDay,
            timeVisualization: .timeHeatmap,
            dayStartHour: 6,
            activeWeekdays: [2, 3, 4, 5, 6],
            sortOrder: 4,
            defaultShowInTimeline: false,
            tagId: nil,
            createdAt: createdAt,
            updatedAt: createdAt,
            archivedAt: nil,
            deletedAt: nil,
            syncStatus: "synced"
        ))
        try database.upsertCheckInEntryOnly(CheckInEntry(
            id: "checkin-entry-asset",
            itemId: "checkin-item-asset",
            occurredAt: createdAt.addingTimeInterval(3_600),
            note: "Two glasses before lunch",
            showInTimeline: true,
            createdAt: createdAt,
            updatedAt: createdAt,
            deletedAt: nil,
            syncStatus: "synced"
        ))
        let compressedURL = temporaryRoot.appending(path: "downloaded-checkin-compressed.jpg")
        let compressedData = Data([0x51, 0x52, 0x53])
        try compressedData.write(to: compressedURL)
        let mediaPayload = CloudKitRecordPayload(
            entityType: .checkInMedia,
            entityId: "checkin-media-cloudkit-assets",
            fields: [
                "entryId": .string("checkin-entry-asset"),
                "kind": .string("image"),
                "mimeType": .string("image/jpeg"),
                "durationSeconds": .double(0),
                "sortOrder": .int(1),
                "checksum": .string("sha256:checkin-media-asset"),
                "createdAt": .date(createdAt.addingTimeInterval(10)),
                "updatedAt": .date(updatedAt)
            ]
        )
        let transport = FakeCloudKitSyncTransport()
        transport.downloadedChanges = .init(
            modifiedPayloads: [mediaPayload],
            modifiedAssetRecords: [
                .init(
                    payload: mediaPayload,
                    assetFields: [.init(fieldName: "compressedAsset", fileURL: compressedURL)]
                )
            ],
            deletedRecords: [],
            serverChangeTokenData: nextToken,
            moreComing: false
        )
        let runner = CloudKitSyncRunner(
            database: database,
            payloadResolver: FakeCloudKitPayloadResolver(payloads: [:]),
            transport: transport,
            incomingRecordApplier: CloudKitLocalRecordApplier(database: database),
            now: { downloadedAt },
            retryDelay: 90
        )
        defer {
            if let media = try? database.fetchCheckInMedia(id: "checkin-media-cloudkit-assets"),
               !media.localCompressedPath.isEmpty {
                try? FileManager.default.removeItem(atPath: media.localCompressedPath)
            }
        }

        let summary = await runner.pullOnce(resultsLimit: 10)

        XCTAssertEqual(summary.failed, 0)
        XCTAssertEqual(summary.appliedUpserts, 1)
        let media = try XCTUnwrap(database.fetchCheckInMedia(id: "checkin-media-cloudkit-assets"))
        XCTAssertEqual(media.entryId, "checkin-entry-asset")
        XCTAssertFalse(media.localCompressedPath.isEmpty)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: media.localCompressedPath)), compressedData)
        XCTAssertEqual(try database.count("SELECT COUNT(*) FROM outbox_operations"), 0)
        XCTAssertEqual(try database.fetchCloudKitSyncState(scope: CloudKitSyncDefaults.zoneName)?.serverChangeTokenData, nextToken)
    }

    func testPullOnceAppliesRemoteCheckInMetadataDeletesToLocalDatabaseWithoutOutbox() async throws {
        let database = try LocalDatabase.openForTesting(url: temporaryRoot.appending(path: "pull-local-checkin-metadata-deletes.sqlite"))
        let previousToken = Data([31])
        let nextToken = Data([32])
        let createdAt = Date(timeIntervalSince1970: 7_700)
        let deletedAt = createdAt.addingTimeInterval(160)
        try database.upsertCloudKitSyncState(.init(
            scope: CloudKitSyncDefaults.zoneName,
            serverChangeTokenData: previousToken,
            lastAccountStatus: "available",
            lastSyncStartedAt: nil,
            lastSyncFinishedAt: nil,
            lastErrorCode: nil,
            updatedAt: createdAt
        ))
        try database.upsertCheckInItemOnly(CheckInItem(
            id: "checkin-item-cloudkit",
            name: "Hydration",
            symbolName: "drop",
            colorHex: "#4FA3FF",
            recordMode: .multiplePerDay,
            timeVisualization: .timeHeatmap,
            dayStartHour: 6,
            activeWeekdays: [2, 3, 4, 5, 6],
            sortOrder: 4,
            defaultShowInTimeline: false,
            tagId: nil,
            createdAt: createdAt,
            updatedAt: createdAt,
            archivedAt: nil,
            deletedAt: nil,
            syncStatus: "synced"
        ))
        try database.upsertCheckInEntryOnly(CheckInEntry(
            id: "checkin-entry-cloudkit",
            itemId: "checkin-item-cloudkit",
            occurredAt: createdAt.addingTimeInterval(3_600),
            note: "Two glasses before lunch",
            showInTimeline: true,
            createdAt: createdAt,
            updatedAt: createdAt,
            deletedAt: nil,
            syncStatus: "synced"
        ))
        try database.upsertCheckInMediaOnly(CheckInMedia(
            id: "checkin-media-cloudkit",
            entryId: "checkin-entry-cloudkit",
            kind: "image",
            localCompressedPath: "",
            remoteCompressedPath: nil,
            uploadStatus: "uploaded",
            uploadError: nil,
            mimeType: "image/jpeg",
            durationSeconds: nil,
            sortOrder: 0,
            checksum: "sha256:checkin-media",
            createdAt: createdAt,
            updatedAt: createdAt,
            deletedAt: nil
        ))
        let deletedRecords = [
            CloudKitDeletedRecordIdentity(
                entityType: .checkInMedia,
                entityId: "checkin-media-cloudkit",
                recordType: CloudKitSyncEntityType.checkInMedia.recordType,
                recordName: CloudKitSyncEntityType.checkInMedia.recordName(entityId: "checkin-media-cloudkit"),
                zoneName: CloudKitSyncDefaults.zoneName
            ),
            CloudKitDeletedRecordIdentity(
                entityType: .checkInEntry,
                entityId: "checkin-entry-cloudkit",
                recordType: CloudKitSyncEntityType.checkInEntry.recordType,
                recordName: CloudKitSyncEntityType.checkInEntry.recordName(entityId: "checkin-entry-cloudkit"),
                zoneName: CloudKitSyncDefaults.zoneName
            ),
            CloudKitDeletedRecordIdentity(
                entityType: .checkInItem,
                entityId: "checkin-item-cloudkit",
                recordType: CloudKitSyncEntityType.checkInItem.recordType,
                recordName: CloudKitSyncEntityType.checkInItem.recordName(entityId: "checkin-item-cloudkit"),
                zoneName: CloudKitSyncDefaults.zoneName
            )
        ]
        let transport = FakeCloudKitSyncTransport()
        transport.downloadedChanges = .init(
            modifiedPayloads: [],
            deletedRecords: deletedRecords,
            serverChangeTokenData: nextToken,
            moreComing: false
        )
        let runner = CloudKitSyncRunner(
            database: database,
            payloadResolver: FakeCloudKitPayloadResolver(payloads: [:]),
            transport: transport,
            incomingRecordApplier: CloudKitLocalRecordApplier(database: database),
            now: { deletedAt },
            retryDelay: 90
        )

        let summary = await runner.pullOnce(resultsLimit: 10)

        XCTAssertEqual(summary.failed, 0)
        XCTAssertEqual(summary.appliedDeletes, 3)
        let item = try XCTUnwrap(database.fetchCheckInItem(id: "checkin-item-cloudkit"))
        XCTAssertEqual(item.deletedAt, deletedAt)
        XCTAssertEqual(item.updatedAt, deletedAt)
        XCTAssertEqual(item.syncStatus, "synced")
        let entry = try XCTUnwrap(database.fetchCheckInEntry(id: "checkin-entry-cloudkit"))
        XCTAssertEqual(entry.deletedAt, deletedAt)
        XCTAssertEqual(entry.updatedAt, deletedAt)
        XCTAssertEqual(entry.syncStatus, "synced")
        let media = try XCTUnwrap(database.fetchCheckInMedia(id: "checkin-media-cloudkit"))
        XCTAssertEqual(media.deletedAt, deletedAt)
        XCTAssertEqual(media.updatedAt, deletedAt)
        XCTAssertEqual(media.uploadStatus, "deleted")
        XCTAssertNil(media.uploadError)
        XCTAssertEqual(try database.count("SELECT COUNT(*) FROM outbox_operations"), 0)
        XCTAssertEqual(try database.fetchCloudKitSyncState(scope: CloudKitSyncDefaults.zoneName)?.serverChangeTokenData, nextToken)
    }

    func testPullOnceAppliesRemoteAIArtifactPayloadsToLocalDatabaseWithoutOutbox() async throws {
        let database = try LocalDatabase.openForTesting(url: temporaryRoot.appending(path: "pull-local-ai-artifacts.sqlite"))
        let previousToken = Data([33])
        let nextToken = Data([34])
        let createdAt = Date(timeIntervalSince1970: 7_900)
        let updatedAt = createdAt.addingTimeInterval(90)
        let downloadedAt = updatedAt.addingTimeInterval(30)
        try database.upsertCloudKitSyncState(.init(
            scope: CloudKitSyncDefaults.zoneName,
            serverChangeTokenData: previousToken,
            lastAccountStatus: "available",
            lastSyncStartedAt: nil,
            lastSyncFinishedAt: nil,
            lastErrorCode: nil,
            updatedAt: createdAt
        ))
        try database.insert(TimelinePost(
            id: "remote-moment-ai",
            text: "Voice note",
            isFavorite: false,
            isPinned: false,
            pinnedAt: nil,
            aiTagProcessedAt: nil,
            tagsUserEditedAt: nil,
            occurredAt: createdAt,
            localCreatedAt: createdAt,
            localUpdatedAt: createdAt,
            localEditedAt: nil,
            serverVersion: nil,
            syncStatus: "synced",
            deletedAt: nil
        ))
        try database.insert(TimelineMedia(
            id: "remote-media-ai",
            postId: "remote-moment-ai",
            kind: "audio",
            localCompressedPath: "",
            localOriginalStagingPath: nil,
            localThumbnailPath: nil,
            remoteCompressedPath: nil,
            remoteOriginalPath: nil,
            remoteThumbnailPath: nil,
            originalPreserved: false,
            uploadStatus: "uploaded",
            mimeType: "audio/mp4",
            durationSeconds: 58,
            transcriptionText: nil,
            transcriptionStatus: "not_requested",
            transcriptionError: nil,
            transcriptionUpdatedAt: nil,
            sortOrder: 0,
            checksum: "sha256:timeline-ai-media",
            createdAt: createdAt,
            updatedAt: createdAt
        ))
        try database.upsertCheckInItemOnly(CheckInItem(
            id: "checkin-item-ai",
            name: "Workout",
            symbolName: "figure.run",
            colorHex: "#8E8E93",
            recordMode: .multiplePerDay,
            timeVisualization: .none,
            dayStartHour: 0,
            activeWeekdays: [1, 2, 3, 4, 5, 6, 7],
            sortOrder: 1,
            defaultShowInTimeline: false,
            tagId: nil,
            createdAt: createdAt,
            updatedAt: createdAt,
            archivedAt: nil,
            deletedAt: nil,
            syncStatus: "synced"
        ))
        try database.upsertCheckInEntryOnly(CheckInEntry(
            id: "checkin-entry-ai",
            itemId: "checkin-item-ai",
            occurredAt: createdAt.addingTimeInterval(600),
            note: "Tempo run",
            showInTimeline: false,
            createdAt: createdAt,
            updatedAt: createdAt,
            deletedAt: nil,
            syncStatus: "synced"
        ))
        try database.upsertCheckInMediaOnly(CheckInMedia(
            id: "checkin-media-ai",
            entryId: "checkin-entry-ai",
            kind: "audio",
            localCompressedPath: "",
            remoteCompressedPath: nil,
            uploadStatus: "uploaded",
            uploadError: nil,
            mimeType: "audio/mp4",
            durationSeconds: 24,
            sortOrder: 0,
            checksum: "sha256:checkin-ai-media",
            createdAt: createdAt,
            updatedAt: createdAt,
            deletedAt: nil
        ))
        let timelinePayload = CloudKitRecordPayload(
            entityType: .aiSummary,
            entityId: "summary-cloudkit",
            fields: [
                "postId": .string("remote-moment-ai"),
                "mediaId": .string("remote-media-ai"),
                "status": .string("ready"),
                "format": .string("document"),
                "language": .string("zh-Hans"),
                "overview": .string("一次清楚的语音回顾"),
                "keyPoints": .stringList(["确认节奏", "记录下一步"]),
                "sections": .string(#"[{"heading":"Highlights","bullets":["One clear next step"]}]"#),
                "summaryText": .string("summary text"),
                "documentTitle": .string("语音回顾"),
                "oneLiner": .string("把语音整理成可回看的摘要。"),
                "documentBlocks": .string(#"[{"kind":"heading","level":2,"text":"Plan","items":[]},{"kind":"list","level":0,"text":"","items":["A","B"]}]"#),
                "promptVersion": .string("media-summary-v4"),
                "createdAt": .date(createdAt),
                "updatedAt": .date(updatedAt)
            ]
        )
        let checkInPayload = CloudKitRecordPayload(
            entityType: .checkInAISummary,
            entityId: "checkin-summary-cloudkit",
            fields: [
                "entryId": .string("checkin-entry-ai"),
                "mediaId": .string("checkin-media-ai"),
                "status": .string("ready"),
                "format": .string("document"),
                "language": .string("en"),
                "overview": .string("Workout note"),
                "sections": .string(#"[{"heading":"Workout","bullets":["Tempo stayed steady"]}]"#),
                "summaryText": .string("check-in summary text"),
                "documentTitle": .string("Run recap"),
                "oneLiner": .string("A compact workout recap."),
                "documentBlocks": .string(#"[{"kind":"paragraph","level":0,"text":"Keep the same route next time.","items":[]}]"#),
                "promptVersion": .string("checkin-summary-v1"),
                "createdAt": .date(createdAt.addingTimeInterval(5)),
                "updatedAt": .date(updatedAt)
            ]
        )
        let transport = FakeCloudKitSyncTransport()
        transport.downloadedChanges = .init(
            modifiedPayloads: [timelinePayload, checkInPayload],
            deletedRecords: [],
            serverChangeTokenData: nextToken,
            moreComing: false
        )
        let runner = CloudKitSyncRunner(
            database: database,
            payloadResolver: FakeCloudKitPayloadResolver(payloads: [:]),
            transport: transport,
            incomingRecordApplier: CloudKitLocalRecordApplier(database: database),
            now: { downloadedAt },
            retryDelay: 90
        )

        let summary = await runner.pullOnce(resultsLimit: 10)

        XCTAssertEqual(summary.failed, 0)
        XCTAssertEqual(summary.appliedUpserts, 2)
        let timelineSummary = try XCTUnwrap(database.fetchAISummary(id: "summary-cloudkit"))
        XCTAssertEqual(timelineSummary.postId, "remote-moment-ai")
        XCTAssertEqual(timelineSummary.mediaId, "remote-media-ai")
        XCTAssertEqual(timelineSummary.status, "ready")
        XCTAssertEqual(timelineSummary.documentTitle, "语音回顾")
        XCTAssertEqual(timelineSummary.oneLiner, "把语音整理成可回看的摘要。")
        XCTAssertEqual(timelineSummary.keyPoints, ["确认节奏", "记录下一步"])
        XCTAssertEqual(timelineSummary.sections.first?.heading, "Highlights")
        XCTAssertEqual(timelineSummary.documentBlocks.count, 2)
        XCTAssertNil(timelineSummary.provider)
        XCTAssertNil(timelineSummary.model)
        XCTAssertNil(timelineSummary.inputTokenCount)
        XCTAssertNil(timelineSummary.errorCode)

        let checkInSummary = try XCTUnwrap(database.fetchCheckInAISummary(id: "checkin-summary-cloudkit"))
        XCTAssertEqual(checkInSummary.entryId, "checkin-entry-ai")
        XCTAssertEqual(checkInSummary.mediaId, "checkin-media-ai")
        XCTAssertEqual(checkInSummary.status, "ready")
        XCTAssertEqual(checkInSummary.documentTitle, "Run recap")
        XCTAssertEqual(checkInSummary.keyPoints, [])
        XCTAssertEqual(checkInSummary.sections.first?.heading, "Workout")
        XCTAssertEqual(checkInSummary.documentBlocks.first?.text, "Keep the same route next time.")
        XCTAssertNil(checkInSummary.provider)
        XCTAssertNil(checkInSummary.model)
        XCTAssertNil(checkInSummary.totalTokenCount)
        XCTAssertNil(checkInSummary.errorMessage)
        XCTAssertEqual(try database.count("SELECT COUNT(*) FROM outbox_operations"), 0)
        XCTAssertEqual(try database.fetchCloudKitSyncState(scope: CloudKitSyncDefaults.zoneName)?.serverChangeTokenData, nextToken)
    }

    func testPullOnceAppliesRemoteAIArtifactDeletesToLocalDatabaseWithoutOutbox() async throws {
        let database = try LocalDatabase.openForTesting(url: temporaryRoot.appending(path: "pull-local-ai-artifact-deletes.sqlite"))
        let previousToken = Data([35])
        let nextToken = Data([36])
        let createdAt = Date(timeIntervalSince1970: 8_100)
        let deletedAt = createdAt.addingTimeInterval(180)
        try database.upsertCloudKitSyncState(.init(
            scope: CloudKitSyncDefaults.zoneName,
            serverChangeTokenData: previousToken,
            lastAccountStatus: "available",
            lastSyncStartedAt: nil,
            lastSyncFinishedAt: nil,
            lastErrorCode: nil,
            updatedAt: createdAt
        ))
        try database.insert(TimelinePost(
            id: "remote-moment-ai",
            text: "Voice note",
            isFavorite: false,
            isPinned: false,
            pinnedAt: nil,
            aiTagProcessedAt: nil,
            tagsUserEditedAt: nil,
            occurredAt: createdAt,
            localCreatedAt: createdAt,
            localUpdatedAt: createdAt,
            localEditedAt: nil,
            serverVersion: nil,
            syncStatus: "synced",
            deletedAt: nil
        ))
        try database.insert(TimelineMedia(
            id: "remote-media-ai",
            postId: "remote-moment-ai",
            kind: "audio",
            localCompressedPath: "",
            localOriginalStagingPath: nil,
            localThumbnailPath: nil,
            remoteCompressedPath: nil,
            remoteOriginalPath: nil,
            remoteThumbnailPath: nil,
            originalPreserved: false,
            uploadStatus: "uploaded",
            mimeType: "audio/mp4",
            durationSeconds: 58,
            transcriptionText: nil,
            transcriptionStatus: "not_requested",
            transcriptionError: nil,
            transcriptionUpdatedAt: nil,
            sortOrder: 0,
            checksum: "sha256:timeline-ai-media",
            createdAt: createdAt,
            updatedAt: createdAt
        ))
        try database.upsertAISummary(TimelineAISummary(
            id: "summary-cloudkit",
            postId: "remote-moment-ai",
            mediaId: "remote-media-ai",
            status: "ready",
            format: "document",
            language: "zh-Hans",
            overview: "Existing overview",
            keyPoints: ["old"],
            sections: [],
            summaryText: "old text",
            documentTitle: "Old title",
            oneLiner: "Old one liner",
            documentBlocks: [],
            inputTranscriptLength: nil,
            inputDurationSeconds: nil,
            inputTokenCount: nil,
            outputTokenCount: nil,
            totalTokenCount: nil,
            promptVersion: "media-summary-v4",
            provider: nil,
            model: nil,
            errorCode: nil,
            errorMessage: nil,
            createdAt: createdAt,
            updatedAt: createdAt,
            deletedAt: nil
        ))
        try database.upsertCheckInItemOnly(CheckInItem(
            id: "checkin-item-ai",
            name: "Workout",
            symbolName: "figure.run",
            colorHex: "#8E8E93",
            recordMode: .multiplePerDay,
            timeVisualization: .none,
            dayStartHour: 0,
            activeWeekdays: [1, 2, 3, 4, 5, 6, 7],
            sortOrder: 1,
            defaultShowInTimeline: false,
            tagId: nil,
            createdAt: createdAt,
            updatedAt: createdAt,
            archivedAt: nil,
            deletedAt: nil,
            syncStatus: "synced"
        ))
        try database.upsertCheckInEntryOnly(CheckInEntry(
            id: "checkin-entry-ai",
            itemId: "checkin-item-ai",
            occurredAt: createdAt.addingTimeInterval(600),
            note: "Tempo run",
            showInTimeline: false,
            createdAt: createdAt,
            updatedAt: createdAt,
            deletedAt: nil,
            syncStatus: "synced"
        ))
        try database.upsertCheckInMediaOnly(CheckInMedia(
            id: "checkin-media-ai",
            entryId: "checkin-entry-ai",
            kind: "audio",
            localCompressedPath: "",
            remoteCompressedPath: nil,
            uploadStatus: "uploaded",
            uploadError: nil,
            mimeType: "audio/mp4",
            durationSeconds: 24,
            sortOrder: 0,
            checksum: "sha256:checkin-ai-media",
            createdAt: createdAt,
            updatedAt: createdAt,
            deletedAt: nil
        ))
        try database.upsertCheckInAISummary(CheckInAISummary(
            id: "checkin-summary-cloudkit",
            entryId: "checkin-entry-ai",
            mediaId: "checkin-media-ai",
            status: "ready",
            format: "document",
            language: "en",
            overview: "Existing check-in overview",
            keyPoints: ["old"],
            sections: [],
            summaryText: "old text",
            documentTitle: "Old check-in title",
            oneLiner: "Old one liner",
            documentBlocks: [],
            inputTranscriptLength: nil,
            inputDurationSeconds: nil,
            inputTokenCount: nil,
            outputTokenCount: nil,
            totalTokenCount: nil,
            promptVersion: "checkin-summary-v1",
            provider: nil,
            model: nil,
            errorCode: nil,
            errorMessage: nil,
            createdAt: createdAt,
            updatedAt: createdAt,
            deletedAt: nil
        ))
        let deletedRecords = [
            CloudKitDeletedRecordIdentity(
                entityType: .aiSummary,
                entityId: "summary-cloudkit",
                recordType: CloudKitSyncEntityType.aiSummary.recordType,
                recordName: CloudKitSyncEntityType.aiSummary.recordName(entityId: "summary-cloudkit"),
                zoneName: CloudKitSyncDefaults.zoneName
            ),
            CloudKitDeletedRecordIdentity(
                entityType: .checkInAISummary,
                entityId: "checkin-summary-cloudkit",
                recordType: CloudKitSyncEntityType.checkInAISummary.recordType,
                recordName: CloudKitSyncEntityType.checkInAISummary.recordName(entityId: "checkin-summary-cloudkit"),
                zoneName: CloudKitSyncDefaults.zoneName
            )
        ]
        let transport = FakeCloudKitSyncTransport()
        transport.downloadedChanges = .init(
            modifiedPayloads: [],
            deletedRecords: deletedRecords,
            serverChangeTokenData: nextToken,
            moreComing: false
        )
        let runner = CloudKitSyncRunner(
            database: database,
            payloadResolver: FakeCloudKitPayloadResolver(payloads: [:]),
            transport: transport,
            incomingRecordApplier: CloudKitLocalRecordApplier(database: database),
            now: { deletedAt },
            retryDelay: 90
        )

        let summary = await runner.pullOnce(resultsLimit: 10)

        XCTAssertEqual(summary.failed, 0)
        XCTAssertEqual(summary.appliedDeletes, 2)
        let timelineSummary = try XCTUnwrap(database.fetchAISummary(id: "summary-cloudkit"))
        XCTAssertEqual(timelineSummary.status, "deleted")
        XCTAssertEqual(timelineSummary.updatedAt, deletedAt)
        XCTAssertEqual(timelineSummary.deletedAt, deletedAt)
        let checkInSummary = try XCTUnwrap(database.fetchCheckInAISummary(id: "checkin-summary-cloudkit"))
        XCTAssertEqual(checkInSummary.status, "deleted")
        XCTAssertEqual(checkInSummary.updatedAt, deletedAt)
        XCTAssertEqual(checkInSummary.deletedAt, deletedAt)
        XCTAssertEqual(try database.count("SELECT COUNT(*) FROM outbox_operations"), 0)
        XCTAssertEqual(try database.fetchCloudKitSyncState(scope: CloudKitSyncDefaults.zoneName)?.serverChangeTokenData, nextToken)
    }

    func testPullOnceAppliesRemoteTagMetadataPayloadsToLocalDatabaseWithoutOutbox() async throws {
        let database = try LocalDatabase.openForTesting(url: temporaryRoot.appending(path: "pull-local-tag-metadata.sqlite"))
        let previousToken = Data([21])
        let nextToken = Data([22])
        let createdAt = Date(timeIntervalSince1970: 6_900)
        let updatedAt = createdAt.addingTimeInterval(30)
        let downloadedAt = updatedAt.addingTimeInterval(45)
        try database.upsertCloudKitSyncState(.init(
            scope: CloudKitSyncDefaults.zoneName,
            serverChangeTokenData: previousToken,
            lastAccountStatus: "available",
            lastSyncStartedAt: nil,
            lastSyncFinishedAt: nil,
            lastErrorCode: nil,
            updatedAt: createdAt
        ))
        try database.insert(TimelinePost(
            id: "remote-moment-1",
            text: "Existing post",
            isFavorite: false,
            isPinned: false,
            pinnedAt: nil,
            aiTagProcessedAt: nil,
            tagsUserEditedAt: nil,
            occurredAt: createdAt,
            localCreatedAt: createdAt,
            localUpdatedAt: createdAt,
            localEditedAt: nil,
            serverVersion: nil,
            syncStatus: "synced",
            deletedAt: nil
        ))
        let tagPayload = CloudKitRecordPayload(
            entityType: .tag,
            entityId: "topic-cloudkit",
            fields: [
                "type": .string("topic"),
                "name": .string("CloudKit Sync"),
                "normalizedName": .string("cloudkitsync"),
                "isDefault": .bool(false),
                "isArchived": .bool(false),
                "aiUsableAsPrimary": .bool(false),
                "createdAt": .date(createdAt),
                "updatedAt": .date(updatedAt),
                "areaId": .string(TopicTagArea.technology.rawValue)
            ]
        )
        let aliasPayload = CloudKitRecordPayload(
            entityType: .tagAlias,
            entityId: "alias-cloudkit",
            fields: [
                "tagId": .string("topic-cloudkit"),
                "alias": .string("Apple Cloud"),
                "normalizedAlias": .string("applecloud"),
                "createdAt": .date(createdAt.addingTimeInterval(1))
            ]
        )
        let assignmentPayload = CloudKitRecordPayload(
            entityType: .postTag,
            entityId: "assignment-cloudkit",
            fields: [
                "postId": .string("remote-moment-1"),
                "tagId": .string("topic-cloudkit"),
                "role": .string("topic"),
                "source": .string("ai"),
                "confidence": .double(0.84),
                "aiSummaryId": .string("summary-1"),
                "createdAt": .date(createdAt.addingTimeInterval(2)),
                "updatedAt": .date(updatedAt)
            ]
        )
        let transport = FakeCloudKitSyncTransport()
        transport.downloadedChanges = .init(
            modifiedPayloads: [tagPayload, aliasPayload, assignmentPayload],
            deletedRecords: [],
            serverChangeTokenData: nextToken,
            moreComing: false
        )
        let runner = CloudKitSyncRunner(
            database: database,
            payloadResolver: FakeCloudKitPayloadResolver(payloads: [:]),
            transport: transport,
            incomingRecordApplier: CloudKitLocalRecordApplier(database: database),
            now: { downloadedAt },
            retryDelay: 90
        )

        let summary = await runner.pullOnce(resultsLimit: 10)

        XCTAssertEqual(summary.failed, 0)
        XCTAssertEqual(summary.appliedUpserts, 3)
        let tag = try XCTUnwrap(database.fetchTag(id: "topic-cloudkit"))
        XCTAssertEqual(tag.type, "topic")
        XCTAssertEqual(tag.name, "CloudKit Sync")
        XCTAssertEqual(tag.normalizedName, "cloudkitsync")
        XCTAssertEqual(tag.resolvedArea, .technology)
        let alias = try XCTUnwrap(database.fetchTagAlias(id: "alias-cloudkit"))
        XCTAssertEqual(alias.tagId, "topic-cloudkit")
        XCTAssertEqual(alias.alias, "Apple Cloud")
        XCTAssertNil(alias.deletedAt)
        let assignedTag = try XCTUnwrap(database.fetchAssignedTag(id: "assignment-cloudkit"))
        XCTAssertEqual(assignedTag.postId, "remote-moment-1")
        XCTAssertEqual(assignedTag.tagId, "topic-cloudkit")
        XCTAssertEqual(assignedTag.source, "ai")
        XCTAssertEqual(assignedTag.confidence, 0.84)
        XCTAssertEqual(assignedTag.aiSummaryId, "summary-1")
        XCTAssertNil(assignedTag.deletedAt)
        XCTAssertEqual(try database.count("SELECT COUNT(*) FROM outbox_operations"), 0)
        XCTAssertEqual(try database.fetchCloudKitSyncState(scope: CloudKitSyncDefaults.zoneName)?.serverChangeTokenData, nextToken)
    }

    func testPullOnceIgnoresOrphanedTagAssignmentWhenReferencedTagIsUnavailable() async throws {
        let database = try LocalDatabase.openForTesting(url: temporaryRoot.appending(path: "pull-orphan-post-tag.sqlite"))
        let previousToken = Data([23])
        let nextToken = Data([24])
        let createdAt = Date(timeIntervalSince1970: 7_000)
        let updatedAt = createdAt.addingTimeInterval(30)
        let downloadedAt = updatedAt.addingTimeInterval(45)
        try database.upsertCloudKitSyncState(.init(
            scope: CloudKitSyncDefaults.zoneName,
            serverChangeTokenData: previousToken,
            lastAccountStatus: "available",
            lastSyncStartedAt: nil,
            lastSyncFinishedAt: nil,
            lastErrorCode: nil,
            updatedAt: createdAt
        ))
        try database.insert(TimelinePost(
            id: "remote-moment-1",
            text: "Existing post",
            isFavorite: false,
            isPinned: false,
            pinnedAt: nil,
            aiTagProcessedAt: nil,
            tagsUserEditedAt: nil,
            occurredAt: createdAt,
            localCreatedAt: createdAt,
            localUpdatedAt: createdAt,
            localEditedAt: nil,
            serverVersion: nil,
            syncStatus: "synced",
            deletedAt: nil
        ))
        let assignmentPayload = CloudKitRecordPayload(
            entityType: .postTag,
            entityId: "orphan-assignment",
            fields: [
                "postId": .string("remote-moment-1"),
                "tagId": .string("missing-topic"),
                "role": .string("topic"),
                "source": .string("ai"),
                "createdAt": .date(createdAt.addingTimeInterval(2)),
                "updatedAt": .date(updatedAt)
            ]
        )
        let transport = FakeCloudKitSyncTransport()
        transport.downloadedChanges = .init(
            modifiedPayloads: [assignmentPayload],
            deletedRecords: [],
            serverChangeTokenData: nextToken,
            moreComing: false
        )
        let runner = CloudKitSyncRunner(
            database: database,
            payloadResolver: FakeCloudKitPayloadResolver(payloads: [:]),
            transport: transport,
            incomingRecordApplier: CloudKitLocalRecordApplier(database: database),
            now: { downloadedAt },
            retryDelay: 90
        )

        let summary = await runner.pullOnce(resultsLimit: 10)

        XCTAssertEqual(summary.failed, 0)
        XCTAssertEqual(summary.ignored, 1)
        XCTAssertEqual(summary.appliedUpserts, 0)
        XCTAssertEqual(transport.fetchRecordRequests, [
            .init(entityType: .tag, entityId: "missing-topic", zoneName: CloudKitSyncDefaults.zoneName)
        ])
        XCTAssertNil(try database.fetchAssignedTag(id: "orphan-assignment"))
        let syncState = try XCTUnwrap(database.fetchCloudKitSyncState(scope: CloudKitSyncDefaults.zoneName))
        XCTAssertEqual(syncState.serverChangeTokenData, nextToken)
        XCTAssertEqual(syncState.lastSyncFinishedAt, downloadedAt)
        XCTAssertNil(syncState.lastErrorCode)
    }

    func testPullOnceIgnoresOrphanedTimelineAISummaryWhenReferencedMediaIsUnavailable() async throws {
        let database = try LocalDatabase.openForTesting(url: temporaryRoot.appending(path: "pull-orphan-ai-summary.sqlite"))
        let previousToken = Data([28])
        let nextToken = Data([29])
        let createdAt = Date(timeIntervalSince1970: 7_180)
        let updatedAt = createdAt.addingTimeInterval(30)
        let downloadedAt = updatedAt.addingTimeInterval(10)
        try database.upsertCloudKitSyncState(.init(
            scope: CloudKitSyncDefaults.zoneName,
            serverChangeTokenData: previousToken,
            lastAccountStatus: "available",
            lastSyncStartedAt: nil,
            lastSyncFinishedAt: nil,
            lastErrorCode: nil,
            updatedAt: createdAt
        ))
        try database.insert(TimelinePost(
            id: "remote-moment-ai",
            text: "Existing post",
            isFavorite: false,
            isPinned: false,
            pinnedAt: nil,
            aiTagProcessedAt: nil,
            tagsUserEditedAt: nil,
            occurredAt: createdAt,
            localCreatedAt: createdAt,
            localUpdatedAt: createdAt,
            localEditedAt: nil,
            serverVersion: nil,
            syncStatus: "synced",
            deletedAt: nil
        ))
        let summaryPayload = CloudKitRecordPayload(
            entityType: .aiSummary,
            entityId: "orphan-summary",
            fields: [
                "postId": .string("remote-moment-ai"),
                "mediaId": .string("missing-media"),
                "status": .string("ready"),
                "keyPoints": .stringList(["optional summary"]),
                "sections": .string("[]"),
                "documentBlocks": .string("[]"),
                "promptVersion": .string("media-summary-v4"),
                "createdAt": .date(createdAt.addingTimeInterval(2)),
                "updatedAt": .date(updatedAt)
            ]
        )
        let transport = FakeCloudKitSyncTransport()
        transport.downloadedChanges = .init(
            modifiedPayloads: [summaryPayload],
            deletedRecords: [],
            serverChangeTokenData: nextToken,
            moreComing: false
        )
        let runner = CloudKitSyncRunner(
            database: database,
            payloadResolver: FakeCloudKitPayloadResolver(payloads: [:]),
            transport: transport,
            incomingRecordApplier: CloudKitLocalRecordApplier(database: database),
            now: { downloadedAt },
            retryDelay: 90
        )

        let summary = await runner.pullOnce(resultsLimit: 10)

        XCTAssertEqual(summary.failed, 0)
        XCTAssertEqual(summary.ignored, 1)
        XCTAssertEqual(summary.appliedUpserts, 0)
        XCTAssertEqual(transport.fetchRecordRequests, [
            .init(entityType: .media, entityId: "missing-media", zoneName: CloudKitSyncDefaults.zoneName)
        ])
        XCTAssertNil(try database.fetchAISummary(id: "orphan-summary"))
        let syncState = try XCTUnwrap(database.fetchCloudKitSyncState(scope: CloudKitSyncDefaults.zoneName))
        XCTAssertEqual(syncState.serverChangeTokenData, nextToken)
        XCTAssertEqual(syncState.lastSyncFinishedAt, downloadedAt)
        XCTAssertNil(syncState.lastErrorCode)
    }

    func testPullOnceIgnoresTimelineAISummaryWhenFetchedMediaParentCannotBeApplied() async throws {
        let database = try LocalDatabase.openForTesting(url: temporaryRoot.appending(path: "pull-ai-summary-invalid-media-parent.sqlite"))
        let previousToken = Data([30])
        let nextToken = Data([31])
        let createdAt = Date(timeIntervalSince1970: 7_220)
        let updatedAt = createdAt.addingTimeInterval(30)
        let downloadedAt = updatedAt.addingTimeInterval(10)
        try database.upsertCloudKitSyncState(.init(
            scope: CloudKitSyncDefaults.zoneName,
            serverChangeTokenData: previousToken,
            lastAccountStatus: "available",
            lastSyncStartedAt: nil,
            lastSyncFinishedAt: nil,
            lastErrorCode: nil,
            updatedAt: createdAt
        ))
        try database.insert(TimelinePost(
            id: "remote-moment-ai",
            text: "Existing post",
            isFavorite: false,
            isPinned: false,
            pinnedAt: nil,
            aiTagProcessedAt: nil,
            tagsUserEditedAt: nil,
            occurredAt: createdAt,
            localCreatedAt: createdAt,
            localUpdatedAt: createdAt,
            localEditedAt: nil,
            serverVersion: nil,
            syncStatus: "synced",
            deletedAt: nil
        ))
        let summaryPayload = CloudKitRecordPayload(
            entityType: .aiSummary,
            entityId: "summary-with-invalid-parent",
            fields: [
                "postId": .string("remote-moment-ai"),
                "mediaId": .string("missing-media"),
                "status": .string("ready"),
                "keyPoints": .stringList(["optional summary"]),
                "sections": .string("[]"),
                "documentBlocks": .string("[]"),
                "promptVersion": .string("media-summary-v4"),
                "createdAt": .date(createdAt.addingTimeInterval(2)),
                "updatedAt": .date(updatedAt)
            ]
        )
        let mismatchedMediaPayload = CloudKitRecordPayload(
            entityType: .media,
            entityId: "different-media",
            fields: [
                "postId": .string("remote-moment-ai"),
                "kind": .string("audio"),
                "sortOrder": .int(0),
                "createdAt": .date(createdAt),
                "updatedAt": .date(updatedAt)
            ]
        )
        let transport = FakeCloudKitSyncTransport()
        transport.downloadedChanges = .init(
            modifiedPayloads: [summaryPayload],
            deletedRecords: [],
            serverChangeTokenData: nextToken,
            moreComing: false
        )
        transport.fetchRecordPayloads[CloudKitSyncEntityType.media.localRecordStateId(entityId: "missing-media")] = mismatchedMediaPayload
        let runner = CloudKitSyncRunner(
            database: database,
            payloadResolver: FakeCloudKitPayloadResolver(payloads: [:]),
            transport: transport,
            incomingRecordApplier: CloudKitLocalRecordApplier(database: database),
            now: { downloadedAt },
            retryDelay: 90
        )

        let summary = await runner.pullOnce(resultsLimit: 10)

        XCTAssertEqual(summary.failed, 0)
        XCTAssertEqual(summary.ignored, 1)
        XCTAssertEqual(summary.appliedUpserts, 0)
        XCTAssertEqual(transport.fetchRecordRequests, [
            .init(entityType: .media, entityId: "missing-media", zoneName: CloudKitSyncDefaults.zoneName)
        ])
        XCTAssertNil(try database.fetchMedia(id: "missing-media"))
        XCTAssertNil(try database.fetchAISummary(id: "summary-with-invalid-parent"))
        let syncState = try XCTUnwrap(database.fetchCloudKitSyncState(scope: CloudKitSyncDefaults.zoneName))
        XCTAssertEqual(syncState.serverChangeTokenData, nextToken)
        XCTAssertEqual(syncState.lastSyncFinishedAt, downloadedAt)
        XCTAssertNil(syncState.lastErrorCode)
    }

    func testPullOnceAcceptsRemoteTagNumericBooleanFields() async throws {
        let database = try LocalDatabase.openForTesting(url: temporaryRoot.appending(path: "pull-local-tag-numeric-booleans.sqlite"))
        let previousToken = Data([25])
        let nextToken = Data([26])
        let createdAt = Date(timeIntervalSince1970: 7_120)
        let updatedAt = createdAt.addingTimeInterval(30)
        let downloadedAt = updatedAt.addingTimeInterval(10)
        try database.upsertCloudKitSyncState(.init(
            scope: CloudKitSyncDefaults.zoneName,
            serverChangeTokenData: previousToken,
            lastAccountStatus: "available",
            lastSyncStartedAt: nil,
            lastSyncFinishedAt: nil,
            lastErrorCode: nil,
            updatedAt: createdAt
        ))
        let tagPayload = CloudKitRecordPayload(
            entityType: .tag,
            entityId: "topic-cloudkit-numeric",
            fields: [
                "type": .string("topic"),
                "name": .string("CloudKit Numeric"),
                "normalizedName": .string("cloudkitnumeric"),
                "isDefault": .int(0),
                "isArchived": .int(0),
                "aiUsableAsPrimary": .int(0),
                "createdAt": .date(createdAt),
                "updatedAt": .date(updatedAt),
                "areaId": .string(TopicTagArea.technology.rawValue)
            ]
        )
        let transport = FakeCloudKitSyncTransport()
        transport.downloadedChanges = .init(
            modifiedPayloads: [tagPayload],
            deletedRecords: [],
            serverChangeTokenData: nextToken,
            moreComing: false
        )
        let runner = CloudKitSyncRunner(
            database: database,
            payloadResolver: FakeCloudKitPayloadResolver(payloads: [:]),
            transport: transport,
            incomingRecordApplier: CloudKitLocalRecordApplier(database: database),
            now: { downloadedAt },
            retryDelay: 90
        )

        let summary = await runner.pullOnce(resultsLimit: 10)

        XCTAssertEqual(summary.failed, 0)
        XCTAssertEqual(summary.appliedUpserts, 1)
        let tag = try XCTUnwrap(database.fetchTag(id: "topic-cloudkit-numeric"))
        XCTAssertFalse(tag.isDefault)
        XCTAssertFalse(tag.isArchived)
        XCTAssertFalse(tag.aiUsableAsPrimary)
        XCTAssertEqual(try database.fetchCloudKitSyncState(scope: CloudKitSyncDefaults.zoneName)?.serverChangeTokenData, nextToken)
    }

    func testPullOnceAppliesRemoteTagMetadataDeletesToLocalDatabaseWithoutOutbox() async throws {
        let database = try LocalDatabase.openForTesting(url: temporaryRoot.appending(path: "pull-local-tag-metadata-deletes.sqlite"))
        let previousToken = Data([23])
        let nextToken = Data([24])
        let createdAt = Date(timeIntervalSince1970: 7_000)
        let deletedAt = createdAt.addingTimeInterval(120)
        try database.upsertCloudKitSyncState(.init(
            scope: CloudKitSyncDefaults.zoneName,
            serverChangeTokenData: previousToken,
            lastAccountStatus: "available",
            lastSyncStartedAt: nil,
            lastSyncFinishedAt: nil,
            lastErrorCode: nil,
            updatedAt: createdAt
        ))
        try database.insert(TimelinePost(
            id: "remote-moment-1",
            text: "Existing post",
            isFavorite: false,
            isPinned: false,
            pinnedAt: nil,
            aiTagProcessedAt: nil,
            tagsUserEditedAt: nil,
            occurredAt: createdAt,
            localCreatedAt: createdAt,
            localUpdatedAt: createdAt,
            localEditedAt: nil,
            serverVersion: nil,
            syncStatus: "synced",
            deletedAt: nil
        ))
        let hardDeletedTag = TimelineTag(
            id: "topic-deleted",
            type: "topic",
            name: "Deleted Topic",
            normalizedName: "deletedtopic",
            colorHex: nil,
            isDefault: false,
            isArchived: false,
            aiUsableAsPrimary: false,
            createdAt: createdAt,
            updatedAt: createdAt,
            archivedAt: nil,
            areaId: TopicTagArea.technology.rawValue
        )
        let relationTag = TimelineTag(
            id: "topic-relations",
            type: "topic",
            name: "Relations Topic",
            normalizedName: "relationstopic",
            colorHex: nil,
            isDefault: false,
            isArchived: false,
            aiUsableAsPrimary: false,
            createdAt: createdAt,
            updatedAt: createdAt,
            archivedAt: nil,
            areaId: TopicTagArea.life.rawValue
        )
        try database.upsertTag(hardDeletedTag)
        try database.upsertTag(relationTag)
        try database.upsertTagAlias(TimelineTagAlias(
            id: "alias-relations",
            tagId: relationTag.id,
            alias: "Relationship",
            normalizedAlias: "relationship",
            createdAt: createdAt,
            deletedAt: nil
        ))
        try database.upsertAssignedTag(TimelineAssignedTag(
            id: "assignment-relations",
            postId: "remote-moment-1",
            tagId: relationTag.id,
            role: "topic",
            source: "ai",
            confidence: 0.71,
            aiSummaryId: "summary-1",
            createdAt: createdAt,
            updatedAt: createdAt,
            deletedAt: nil,
            tag: relationTag
        ))
        let deletedRecords = [
            CloudKitDeletedRecordIdentity(
                entityType: .tag,
                entityId: hardDeletedTag.id,
                recordType: CloudKitSyncEntityType.tag.recordType,
                recordName: CloudKitSyncEntityType.tag.recordName(entityId: hardDeletedTag.id),
                zoneName: CloudKitSyncDefaults.zoneName
            ),
            CloudKitDeletedRecordIdentity(
                entityType: .tagAlias,
                entityId: "alias-relations",
                recordType: CloudKitSyncEntityType.tagAlias.recordType,
                recordName: CloudKitSyncEntityType.tagAlias.recordName(entityId: "alias-relations"),
                zoneName: CloudKitSyncDefaults.zoneName
            ),
            CloudKitDeletedRecordIdentity(
                entityType: .postTag,
                entityId: "assignment-relations",
                recordType: CloudKitSyncEntityType.postTag.recordType,
                recordName: CloudKitSyncEntityType.postTag.recordName(entityId: "assignment-relations"),
                zoneName: CloudKitSyncDefaults.zoneName
            )
        ]
        let transport = FakeCloudKitSyncTransport()
        transport.downloadedChanges = .init(
            modifiedPayloads: [],
            deletedRecords: deletedRecords,
            serverChangeTokenData: nextToken,
            moreComing: false
        )
        let runner = CloudKitSyncRunner(
            database: database,
            payloadResolver: FakeCloudKitPayloadResolver(payloads: [:]),
            transport: transport,
            incomingRecordApplier: CloudKitLocalRecordApplier(database: database),
            now: { deletedAt },
            retryDelay: 90
        )

        let summary = await runner.pullOnce(resultsLimit: 10)

        XCTAssertEqual(summary.failed, 0)
        XCTAssertEqual(summary.appliedDeletes, 3)
        XCTAssertNil(try database.fetchTag(id: hardDeletedTag.id))
        let alias = try XCTUnwrap(database.fetchTagAlias(id: "alias-relations"))
        XCTAssertEqual(alias.deletedAt, deletedAt)
        let assignedTag = try XCTUnwrap(database.fetchAssignedTag(id: "assignment-relations"))
        XCTAssertEqual(assignedTag.deletedAt, deletedAt)
        XCTAssertEqual(assignedTag.updatedAt, deletedAt)
        XCTAssertEqual(try database.count("SELECT COUNT(*) FROM outbox_operations"), 0)
        XCTAssertEqual(try database.fetchCloudKitSyncState(scope: CloudKitSyncDefaults.zoneName)?.serverChangeTokenData, nextToken)
    }

    func testPullOnceAppliesRemoteWeeklyReviewPayloadsToLocalSettingsWithoutOutbox() async throws {
        let database = try LocalDatabase.openForTesting(url: temporaryRoot.appending(path: "weekly-review-upsert.sqlite"))
        let nextToken = Data([70])
        let downloadedAt = Date(timeIntervalSince1970: 8_700)
        AppSettings.localWeeklyReviews = [
            Self.weeklyReview(id: "existing-review", updatedAt: "2026-06-02T10:20:30Z", deletedAt: nil)
        ]
        let payload = CloudKitRecordMapper.payload(for: Self.weeklyReview(
            id: "remote-review",
            updatedAt: "2026-06-03T10:20:30Z",
            deletedAt: nil
        ))
        let transport = FakeCloudKitSyncTransport()
        transport.downloadedChanges = .init(
            modifiedPayloads: [payload],
            deletedRecords: [],
            serverChangeTokenData: nextToken,
            moreComing: false
        )
        let runner = CloudKitSyncRunner(
            database: database,
            payloadResolver: FakeCloudKitPayloadResolver(payloads: [:]),
            transport: transport,
            incomingRecordApplier: CloudKitLocalRecordApplier(database: database),
            now: { downloadedAt },
            retryDelay: 90
        )

        let summary = await runner.pullOnce(resultsLimit: 10)

        XCTAssertEqual(summary.failed, 0)
        XCTAssertEqual(summary.appliedUpserts, 1)
        let reviews = AppSettings.localWeeklyReviews
        XCTAssertEqual(reviews.map(\.id), ["remote-review", "existing-review"])
        let remoteReview = try XCTUnwrap(reviews.first { $0.id == "remote-review" })
        XCTAssertEqual(remoteReview.content.title, "A useful week")
        XCTAssertEqual(remoteReview.feedback?.selectedTypes, ["more_concrete"])
        XCTAssertNil(remoteReview.provider)
        XCTAssertNil(remoteReview.model)
        XCTAssertNil(remoteReview.errorCode)
        XCTAssertNil(remoteReview.errorMessage)
        XCTAssertEqual(try database.count("SELECT COUNT(*) FROM outbox_operations"), 0)
        XCTAssertEqual(try database.fetchCloudKitSyncState(scope: CloudKitSyncDefaults.zoneName)?.serverChangeTokenData, nextToken)
    }

    func testPullOnceAppliesRemoteWeeklyReviewDeletesToLocalSettingsWithoutOutbox() async throws {
        let database = try LocalDatabase.openForTesting(url: temporaryRoot.appending(path: "weekly-review-delete.sqlite"))
        let nextToken = Data([71])
        let deletedAt = Date(timeIntervalSince1970: 8_800)
        AppSettings.localWeeklyReviews = [
            Self.weeklyReview(id: "deleted-review", updatedAt: "2026-06-03T10:20:30Z", deletedAt: nil)
        ]
        let deletedRecord = CloudKitDeletedRecordIdentity(
            entityType: .weeklyReview,
            entityId: "deleted-review",
            recordType: CloudKitSyncEntityType.weeklyReview.recordType,
            recordName: CloudKitSyncEntityType.weeklyReview.recordName(entityId: "deleted-review"),
            zoneName: CloudKitSyncDefaults.zoneName
        )
        let transport = FakeCloudKitSyncTransport()
        transport.downloadedChanges = .init(
            modifiedPayloads: [],
            deletedRecords: [deletedRecord],
            serverChangeTokenData: nextToken,
            moreComing: false
        )
        let runner = CloudKitSyncRunner(
            database: database,
            payloadResolver: FakeCloudKitPayloadResolver(payloads: [:]),
            transport: transport,
            incomingRecordApplier: CloudKitLocalRecordApplier(database: database),
            now: { deletedAt },
            retryDelay: 90
        )

        let summary = await runner.pullOnce(resultsLimit: 10)

        XCTAssertEqual(summary.failed, 0)
        XCTAssertEqual(summary.appliedDeletes, 1)
        let review = try XCTUnwrap(AppSettings.localWeeklyReviews.first { $0.id == "deleted-review" })
        XCTAssertEqual(review.status, "deleted")
        XCTAssertEqual(review.deletedAt, Self.isoString(deletedAt))
        XCTAssertEqual(review.updatedAt, Self.isoString(deletedAt))
        XCTAssertEqual(try database.count("SELECT COUNT(*) FROM outbox_operations"), 0)
        XCTAssertEqual(try database.fetchCloudKitSyncState(scope: CloudKitSyncDefaults.zoneName)?.serverChangeTokenData, nextToken)
    }

    func testPullOnceAppliesRemotePreferencesToLocalSettingsWithoutOutboxOrProviderConfig() async throws {
        let database = try LocalDatabase.openForTesting(url: temporaryRoot.appending(path: "preference-upsert.sqlite"))
        let nextToken = Data([72])
        let downloadedAt = Date(timeIntervalSince1970: 8_900)
        AppSettings.showTagsInTimeline = true
        AppSettings.showCheckInSummaries = false
        AppSettings.memoryLinksEnabled = true
        AppSettings.aiTitleAutoInsertEnabled = false
        AppSettings.appAppearanceMode = .light
        AppSettings.appLanguageMode = .english
        AppSettings.aiLanguageMode = .english
        AppSettings.aiAnalysisEnabled = false
        AppSettings.aiExternalProcessingConsentAccepted = false
        AppSettings.useTextProviderForTranscription = false
        AppSettings.transcriptionProviderMode = .iPhoneOnDevice
        AppSettings.preferredSpeechTranscriptionLocaleIdentifier = nil
        AppSettings.autoWeeklyReviewEnabled = false
        AppSettings.publishWeeklyReviewToMoments = false
        AppSettings.markdownMathRenderingEnabled = false
        AppSettings.markdownRemoteImagesEnabled = true
        AppSettings.markdownRawHTMLRenderingEnabled = false
        AppSettings.automaticSyncEnabled = true
        let providerProfiles = [
            AIProviderProfile(
                id: "profile-local",
                kind: .customOpenAICompatible,
                displayName: "Local only",
                baseURLString: "https://local-ai.example/v1",
                model: "local-model",
                isEnabled: true,
                sortOrder: 0
            )
        ]
        let gatewaySettings = LocalTranscriptionGatewaySettings(
            urlString: "https://local-gateway.example",
            model: "local-whisper"
        )
        AppSettings.aiProviderProfiles = providerProfiles
        AppSettings.localTranscriptionGatewaySettings = gatewaySettings
        let payload = CloudKitRecordPayload(
            entityType: .preference,
            entityId: "app",
            fields: [
                "schemaVersion": .int(1),
                "showTagsInTimeline": .bool(false),
                "showCheckInSummaries": .bool(true),
                "memoryLinksEnabled": .bool(false),
                "aiTitleAutoInsertEnabled": .bool(true),
                "appAppearanceMode": .string("dark"),
                "appLanguageMode": .string("simplifiedChinese"),
                "aiLanguageMode": .string("chinese"),
                "aiAnalysisEnabled": .bool(true),
                "aiExternalProcessingConsentAccepted": .bool(true),
                "useTextProviderForTranscription": .bool(true),
                "transcriptionProviderMode": .string("custom_openai_compatible"),
                "preferredSpeechTranscriptionLocaleIdentifier": .string("zh-CN"),
                "autoWeeklyReviewEnabled": .bool(true),
                "publishWeeklyReviewToMoments": .bool(true),
                "markdownMathRenderingEnabled": .bool(true),
                "markdownRemoteImagesEnabled": .bool(false),
                "markdownRawHTMLRenderingEnabled": .bool(true)
            ]
        )
        let transport = FakeCloudKitSyncTransport()
        transport.downloadedChanges = .init(
            modifiedPayloads: [payload],
            deletedRecords: [],
            serverChangeTokenData: nextToken,
            moreComing: false
        )
        let runner = CloudKitSyncRunner(
            database: database,
            payloadResolver: FakeCloudKitPayloadResolver(payloads: [:]),
            transport: transport,
            incomingRecordApplier: CloudKitLocalRecordApplier(database: database),
            now: { downloadedAt },
            retryDelay: 90
        )

        let summary = await runner.pullOnce(resultsLimit: 10)

        XCTAssertEqual(summary.failed, 0)
        XCTAssertEqual(summary.appliedUpserts, 1)
        XCTAssertFalse(AppSettings.showTagsInTimeline)
        XCTAssertTrue(AppSettings.showCheckInSummaries)
        XCTAssertFalse(AppSettings.memoryLinksEnabled)
        XCTAssertTrue(AppSettings.aiTitleAutoInsertEnabled)
        XCTAssertEqual(AppSettings.appAppearanceMode, .dark)
        XCTAssertEqual(AppSettings.appLanguageMode, .simplifiedChinese)
        XCTAssertEqual(AppSettings.aiLanguageMode, .chinese)
        XCTAssertTrue(AppSettings.aiAnalysisEnabled)
        XCTAssertTrue(AppSettings.aiExternalProcessingConsentAccepted)
        XCTAssertTrue(AppSettings.useTextProviderForTranscription)
        XCTAssertEqual(AppSettings.transcriptionProviderMode, .customOpenAICompatible)
        XCTAssertEqual(AppSettings.preferredSpeechTranscriptionLocaleIdentifier, "zh-CN")
        XCTAssertTrue(AppSettings.autoWeeklyReviewEnabled)
        XCTAssertTrue(AppSettings.publishWeeklyReviewToMoments)
        XCTAssertTrue(AppSettings.markdownMathRenderingEnabled)
        XCTAssertFalse(AppSettings.markdownRemoteImagesEnabled)
        XCTAssertTrue(AppSettings.markdownRawHTMLRenderingEnabled)
        XCTAssertTrue(AppSettings.automaticSyncEnabled)
        XCTAssertEqual(AppSettings.aiProviderProfiles, providerProfiles)
        XCTAssertEqual(AppSettings.localTranscriptionGatewaySettings, gatewaySettings)
        XCTAssertEqual(try database.count("SELECT COUNT(*) FROM outbox_operations"), 0)
        XCTAssertEqual(try database.fetchCloudKitSyncState(scope: CloudKitSyncDefaults.zoneName)?.serverChangeTokenData, nextToken)
    }

    func testPullOnceAppliesRemoteDraftsToLocalDraftStoresWithoutOutbox() async throws {
        let database = try LocalDatabase.openForTesting(url: temporaryRoot.appending(path: "draft-upsert.sqlite"))
        let nextToken = Data([73])
        let occurredAt = Date(timeIntervalSince1970: 9_100)
        let updatedAt = occurredAt.addingTimeInterval(75)
        let downloadedAt = updatedAt.addingTimeInterval(25)
        let composerPayload = CloudKitRecordPayload(
            entityType: .draft,
            entityId: "composer",
            fields: [
                "schemaVersion": .int(1),
                "draftKind": .string("composer"),
                "text": .string("Remote composer draft"),
                "occurredAt": .date(occurredAt),
                "updatedAt": .date(updatedAt),
                "hasUnsupportedMediaDrafts": .bool(false)
            ]
        )
        let editPayload = CloudKitRecordPayload(
            entityType: .draft,
            entityId: "edit:post-remote",
            fields: [
                "schemaVersion": .int(1),
                "draftKind": .string("edit_moment"),
                "postId": .string("post-remote"),
                "text": .string("Remote edit draft"),
                "occurredAt": .date(occurredAt.addingTimeInterval(-600)),
                "updatedAt": .date(updatedAt.addingTimeInterval(10)),
                "existingMediaIds": .stringList(["media-remote-1"]),
                "hasUnsupportedMediaDrafts": .bool(true)
            ]
        )
        let transport = FakeCloudKitSyncTransport()
        transport.downloadedChanges = .init(
            modifiedPayloads: [composerPayload, editPayload],
            deletedRecords: [],
            serverChangeTokenData: nextToken,
            moreComing: false
        )
        let runner = CloudKitSyncRunner(
            database: database,
            payloadResolver: FakeCloudKitPayloadResolver(payloads: [:]),
            transport: transport,
            incomingRecordApplier: CloudKitLocalRecordApplier(database: database),
            now: { downloadedAt },
            retryDelay: 90
        )

        let summary = await runner.pullOnce(resultsLimit: 10)

        XCTAssertEqual(summary.failed, 0)
        XCTAssertEqual(summary.appliedUpserts, 2)
        XCTAssertEqual(ComposerDraftStore.loadText(), "Remote composer draft")
        XCTAssertEqual(ComposerDraftStore.loadOccurredAt(), occurredAt)
        XCTAssertEqual(ComposerDraftStore.loadUpdatedAt(), updatedAt)

        let currentItem = TimelineItem(
            post: Self.timelinePost(id: "post-remote", now: occurredAt),
            media: [Self.timelineMedia(id: "media-remote-1", postId: "post-remote", now: occurredAt)],
            comments: [],
            aiSummaries: [],
            tags: []
        )
        let editDraft = try XCTUnwrap(EditDraftStore.load(postId: "post-remote", currentItem: currentItem))
        XCTAssertEqual(editDraft.text, "Remote edit draft")
        XCTAssertEqual(editDraft.occurredAt, occurredAt.addingTimeInterval(-600))
        XCTAssertEqual(editDraft.updatedAt, updatedAt.addingTimeInterval(10))
        XCTAssertEqual(editDraft.mediaItems.map(\.id), ["media-remote-1"])
        XCTAssertEqual(try database.count("SELECT COUNT(*) FROM outbox_operations"), 0)
        XCTAssertEqual(try database.fetchCloudKitSyncState(scope: CloudKitSyncDefaults.zoneName)?.serverChangeTokenData, nextToken)
    }

    func testPullOnceAppliesRemoteDraftDeletesToLocalDraftStoresWithoutOutbox() async throws {
        let database = try LocalDatabase.openForTesting(url: temporaryRoot.appending(path: "draft-delete.sqlite"))
        let nextToken = Data([74])
        let occurredAt = Date(timeIntervalSince1970: 9_300)
        let updatedAt = occurredAt.addingTimeInterval(40)
        let downloadedAt = updatedAt.addingTimeInterval(10)
        ComposerDraftStore.save(text: "Local composer draft", occurredAt: occurredAt, updatedAt: updatedAt)
        try EditDraftStore.save(
            postId: "post-remote",
            text: "Local edit draft",
            occurredAt: occurredAt,
            updatedAt: updatedAt,
            mediaItems: []
        )
        let transport = FakeCloudKitSyncTransport()
        transport.downloadedChanges = .init(
            modifiedPayloads: [],
            deletedRecords: [
                .init(
                    entityType: .draft,
                    entityId: "composer",
                    recordType: "PMDraft",
                    recordName: "pm.draft.composer",
                    zoneName: CloudKitSyncDefaults.zoneName
                ),
                .init(
                    entityType: .draft,
                    entityId: "edit:post-remote",
                    recordType: "PMDraft",
                    recordName: "pm.draft.edit_post-remote",
                    zoneName: CloudKitSyncDefaults.zoneName
                )
            ],
            serverChangeTokenData: nextToken,
            moreComing: false
        )
        let runner = CloudKitSyncRunner(
            database: database,
            payloadResolver: FakeCloudKitPayloadResolver(payloads: [:]),
            transport: transport,
            incomingRecordApplier: CloudKitLocalRecordApplier(database: database),
            now: { downloadedAt },
            retryDelay: 90
        )

        let summary = await runner.pullOnce(resultsLimit: 10)

        XCTAssertEqual(summary.failed, 0)
        XCTAssertEqual(summary.appliedDeletes, 2)
        XCTAssertEqual(ComposerDraftStore.loadText(), "")
        XCTAssertNil(ComposerDraftStore.loadUpdatedAt())
        XCTAssertFalse(EditDraftStore.hasDraft(postId: "post-remote"))
        XCTAssertEqual(try database.count("SELECT COUNT(*) FROM outbox_operations"), 0)
        XCTAssertEqual(try database.fetchCloudKitSyncState(scope: CloudKitSyncDefaults.zoneName)?.serverChangeTokenData, nextToken)
    }

    func testPullOnceRecoversEditDraftPostIdFromSanitizedRecordNameWhenPostIdFieldIsMissing() async throws {
        let database = try LocalDatabase.openForTesting(url: temporaryRoot.appending(path: "draft-sanitized-id.sqlite"))
        let nextToken = Data([75])
        let occurredAt = Date(timeIntervalSince1970: 9_420)
        let updatedAt = occurredAt.addingTimeInterval(40)
        let downloadedAt = updatedAt.addingTimeInterval(10)
        let editPayload = CloudKitRecordPayload(
            entityType: .draft,
            entityId: "edit_post-remote",
            fields: [
                "schemaVersion": .int(CloudKitDraftSnapshot.schemaVersion),
                "draftKind": .string(CloudKitDraftSnapshot.Kind.editMoment.rawValue),
                "text": .string("Remote edit draft"),
                "occurredAt": .date(occurredAt),
                "updatedAt": .date(updatedAt),
                "existingMediaIds": .stringList(["media-remote-1"]),
                "hasUnsupportedMediaDrafts": .bool(false)
            ]
        )
        let transport = FakeCloudKitSyncTransport()
        transport.downloadedChanges = .init(
            modifiedPayloads: [editPayload],
            deletedRecords: [],
            serverChangeTokenData: nextToken,
            moreComing: false
        )
        let runner = CloudKitSyncRunner(
            database: database,
            payloadResolver: FakeCloudKitPayloadResolver(payloads: [:]),
            transport: transport,
            incomingRecordApplier: CloudKitLocalRecordApplier(database: database),
            now: { downloadedAt },
            retryDelay: 90
        )

        let summary = await runner.pullOnce(resultsLimit: 10)

        XCTAssertEqual(summary.failed, 0)
        XCTAssertEqual(summary.appliedUpserts, 1)
        let metadata = try XCTUnwrap(EditDraftStore.loadMetadata(postId: "post-remote"))
        XCTAssertEqual(metadata.text, "Remote edit draft")
        XCTAssertEqual(metadata.existingMediaIds, ["media-remote-1"])
        XCTAssertEqual(try database.fetchCloudKitSyncState(scope: CloudKitSyncDefaults.zoneName)?.serverChangeTokenData, nextToken)
    }
}

private extension CloudKitSyncRunnerTests {
    static func weeklyReview(id: String, updatedAt: String, deletedAt: String?) -> ReviewPayload {
        ReviewPayload(
            id: id,
            kind: "weekly",
            rangeMode: "weekly",
            rangeStart: "2026-05-27T10:20:30Z",
            rangeEnd: "2026-06-03T10:20:30Z",
            status: deletedAt == nil ? "ready" : "deleted",
            trigger: "manual",
            content: ReviewContentPayload(
                title: "A useful week",
                subtitle: nil,
                bodyMarkdown: "## A useful week\n\nSeveral ideas became concrete.",
                oneLiner: "Several ideas became concrete.",
                keywords: nil,
                themes: nil,
                emotionalReflection: nil,
                progressAndOpenLoops: nil,
                rhythm: nil,
                notableMoments: nil,
                gentleSuggestions: ["Keep one next step visible."],
                uncertainty: nil
            ),
            promptVersion: "weekly-review-v1",
            provider: "Private Provider",
            model: "private-model",
            language: "zh-Hans",
            errorCode: "provider_timeout",
            errorMessage: "private diagnostic",
            generatedAt: "2026-06-03T10:20:30Z",
            regeneratedFromReviewId: nil,
            publishedPostId: "review-post-1",
            createdAt: "2026-06-03T10:20:00Z",
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            feedback: ReviewFeedbackStatePayload(
                selectedTypes: ["more_concrete"],
                customNote: "Keep it practical.",
                customNoteUpdatedAt: "2026-06-03T10:21:00Z"
            )
        )
    }

    static func isoString(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    static func timelinePost(id: String, now: Date) -> TimelinePost {
        TimelinePost(
            id: id,
            text: "Existing post",
            isFavorite: false,
            isPinned: false,
            pinnedAt: nil,
            aiTagProcessedAt: nil,
            tagsUserEditedAt: nil,
            occurredAt: now,
            localCreatedAt: now,
            localUpdatedAt: now,
            localEditedAt: nil,
            serverVersion: nil,
            syncStatus: "synced",
            deletedAt: nil
        )
    }

    static func timelineMedia(id: String, postId: String, now: Date) -> TimelineMedia {
        TimelineMedia(
            id: id,
            postId: postId,
            kind: "image",
            localCompressedPath: "/tmp/\(id).jpg",
            localOriginalStagingPath: nil,
            localThumbnailPath: nil,
            remoteCompressedPath: nil,
            remoteOriginalPath: nil,
            remoteThumbnailPath: nil,
            originalPreserved: false,
            uploadStatus: "synced",
            mimeType: "image/jpeg",
            durationSeconds: nil,
            transcriptionText: nil,
            transcriptionStatus: "not_applicable",
            transcriptionError: nil,
            transcriptionUpdatedAt: nil,
            sortOrder: 0,
            checksum: nil,
            createdAt: now,
            updatedAt: now
        )
    }
}

private final class FakeCloudKitPayloadResolver: CloudKitSyncPayloadResolving {
    var payloads: [String: CloudKitRecordPayload]
    var assetPayloads: [String: CloudKitAssetRecordPayload]

    init(
        payloads: [String: CloudKitRecordPayload],
        assetPayloads: [String: CloudKitAssetRecordPayload] = [:]
    ) {
        self.payloads = payloads
        self.assetPayloads = assetPayloads
    }

    func payload(for change: CloudKitPendingChange) throws -> CloudKitRecordPayload? {
        payloads[change.id]
    }

    func assetPayload(for change: CloudKitPendingChange) throws -> CloudKitAssetRecordPayload? {
        assetPayloads[change.id]
    }
}

private final class FakeCloudKitSyncTransport: CloudKitSyncTransporting {
    struct FetchRequest: Equatable {
        var zoneName: String
        var sinceChangeTokenData: Data?
        var resultsLimit: Int?
    }

    struct FetchRecordRequest: Equatable {
        var entityType: CloudKitSyncEntityType
        var entityId: String
        var zoneName: String
    }

    var saveResult = CloudKitSavedRecordMetadata(recordChangeTag: nil, lastKnownRecordJson: nil)
    var saveAssetsResult = CloudKitSavedRecordMetadata(recordChangeTag: nil, lastKnownRecordJson: nil)
    var saveError: Error?
    var saveAssetsError: Error?
    var deleteError: Error?
    var downloadedChanges = CloudKitDownloadedChanges(
        modifiedPayloads: [],
        deletedRecords: [],
        serverChangeTokenData: nil,
        moreComing: false
    )
    var fetchRecordPayloads: [String: CloudKitRecordPayload] = [:]
    private(set) var savedPayloads: [CloudKitRecordPayload] = []
    private(set) var savedAssetPayloads: [CloudKitAssetRecordPayload] = []
    private(set) var deletedRecords: [CloudKitDeletedRecord] = []
    private(set) var fetchRequests: [FetchRequest] = []
    private(set) var fetchRecordRequests: [FetchRecordRequest] = []

    func save(_ payload: CloudKitRecordPayload) async throws -> CloudKitSavedRecordMetadata {
        if let saveError {
            throw saveError
        }
        savedPayloads.append(payload)
        return saveResult
    }

    func saveAssets(_ payload: CloudKitAssetRecordPayload) async throws -> CloudKitSavedRecordMetadata {
        if let saveAssetsError {
            throw saveAssetsError
        }
        savedAssetPayloads.append(payload)
        return saveAssetsResult
    }

    func delete(recordType: String, recordName: String, zoneName: String) async throws {
        if let deleteError {
            throw deleteError
        }
        deletedRecords.append(.init(recordType: recordType, recordName: recordName, zoneName: zoneName))
    }

    func fetchChanges(
        zoneName: String,
        sinceChangeTokenData: Data?,
        resultsLimit: Int?
    ) async throws -> CloudKitDownloadedChanges {
        fetchRequests.append(.init(
            zoneName: zoneName,
            sinceChangeTokenData: sinceChangeTokenData,
            resultsLimit: resultsLimit
        ))
        return downloadedChanges
    }

    func fetchRecord(
        entityType: CloudKitSyncEntityType,
        entityId: String,
        zoneName: String
    ) async throws -> CloudKitRecordPayload? {
        fetchRecordRequests.append(.init(entityType: entityType, entityId: entityId, zoneName: zoneName))
        return fetchRecordPayloads[entityType.localRecordStateId(entityId: entityId)]
    }
}

private final class FakeCloudKitIncomingRecordApplier: CloudKitIncomingRecordApplying {
    struct AppliedUpsert: Equatable {
        var payload: CloudKitRecordPayload
        var downloadedAt: Date
    }

    struct AppliedDelete: Equatable {
        var entityType: CloudKitSyncEntityType
        var entityId: String
        var cloudDeletedAt: Date?
        var downloadedAt: Date
    }

    private(set) var appliedUpserts: [AppliedUpsert] = []
    private(set) var appliedDeletes: [AppliedDelete] = []

    func applyUpsert(_ payload: CloudKitRecordPayload, downloadedAt: Date) throws {
        appliedUpserts.append(.init(payload: payload, downloadedAt: downloadedAt))
    }

    func applyDelete(
        entityType: CloudKitSyncEntityType,
        entityId: String,
        cloudDeletedAt: Date?,
        downloadedAt: Date
    ) throws {
        appliedDeletes.append(.init(
            entityType: entityType,
            entityId: entityId,
            cloudDeletedAt: cloudDeletedAt,
            downloadedAt: downloadedAt
        ))
    }
}

private struct CloudKitDeletedRecord: Equatable {
    var recordType: String
    var recordName: String
    var zoneName: String
}

private enum TestCloudKitSyncError: Error {
    case networkDown
}

private struct CloudKitSyncRunnerAppSettingsState {
    var showTagsInTimeline: Bool
    var showCheckInSummaries: Bool
    var memoryLinksEnabled: Bool
    var aiTitleAutoInsertEnabled: Bool
    var appAppearanceMode: AppAppearanceMode
    var appLanguageMode: AppLanguageMode
    var aiLanguageMode: AILanguageMode
    var aiAnalysisEnabled: Bool
    var aiExternalProcessingConsentAccepted: Bool
    var aiProviderProfiles: [AIProviderProfile]
    var aiProviderFallbackState: AIProviderFallbackState
    var useTextProviderForTranscription: Bool
    var preferredSpeechTranscriptionLocaleIdentifier: String?
    var transcriptionProviderMode: TranscriptionProviderMode
    var localTranscriptionGatewaySettings: LocalTranscriptionGatewaySettings
    var automaticSyncEnabled: Bool
    var autoWeeklyReviewEnabled: Bool
    var publishWeeklyReviewToMoments: Bool
    var markdownMathRenderingEnabled: Bool
    var markdownRemoteImagesEnabled: Bool
    var markdownRawHTMLRenderingEnabled: Bool

    static func capture() -> Self {
        Self(
            showTagsInTimeline: AppSettings.showTagsInTimeline,
            showCheckInSummaries: AppSettings.showCheckInSummaries,
            memoryLinksEnabled: AppSettings.memoryLinksEnabled,
            aiTitleAutoInsertEnabled: AppSettings.aiTitleAutoInsertEnabled,
            appAppearanceMode: AppSettings.appAppearanceMode,
            appLanguageMode: AppSettings.appLanguageMode,
            aiLanguageMode: AppSettings.aiLanguageMode,
            aiAnalysisEnabled: AppSettings.aiAnalysisEnabled,
            aiExternalProcessingConsentAccepted: AppSettings.aiExternalProcessingConsentAccepted,
            aiProviderProfiles: AppSettings.aiProviderProfiles,
            aiProviderFallbackState: AppSettings.aiProviderFallbackState,
            useTextProviderForTranscription: AppSettings.useTextProviderForTranscription,
            preferredSpeechTranscriptionLocaleIdentifier: AppSettings.preferredSpeechTranscriptionLocaleIdentifier,
            transcriptionProviderMode: AppSettings.transcriptionProviderMode,
            localTranscriptionGatewaySettings: AppSettings.localTranscriptionGatewaySettings,
            automaticSyncEnabled: AppSettings.automaticSyncEnabled,
            autoWeeklyReviewEnabled: AppSettings.autoWeeklyReviewEnabled,
            publishWeeklyReviewToMoments: AppSettings.publishWeeklyReviewToMoments,
            markdownMathRenderingEnabled: AppSettings.markdownMathRenderingEnabled,
            markdownRemoteImagesEnabled: AppSettings.markdownRemoteImagesEnabled,
            markdownRawHTMLRenderingEnabled: AppSettings.markdownRawHTMLRenderingEnabled
        )
    }

    func restore() {
        AppSettings.showTagsInTimeline = showTagsInTimeline
        AppSettings.showCheckInSummaries = showCheckInSummaries
        AppSettings.memoryLinksEnabled = memoryLinksEnabled
        AppSettings.aiTitleAutoInsertEnabled = aiTitleAutoInsertEnabled
        AppSettings.appAppearanceMode = appAppearanceMode
        AppSettings.appLanguageMode = appLanguageMode
        AppSettings.aiLanguageMode = aiLanguageMode
        AppSettings.aiAnalysisEnabled = aiAnalysisEnabled
        AppSettings.aiExternalProcessingConsentAccepted = aiExternalProcessingConsentAccepted
        AppSettings.aiProviderProfiles = aiProviderProfiles
        AppSettings.aiProviderFallbackState = aiProviderFallbackState
        AppSettings.useTextProviderForTranscription = useTextProviderForTranscription
        AppSettings.preferredSpeechTranscriptionLocaleIdentifier = preferredSpeechTranscriptionLocaleIdentifier
        AppSettings.transcriptionProviderMode = transcriptionProviderMode
        AppSettings.localTranscriptionGatewaySettings = localTranscriptionGatewaySettings
        AppSettings.automaticSyncEnabled = automaticSyncEnabled
        AppSettings.autoWeeklyReviewEnabled = autoWeeklyReviewEnabled
        AppSettings.publishWeeklyReviewToMoments = publishWeeklyReviewToMoments
        AppSettings.markdownMathRenderingEnabled = markdownMathRenderingEnabled
        AppSettings.markdownRemoteImagesEnabled = markdownRemoteImagesEnabled
        AppSettings.markdownRawHTMLRenderingEnabled = markdownRawHTMLRenderingEnabled
    }
}
