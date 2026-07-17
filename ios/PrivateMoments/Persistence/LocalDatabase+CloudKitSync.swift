import Foundation
import SQLite3

extension LocalDatabase {
    func upsertCloudKitRecordState(_ state: CloudKitRecordState) throws {
        let statement = try prepare(
            """
            INSERT INTO local_cloudkit_record_states
                (id, entityType, entityId, recordType, recordName, zoneName, recordChangeTag,
                 lastKnownRecordJson, localContentHash, cloudDeletedAt, lastMappedAt, lastUploadedAt, lastDownloadedAt)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(entityType, entityId) DO UPDATE SET
                id = excluded.id,
                recordType = excluded.recordType,
                recordName = excluded.recordName,
                zoneName = excluded.zoneName,
                recordChangeTag = excluded.recordChangeTag,
                lastKnownRecordJson = excluded.lastKnownRecordJson,
                localContentHash = excluded.localContentHash,
                cloudDeletedAt = excluded.cloudDeletedAt,
                lastMappedAt = excluded.lastMappedAt,
                lastUploadedAt = excluded.lastUploadedAt,
                lastDownloadedAt = excluded.lastDownloadedAt
            ON CONFLICT(zoneName, recordName) DO UPDATE SET
                id = excluded.id,
                entityType = excluded.entityType,
                entityId = excluded.entityId,
                recordType = excluded.recordType,
                recordChangeTag = excluded.recordChangeTag,
                lastKnownRecordJson = excluded.lastKnownRecordJson,
                localContentHash = excluded.localContentHash,
                cloudDeletedAt = excluded.cloudDeletedAt,
                lastMappedAt = excluded.lastMappedAt,
                lastUploadedAt = excluded.lastUploadedAt,
                lastDownloadedAt = excluded.lastDownloadedAt
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(state.id, to: 1, in: statement)
        try bind(state.entityType.rawValue, to: 2, in: statement)
        try bind(state.entityId, to: 3, in: statement)
        try bind(state.recordType, to: 4, in: statement)
        try bind(state.recordName, to: 5, in: statement)
        try bind(state.zoneName, to: 6, in: statement)
        try bind(state.recordChangeTag, to: 7, in: statement)
        try bind(state.lastKnownRecordJson, to: 8, in: statement)
        try bind(state.localContentHash, to: 9, in: statement)
        try bind(state.cloudDeletedAt, to: 10, in: statement)
        try bind(state.lastMappedAt, to: 11, in: statement)
        try bind(state.lastUploadedAt, to: 12, in: statement)
        try bind(state.lastDownloadedAt, to: 13, in: statement)
        try stepDone(statement)
    }

    func fetchCloudKitRecordState(
        entityType: CloudKitSyncEntityType,
        entityId: String
    ) throws -> CloudKitRecordState? {
        let statement = try prepare(
            """
            SELECT id, entityType, entityId, recordType, recordName, zoneName, recordChangeTag,
                   lastKnownRecordJson, localContentHash, cloudDeletedAt, lastMappedAt, lastUploadedAt, lastDownloadedAt
            FROM local_cloudkit_record_states
            WHERE entityType = ?
              AND entityId = ?
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(entityType.rawValue, to: 1, in: statement)
        try bind(entityId, to: 2, in: statement)

        if sqlite3_step(statement) == SQLITE_ROW {
            return try cloudKitRecordState(statement)
        }

        return nil
    }

    func upsertCloudKitSyncState(_ state: CloudKitSyncState) throws {
        let statement = try prepare(
            """
            INSERT INTO local_cloudkit_sync_state
                (scope, serverChangeTokenData, lastAccountStatus, lastSyncStartedAt,
                 lastSyncFinishedAt, lastErrorCode, lastErrorMessage, updatedAt)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(scope) DO UPDATE SET
                serverChangeTokenData = excluded.serverChangeTokenData,
                lastAccountStatus = excluded.lastAccountStatus,
                lastSyncStartedAt = excluded.lastSyncStartedAt,
                lastSyncFinishedAt = excluded.lastSyncFinishedAt,
                lastErrorCode = excluded.lastErrorCode,
                lastErrorMessage = excluded.lastErrorMessage,
                updatedAt = excluded.updatedAt
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(state.scope, to: 1, in: statement)
        try bind(state.serverChangeTokenData, to: 2, in: statement)
        try bind(state.lastAccountStatus, to: 3, in: statement)
        try bind(state.lastSyncStartedAt, to: 4, in: statement)
        try bind(state.lastSyncFinishedAt, to: 5, in: statement)
        try bind(state.lastErrorCode, to: 6, in: statement)
        try bind(state.lastErrorMessage, to: 7, in: statement)
        try bind(state.updatedAt, to: 8, in: statement)
        try stepDone(statement)
    }

    func fetchCloudKitSyncState(scope: String) throws -> CloudKitSyncState? {
        let statement = try prepare(
            """
            SELECT scope, serverChangeTokenData, lastAccountStatus, lastSyncStartedAt,
                   lastSyncFinishedAt, lastErrorCode, lastErrorMessage, updatedAt
            FROM local_cloudkit_sync_state
            WHERE scope = ?
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(scope, to: 1, in: statement)

        if sqlite3_step(statement) == SQLITE_ROW {
            return try cloudKitSyncState(statement)
        }

        return nil
    }

    func hasCloudKitSyncHistory() throws -> Bool {
        let recordStateCount = try count(
            """
            SELECT COUNT(*)
            FROM local_cloudkit_record_states
            WHERE zoneName = ?
            """,
            bind: { statement in
                try self.bind(CloudKitSyncDefaults.zoneName, to: 1, in: statement)
            }
        )
        if recordStateCount > 0 {
            return true
        }

        let syncStateCount = try count(
            """
            SELECT COUNT(*)
            FROM local_cloudkit_sync_state
            WHERE scope IN (?, ?, ?)
              AND (
                  serverChangeTokenData IS NOT NULL
                  OR lastSyncFinishedAt IS NOT NULL
                  OR lastSyncStartedAt IS NOT NULL
              )
            """,
            bind: { statement in
                try self.bind(CloudKitSyncDefaults.zoneName, to: 1, in: statement)
                try self.bind(CloudKitInitialUploadPreparer.syncStateScope, to: 2, in: statement)
                try self.bind(CloudKitDerivedContentBackfillPreparer.syncStateScope, to: 3, in: statement)
            }
        )
        return syncStateCount > 0
    }

    func markCloudKitSyncStateFailed(
        scope: String,
        errorCode: String,
        errorMessage: String? = nil,
        now: Date = Date()
    ) throws -> CloudKitSyncState {
        var state = try fetchCloudKitSyncState(scope: scope) ?? CloudKitSyncState(
            scope: scope,
            serverChangeTokenData: nil,
            lastAccountStatus: nil,
            lastSyncStartedAt: nil,
            lastSyncFinishedAt: nil,
            lastErrorCode: nil,
            lastErrorMessage: nil,
            updatedAt: now
        )
        state.lastErrorCode = errorCode
        state.lastErrorMessage = errorMessage
        state.updatedAt = now
        try upsertCloudKitSyncState(state)
        return state
    }

    func enqueueCloudKitPendingChange(
        entityType: CloudKitSyncEntityType,
        entityId: String,
        changeKind: CloudKitPendingChangeKind,
        reason: String?,
        now: Date = Date()
    ) throws -> CloudKitPendingChange {
        let recordState = try fetchCloudKitRecordState(entityType: entityType, entityId: entityId)
        let change = CloudKitPendingChange(
            id: UUID().uuidString,
            entityType: entityType,
            entityId: entityId,
            recordStateId: recordState?.id,
            changeKind: changeKind,
            reason: reason,
            status: .pending,
            attemptCount: 0,
            lastErrorCode: nil,
            lastErrorMessage: nil,
            createdAt: now,
            updatedAt: now,
            nextAttemptAt: nil,
            finishedAt: nil
        )

        let statement = try prepare(
            """
            INSERT INTO local_cloudkit_pending_changes
                (id, entityType, entityId, recordStateId, changeKind, reason, status, attemptCount,
                 lastErrorCode, lastErrorMessage, createdAt, updatedAt, nextAttemptAt, finishedAt)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(change.id, to: 1, in: statement)
        try bind(change.entityType.rawValue, to: 2, in: statement)
        try bind(change.entityId, to: 3, in: statement)
        try bind(change.recordStateId, to: 4, in: statement)
        try bind(change.changeKind.rawValue, to: 5, in: statement)
        try bind(change.reason, to: 6, in: statement)
        try bind(change.status.rawValue, to: 7, in: statement)
        try bind(change.attemptCount, to: 8, in: statement)
        try bind(change.lastErrorCode, to: 9, in: statement)
        try bind(change.lastErrorMessage, to: 10, in: statement)
        try bind(change.createdAt, to: 11, in: statement)
        try bind(change.updatedAt, to: 12, in: statement)
        try bind(change.nextAttemptAt, to: 13, in: statement)
        try bind(change.finishedAt, to: 14, in: statement)
        try stepDone(statement)

        return change
    }

    func fetchPendingCloudKitChanges(limit: Int) throws -> [CloudKitPendingChange] {
        let statement = try prepare(
            """
            SELECT id, entityType, entityId, recordStateId, changeKind, reason, status, attemptCount,
                   lastErrorCode, lastErrorMessage, createdAt, updatedAt, nextAttemptAt, finishedAt
            FROM local_cloudkit_pending_changes
            WHERE status = ?
            ORDER BY createdAt ASC, id ASC
            LIMIT ?
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(CloudKitPendingChangeStatus.pending.rawValue, to: 1, in: statement)
        try bind(limit, to: 2, in: statement)

        var changes: [CloudKitPendingChange] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            changes.append(try cloudKitPendingChange(statement))
        }

        return changes
    }

    func hasUnfinishedCloudKitPendingChange(
        entityType: CloudKitSyncEntityType,
        entityId: String
    ) throws -> Bool {
        try queryUnfinishedCloudKitPendingChange(
            entityType: entityType,
            entityId: entityId,
            changeKind: nil
        )
    }

    func hasUnfinishedCloudKitPendingChange(
        entityType: CloudKitSyncEntityType,
        entityId: String,
        changeKind: CloudKitPendingChangeKind
    ) throws -> Bool {
        try queryUnfinishedCloudKitPendingChange(
            entityType: entityType,
            entityId: entityId,
            changeKind: changeKind
        )
    }

    func hasQueuedCloudKitPendingChange(
        entityType: CloudKitSyncEntityType,
        entityId: String,
        changeKind: CloudKitPendingChangeKind
    ) throws -> Bool {
        let statement = try prepare(
            """
            SELECT 1
            FROM local_cloudkit_pending_changes
            WHERE entityType = ?
              AND entityId = ?
              AND changeKind = ?
              AND status IN (?, ?)
            LIMIT 1
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(entityType.rawValue, to: 1, in: statement)
        try bind(entityId, to: 2, in: statement)
        try bind(changeKind.rawValue, to: 3, in: statement)
        try bind(CloudKitPendingChangeStatus.pending.rawValue, to: 4, in: statement)
        try bind(CloudKitPendingChangeStatus.failed.rawValue, to: 5, in: statement)

        return sqlite3_step(statement) == SQLITE_ROW
    }

    private func queryUnfinishedCloudKitPendingChange(
        entityType: CloudKitSyncEntityType,
        entityId: String,
        changeKind: CloudKitPendingChangeKind?
    ) throws -> Bool {
        let statement = try prepare(
            """
            SELECT 1
            FROM local_cloudkit_pending_changes
            WHERE entityType = ?
              AND entityId = ?
              AND (? IS NULL OR changeKind = ?)
              AND status IN (?, ?, ?)
            LIMIT 1
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(entityType.rawValue, to: 1, in: statement)
        try bind(entityId, to: 2, in: statement)
        if let changeKind {
            try bind(changeKind.rawValue, to: 3, in: statement)
            try bind(changeKind.rawValue, to: 4, in: statement)
        } else {
            try bind(nil as String?, to: 3, in: statement)
            try bind(nil as String?, to: 4, in: statement)
        }
        try bind(CloudKitPendingChangeStatus.pending.rawValue, to: 5, in: statement)
        try bind(CloudKitPendingChangeStatus.running.rawValue, to: 6, in: statement)
        try bind(CloudKitPendingChangeStatus.failed.rawValue, to: 7, in: statement)

        return sqlite3_step(statement) == SQLITE_ROW
    }

    func claimDueCloudKitPendingChanges(
        limit: Int,
        now: Date = Date(),
        staleRunningAfter: TimeInterval = 600
    ) throws -> [CloudKitPendingChange] {
        guard limit > 0 else {
            return []
        }

        var claimedIds: [String] = []
        try transaction {
            claimedIds = try fetchDueCloudKitPendingChangeIds(
                limit: limit,
                now: now,
                staleRunningAfter: staleRunningAfter
            )

            for id in claimedIds {
                let statement = try prepare(
                    """
                    UPDATE local_cloudkit_pending_changes
                    SET status = ?,
                        attemptCount = attemptCount + 1,
                        updatedAt = ?,
                        nextAttemptAt = NULL,
                        finishedAt = NULL
                    WHERE id = ?
                    """
                )
                defer {
                    sqlite3_finalize(statement)
                }

                try bind(CloudKitPendingChangeStatus.running.rawValue, to: 1, in: statement)
                try bind(now, to: 2, in: statement)
                try bind(id, to: 3, in: statement)
                try stepDone(statement)
            }
        }

        var changes: [CloudKitPendingChange] = []
        for id in claimedIds {
            if let change = try fetchCloudKitPendingChange(id: id) {
                changes.append(change)
            }
        }
        return changes
    }

    func markCloudKitPendingChangeFinished(
        id: String,
        now: Date = Date()
    ) throws -> CloudKitPendingChange? {
        let statement = try prepare(
            """
            UPDATE local_cloudkit_pending_changes
            SET status = ?,
                lastErrorCode = NULL,
                lastErrorMessage = NULL,
                updatedAt = ?,
                nextAttemptAt = NULL,
                finishedAt = ?
            WHERE id = ?
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(CloudKitPendingChangeStatus.finished.rawValue, to: 1, in: statement)
        try bind(now, to: 2, in: statement)
        try bind(now, to: 3, in: statement)
        try bind(id, to: 4, in: statement)
        try stepDone(statement)

        return try fetchCloudKitPendingChange(id: id)
    }

    func markCloudKitPendingChangeFailed(
        id: String,
        errorCode: String,
        errorMessage: String?,
        retryAfter: TimeInterval,
        now: Date = Date()
    ) throws -> CloudKitPendingChange? {
        let retryAt = now.addingTimeInterval(max(0, retryAfter))
        let statement = try prepare(
            """
            UPDATE local_cloudkit_pending_changes
            SET status = ?,
                lastErrorCode = ?,
                lastErrorMessage = ?,
                updatedAt = ?,
                nextAttemptAt = ?,
                finishedAt = NULL
            WHERE id = ?
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(CloudKitPendingChangeStatus.failed.rawValue, to: 1, in: statement)
        try bind(errorCode, to: 2, in: statement)
        try bind(errorMessage, to: 3, in: statement)
        try bind(now, to: 4, in: statement)
        try bind(retryAt, to: 5, in: statement)
        try bind(id, to: 6, in: statement)
        try stepDone(statement)

        return try fetchCloudKitPendingChange(id: id)
    }

    private func cloudKitRecordState(_ statement: OpaquePointer) throws -> CloudKitRecordState {
        let entityTypeRawValue = try text(statement, 1)
        guard let entityType = CloudKitSyncEntityType(rawValue: entityTypeRawValue) else {
            throw LocalDatabaseError.sqlite("Unknown CloudKit entity type \(entityTypeRawValue)")
        }

        var state = CloudKitRecordState(
            entityType: entityType,
            entityId: try text(statement, 2),
            recordChangeTag: optionalText(statement, 6),
            lastKnownRecordJson: optionalText(statement, 7),
            localContentHash: optionalText(statement, 8),
            cloudDeletedAt: try optionalDate(statement, 9),
            lastMappedAt: try date(statement, 10),
            lastUploadedAt: try optionalDate(statement, 11),
            lastDownloadedAt: try optionalDate(statement, 12),
            zoneName: try text(statement, 5)
        )
        state.id = try text(statement, 0)
        state.recordType = try text(statement, 3)
        state.recordName = try text(statement, 4)
        return state
    }

    private func cloudKitSyncState(_ statement: OpaquePointer) throws -> CloudKitSyncState {
        CloudKitSyncState(
            scope: try text(statement, 0),
            serverChangeTokenData: optionalData(statement, 1),
            lastAccountStatus: optionalText(statement, 2),
            lastSyncStartedAt: try optionalDate(statement, 3),
            lastSyncFinishedAt: try optionalDate(statement, 4),
            lastErrorCode: optionalText(statement, 5),
            lastErrorMessage: optionalText(statement, 6),
            updatedAt: try date(statement, 7)
        )
    }

    private func cloudKitPendingChange(_ statement: OpaquePointer) throws -> CloudKitPendingChange {
        let entityTypeRawValue = try text(statement, 1)
        guard let entityType = CloudKitSyncEntityType(rawValue: entityTypeRawValue) else {
            throw LocalDatabaseError.sqlite("Unknown CloudKit entity type \(entityTypeRawValue)")
        }

        let changeKindRawValue = try text(statement, 4)
        guard let changeKind = CloudKitPendingChangeKind(rawValue: changeKindRawValue) else {
            throw LocalDatabaseError.sqlite("Unknown CloudKit pending change kind \(changeKindRawValue)")
        }

        let statusRawValue = try text(statement, 6)
        guard let status = CloudKitPendingChangeStatus(rawValue: statusRawValue) else {
            throw LocalDatabaseError.sqlite("Unknown CloudKit pending change status \(statusRawValue)")
        }

        return CloudKitPendingChange(
            id: try text(statement, 0),
            entityType: entityType,
            entityId: try text(statement, 2),
            recordStateId: optionalText(statement, 3),
            changeKind: changeKind,
            reason: optionalText(statement, 5),
            status: status,
            attemptCount: optionalInt(statement, 7) ?? 0,
            lastErrorCode: optionalText(statement, 8),
            lastErrorMessage: optionalText(statement, 9),
            createdAt: try date(statement, 10),
            updatedAt: try date(statement, 11),
            nextAttemptAt: try optionalDate(statement, 12),
            finishedAt: try optionalDate(statement, 13)
        )
    }

    private func fetchDueCloudKitPendingChangeIds(
        limit: Int,
        now: Date,
        staleRunningAfter: TimeInterval
    ) throws -> [String] {
        let staleRunningCutoff = now.addingTimeInterval(-max(0, staleRunningAfter))
        let statement = try prepare(
            """
            SELECT id
            FROM local_cloudkit_pending_changes
            WHERE status = ?
               OR (status = ? AND (nextAttemptAt IS NULL OR nextAttemptAt <= ?))
               OR (status = ? AND updatedAt <= ?)
            ORDER BY createdAt ASC, id ASC
            LIMIT ?
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(CloudKitPendingChangeStatus.pending.rawValue, to: 1, in: statement)
        try bind(CloudKitPendingChangeStatus.failed.rawValue, to: 2, in: statement)
        try bind(now, to: 3, in: statement)
        try bind(CloudKitPendingChangeStatus.running.rawValue, to: 4, in: statement)
        try bind(staleRunningCutoff, to: 5, in: statement)
        try bind(limit, to: 6, in: statement)

        var ids: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            ids.append(try text(statement, 0))
        }
        return ids
    }

    func fetchCloudKitPendingChange(id: String) throws -> CloudKitPendingChange? {
        let statement = try prepare(
            """
            SELECT id, entityType, entityId, recordStateId, changeKind, reason, status, attemptCount,
                   lastErrorCode, lastErrorMessage, createdAt, updatedAt, nextAttemptAt, finishedAt
            FROM local_cloudkit_pending_changes
            WHERE id = ?
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(id, to: 1, in: statement)

        if sqlite3_step(statement) == SQLITE_ROW {
            return try cloudKitPendingChange(statement)
        }

        return nil
    }
}
