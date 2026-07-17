import XCTest
@testable import PrivateMoments

final class LocalDatabaseCloudKitSyncTests: XCTestCase {
    private var temporaryRoot: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryRoot = FileManager.default.temporaryDirectory
            .appending(path: "LocalDatabaseCloudKitSyncTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryRoot {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }
        try super.tearDownWithError()
    }

    func testMigrationCreatesCloudKitMetadataTables() throws {
        let database = try LocalDatabase.openForTesting(url: temporaryRoot.appending(path: "metadata.sqlite"))

        let tableNames = [
            "local_cloudkit_record_states",
            "local_cloudkit_pending_changes",
            "local_cloudkit_sync_state"
        ]

        for tableName in tableNames {
            let count = try database.count(
                "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = ?",
                bind: { statement in
                    try database.bind(tableName, to: 1, in: statement)
                }
            )
            XCTAssertEqual(count, 1, "Missing CloudKit metadata table \(tableName)")
        }
    }

    func testUpsertsCloudKitRecordStateByEntityIdentity() throws {
        let database = try LocalDatabase.openForTesting(url: temporaryRoot.appending(path: "record-state.sqlite"))
        let mappedAt = Date(timeIntervalSince1970: 1_800)
        let first = CloudKitRecordState(
            entityType: .moment,
            entityId: "post-1",
            recordChangeTag: nil,
            localContentHash: "hash-1",
            lastMappedAt: mappedAt
        )
        let second = CloudKitRecordState(
            entityType: .moment,
            entityId: "post-1",
            recordChangeTag: "change-tag-2",
            localContentHash: "hash-2",
            lastMappedAt: mappedAt.addingTimeInterval(60),
            lastUploadedAt: mappedAt.addingTimeInterval(90)
        )

        try database.upsertCloudKitRecordState(first)
        try database.upsertCloudKitRecordState(second)

        let fetched = try XCTUnwrap(database.fetchCloudKitRecordState(entityType: .moment, entityId: "post-1"))
        XCTAssertEqual(fetched.id, first.id)
        XCTAssertEqual(fetched.recordType, "PMMoment")
        XCTAssertEqual(fetched.recordName, "pm.moment.post-1")
        XCTAssertEqual(fetched.recordChangeTag, "change-tag-2")
        XCTAssertEqual(fetched.localContentHash, "hash-2")
        XCTAssertEqual(fetched.lastUploadedAt, mappedAt.addingTimeInterval(90))
        XCTAssertEqual(
            try database.count("SELECT COUNT(*) FROM local_cloudkit_record_states"),
            1
        )
    }

    func testUpsertsCloudKitRecordStateByRecordNameWhenEntityIdWasCanonicalized() throws {
        let database = try LocalDatabase.openForTesting(url: temporaryRoot.appending(path: "record-state-record-name.sqlite"))
        let mappedAt = Date(timeIntervalSince1970: 1_900)
        let legacy = CloudKitRecordState(
            entityType: .draft,
            entityId: "edit_post-1",
            recordChangeTag: "legacy-tag",
            lastMappedAt: mappedAt,
            lastDownloadedAt: mappedAt.addingTimeInterval(1)
        )
        let canonical = CloudKitRecordState(
            entityType: .draft,
            entityId: "edit:post-1",
            recordChangeTag: "canonical-tag",
            lastKnownRecordJson: #"{"draftKind":"edit_moment"}"#,
            lastMappedAt: mappedAt.addingTimeInterval(60),
            lastDownloadedAt: mappedAt.addingTimeInterval(61)
        )

        try database.upsertCloudKitRecordState(legacy)
        try database.upsertCloudKitRecordState(canonical)

        XCTAssertNil(try database.fetchCloudKitRecordState(entityType: .draft, entityId: "edit_post-1"))
        let fetched = try XCTUnwrap(database.fetchCloudKitRecordState(entityType: .draft, entityId: "edit:post-1"))
        XCTAssertEqual(fetched.id, "draft:edit:post-1")
        XCTAssertEqual(fetched.recordName, "pm.draft.edit_post-1")
        XCTAssertEqual(fetched.recordChangeTag, "canonical-tag")
        XCTAssertEqual(fetched.lastKnownRecordJson, #"{"draftKind":"edit_moment"}"#)
        XCTAssertEqual(
            try database.count("SELECT COUNT(*) FROM local_cloudkit_record_states"),
            1
        )
    }

    func testHasCloudKitSyncHistoryReflectsRecordStatesAndSyncState() throws {
        let emptyDatabase = try LocalDatabase.openForTesting(url: temporaryRoot.appending(path: "cloudkit-history-empty.sqlite"))
        XCTAssertFalse(try emptyDatabase.hasCloudKitSyncHistory())

        let recordDatabase = try LocalDatabase.openForTesting(url: temporaryRoot.appending(path: "cloudkit-history-record.sqlite"))
        let now = Date(timeIntervalSince1970: 2_000)
        try recordDatabase.upsertCloudKitRecordState(CloudKitRecordState(
            entityType: .moment,
            entityId: "post-1",
            lastMappedAt: now,
            lastUploadedAt: now
        ))
        XCTAssertTrue(try recordDatabase.hasCloudKitSyncHistory())

        let stateDatabase = try LocalDatabase.openForTesting(url: temporaryRoot.appending(path: "cloudkit-history-state.sqlite"))
        try stateDatabase.upsertCloudKitSyncState(CloudKitSyncState(
            scope: CloudKitSyncDefaults.zoneName,
            serverChangeTokenData: nil,
            lastAccountStatus: nil,
            lastSyncStartedAt: now,
            lastSyncFinishedAt: nil,
            lastErrorCode: nil,
            updatedAt: now
        ))
        XCTAssertTrue(try stateDatabase.hasCloudKitSyncHistory())
    }

    func testEnqueuesPendingCloudKitChangeWithoutUsingMacServerOutbox() throws {
        let database = try LocalDatabase.openForTesting(url: temporaryRoot.appending(path: "pending.sqlite"))
        let now = Date(timeIntervalSince1970: 2_000)
        let state = CloudKitRecordState(
            entityType: .moment,
            entityId: "post-1",
            lastMappedAt: now
        )

        try database.upsertCloudKitRecordState(state)
        let change = try database.enqueueCloudKitPendingChange(
            entityType: .moment,
            entityId: "post-1",
            changeKind: .upsert,
            reason: "local mutation",
            now: now.addingTimeInterval(1)
        )

        let pending = try database.fetchPendingCloudKitChanges(limit: 10)
        XCTAssertEqual(pending, [change])
        XCTAssertEqual(change.recordStateId, state.id)
        XCTAssertEqual(change.status, .pending)
        XCTAssertEqual(change.reason, "local mutation")
        XCTAssertEqual(
            try database.count("SELECT COUNT(*) FROM outbox_operations"),
            0,
            "CloudKit pending work must stay separate from the Mac/server sync outbox"
        )
    }

    func testClaimsDueCloudKitPendingChangesAndMarksThemRunning() throws {
        let database = try LocalDatabase.openForTesting(url: temporaryRoot.appending(path: "claim.sqlite"))
        let now = Date(timeIntervalSince1970: 2_200)
        try database.upsertCloudKitRecordState(.init(entityType: .moment, entityId: "post-1", lastMappedAt: now))
        try database.upsertCloudKitRecordState(.init(entityType: .comment, entityId: "comment-1", lastMappedAt: now))
        let first = try database.enqueueCloudKitPendingChange(
            entityType: .moment,
            entityId: "post-1",
            changeKind: .upsert,
            reason: "first",
            now: now
        )
        _ = try database.enqueueCloudKitPendingChange(
            entityType: .comment,
            entityId: "comment-1",
            changeKind: .delete,
            reason: "second",
            now: now.addingTimeInterval(1)
        )

        let claimed = try database.claimDueCloudKitPendingChanges(
            limit: 1,
            now: now.addingTimeInterval(10)
        )

        XCTAssertEqual(claimed.count, 1)
        XCTAssertEqual(claimed.first?.id, first.id)
        XCTAssertEqual(claimed.first?.status, .running)
        XCTAssertEqual(claimed.first?.attemptCount, 1)
        XCTAssertEqual(claimed.first?.updatedAt, now.addingTimeInterval(10))
        XCTAssertEqual(try database.fetchPendingCloudKitChanges(limit: 10).count, 1)
    }

    func testCloudKitPendingChangeFailureRetriesOnlyAfterDelay() throws {
        let database = try LocalDatabase.openForTesting(url: temporaryRoot.appending(path: "retry.sqlite"))
        let now = Date(timeIntervalSince1970: 2_400)
        try database.upsertCloudKitRecordState(.init(entityType: .moment, entityId: "post-1", lastMappedAt: now))
        let change = try database.enqueueCloudKitPendingChange(
            entityType: .moment,
            entityId: "post-1",
            changeKind: .upsert,
            reason: "retry",
            now: now
        )
        _ = try database.claimDueCloudKitPendingChanges(limit: 10, now: now.addingTimeInterval(1))

        let failed = try XCTUnwrap(database.markCloudKitPendingChangeFailed(
            id: change.id,
            errorCode: "network_unavailable",
            errorMessage: "offline",
            retryAfter: 60,
            now: now.addingTimeInterval(2)
        ))

        XCTAssertEqual(failed.status, .failed)
        XCTAssertEqual(failed.lastErrorCode, "network_unavailable")
        XCTAssertEqual(failed.lastErrorMessage, "offline")
        XCTAssertEqual(failed.nextAttemptAt, now.addingTimeInterval(62))
        XCTAssertEqual(
            try database.claimDueCloudKitPendingChanges(limit: 10, now: now.addingTimeInterval(30)),
            []
        )

        let retried = try database.claimDueCloudKitPendingChanges(limit: 10, now: now.addingTimeInterval(63))
        XCTAssertEqual(retried.count, 1)
        XCTAssertEqual(retried.first?.id, change.id)
        XCTAssertEqual(retried.first?.status, .running)
        XCTAssertEqual(retried.first?.attemptCount, 2)
    }

    func testClaimsStaleRunningCloudKitPendingChangesAgain() throws {
        let database = try LocalDatabase.openForTesting(url: temporaryRoot.appending(path: "stale-running.sqlite"))
        let now = Date(timeIntervalSince1970: 2_500)
        try database.upsertCloudKitRecordState(.init(entityType: .moment, entityId: "post-1", lastMappedAt: now))
        let change = try database.enqueueCloudKitPendingChange(
            entityType: .moment,
            entityId: "post-1",
            changeKind: .upsert,
            reason: "stale",
            now: now
        )
        _ = try database.claimDueCloudKitPendingChanges(limit: 10, now: now.addingTimeInterval(1))

        XCTAssertEqual(
            try database.claimDueCloudKitPendingChanges(limit: 10, now: now.addingTimeInterval(120)),
            []
        )

        let reclaimed = try database.claimDueCloudKitPendingChanges(
            limit: 10,
            now: now.addingTimeInterval(601)
        )

        XCTAssertEqual(reclaimed.count, 1)
        XCTAssertEqual(reclaimed.first?.id, change.id)
        XCTAssertEqual(reclaimed.first?.status, .running)
        XCTAssertEqual(reclaimed.first?.attemptCount, 2)
    }

    func testFinishesCloudKitPendingChangeAndKeepsItOutOfFutureClaims() throws {
        let database = try LocalDatabase.openForTesting(url: temporaryRoot.appending(path: "finish.sqlite"))
        let now = Date(timeIntervalSince1970: 2_600)
        try database.upsertCloudKitRecordState(.init(entityType: .moment, entityId: "post-1", lastMappedAt: now))
        let change = try database.enqueueCloudKitPendingChange(
            entityType: .moment,
            entityId: "post-1",
            changeKind: .upsert,
            reason: "finish",
            now: now
        )
        _ = try database.claimDueCloudKitPendingChanges(limit: 10, now: now.addingTimeInterval(1))

        let finished = try XCTUnwrap(database.markCloudKitPendingChangeFinished(
            id: change.id,
            now: now.addingTimeInterval(2)
        ))

        XCTAssertEqual(finished.status, .finished)
        XCTAssertEqual(finished.finishedAt, now.addingTimeInterval(2))
        XCTAssertEqual(
            try database.claimDueCloudKitPendingChanges(limit: 10, now: now.addingTimeInterval(3)),
            []
        )
    }

    func testFetchCloudKitSyncStateReturnsNilWhenScopeHasNotBeenStored() throws {
        let database = try LocalDatabase.openForTesting(url: temporaryRoot.appending(path: "sync-state-empty.sqlite"))

        XCTAssertNil(try database.fetchCloudKitSyncState(scope: CloudKitSyncDefaults.zoneName))
    }

    func testUpsertsCloudKitSyncStateByScope() throws {
        let database = try LocalDatabase.openForTesting(url: temporaryRoot.appending(path: "sync-state-upsert.sqlite"))
        let firstUpdatedAt = Date(timeIntervalSince1970: 2_800)
        let secondUpdatedAt = firstUpdatedAt.addingTimeInterval(60)

        try database.upsertCloudKitSyncState(.init(
            scope: CloudKitSyncDefaults.zoneName,
            serverChangeTokenData: Data([1, 2, 3]),
            lastAccountStatus: "available",
            lastSyncStartedAt: firstUpdatedAt.addingTimeInterval(-10),
            lastSyncFinishedAt: firstUpdatedAt,
            lastErrorCode: nil,
            updatedAt: firstUpdatedAt
        ))
        try database.upsertCloudKitSyncState(.init(
            scope: CloudKitSyncDefaults.zoneName,
            serverChangeTokenData: Data([4, 5]),
            lastAccountStatus: "available",
            lastSyncStartedAt: secondUpdatedAt.addingTimeInterval(-12),
            lastSyncFinishedAt: secondUpdatedAt,
            lastErrorCode: nil,
            updatedAt: secondUpdatedAt
        ))

        let fetched = try XCTUnwrap(database.fetchCloudKitSyncState(scope: CloudKitSyncDefaults.zoneName))
        XCTAssertEqual(fetched.serverChangeTokenData, Data([4, 5]))
        XCTAssertEqual(fetched.lastAccountStatus, "available")
        XCTAssertEqual(fetched.lastSyncStartedAt, secondUpdatedAt.addingTimeInterval(-12))
        XCTAssertEqual(fetched.lastSyncFinishedAt, secondUpdatedAt)
        XCTAssertNil(fetched.lastErrorCode)
        XCTAssertEqual(fetched.updatedAt, secondUpdatedAt)
        XCTAssertEqual(
            try database.count("SELECT COUNT(*) FROM local_cloudkit_sync_state"),
            1
        )
    }

    func testCloudKitSyncFailureKeepsPreviousServerChangeToken() throws {
        let database = try LocalDatabase.openForTesting(url: temporaryRoot.appending(path: "sync-state-failure.sqlite"))
        let previousFinishedAt = Date(timeIntervalSince1970: 3_000)
        let failedAt = previousFinishedAt.addingTimeInterval(90)
        try database.upsertCloudKitSyncState(.init(
            scope: CloudKitSyncDefaults.zoneName,
            serverChangeTokenData: Data([8, 9]),
            lastAccountStatus: "available",
            lastSyncStartedAt: previousFinishedAt.addingTimeInterval(-5),
            lastSyncFinishedAt: previousFinishedAt,
            lastErrorCode: nil,
            updatedAt: previousFinishedAt
        ))

        let failed = try database.markCloudKitSyncStateFailed(
            scope: CloudKitSyncDefaults.zoneName,
            errorCode: "decode_failed",
            now: failedAt
        )

        XCTAssertEqual(failed.serverChangeTokenData, Data([8, 9]))
        XCTAssertEqual(failed.lastSyncFinishedAt, previousFinishedAt)
        XCTAssertEqual(failed.lastErrorCode, "decode_failed")
        XCTAssertEqual(failed.updatedAt, failedAt)
    }
}
