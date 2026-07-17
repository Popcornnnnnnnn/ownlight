import Foundation

final class CloudKitDerivedContentBackfillPreparer {
    static let syncStateScope = "cloudkit_derived_content_backfill_v1"

    private let database: LocalDatabase
    private let now: () -> Date

    init(database: LocalDatabase, now: @escaping () -> Date = Date.init) {
        self.database = database
        self.now = now
    }

    func prepareIfNeeded() throws -> CloudKitInitialUploadSummary {
        let runAt = now()
        if let state = try database.fetchCloudKitSyncState(scope: Self.syncStateScope),
           state.lastSyncFinishedAt != nil,
           state.lastErrorCode == nil {
            return .init(enqueued: 0, skippedExisting: 0)
        }

        try markStarted(runAt)
        do {
            var summary = CloudKitInitialUploadSummary(enqueued: 0, skippedExisting: 0)
            try database.transaction {
                try enqueueTags(runAt: runAt, summary: &summary)
                try enqueueTimelineDerivedRecords(runAt: runAt, summary: &summary)
            }
            try markFinished(runAt)
            return summary
        } catch {
            _ = try? database.markCloudKitSyncStateFailed(
                scope: Self.syncStateScope,
                errorCode: "cloudkit_derived_backfill_prepare_failed",
                errorMessage: String(describing: error),
                now: runAt
            )
            throw error
        }
    }

    private func enqueueTags(
        runAt: Date,
        summary: inout CloudKitInitialUploadSummary
    ) throws {
        var createdAt = runAt

        for tag in try database.fetchTags(includeArchived: true) where !WelcomeSampleContent.isSampleTagId(tag.id) {
            try enqueueIfNeeded(
                payload: CloudKitRecordMapper.payload(for: tag),
                reason: "derived_backfill",
                at: &createdAt,
                summary: &summary
            )
        }

        for alias in try database.fetchTagAliases() where !WelcomeSampleContent.isSampleTagId(alias.tagId) {
            try enqueueIfNeeded(
                payload: CloudKitRecordMapper.payload(for: alias),
                reason: "derived_backfill",
                at: &createdAt,
                summary: &summary
            )
        }
    }

    private func enqueueTimelineDerivedRecords(
        runAt: Date,
        summary: inout CloudKitInitialUploadSummary
    ) throws {
        var createdAt = runAt.addingTimeInterval(0.1)

        for item in try database.fetchTimelineItems() where !WelcomeSampleContent.isSample(item) {
            for comment in item.comments where !WelcomeSampleContent.isSampleCommentId(comment.id) {
                try enqueueIfNeeded(
                    payload: CloudKitRecordMapper.payload(for: comment),
                    reason: "derived_backfill",
                    at: &createdAt,
                    summary: &summary
                )
            }

            for aiSummary in item.aiSummaries where !WelcomeSampleContent.isSampleAISummaryId(aiSummary.id) {
                try enqueueIfNeeded(
                    payload: CloudKitRecordMapper.payload(for: aiSummary),
                    reason: "derived_backfill",
                    at: &createdAt,
                    summary: &summary
                )
            }

            for assignedTag in item.tags where !WelcomeSampleContent.isSampleTagId(assignedTag.tagId) {
                try enqueueIfNeeded(
                    payload: CloudKitRecordMapper.payload(for: assignedTag),
                    reason: "derived_backfill",
                    at: &createdAt,
                    summary: &summary
                )
            }
        }
    }

    private func enqueueIfNeeded(
        payload: CloudKitRecordPayload,
        reason: String,
        at createdAt: inout Date,
        summary: inout CloudKitInitialUploadSummary
    ) throws {
        if try shouldSkip(payload: payload) {
            summary.skippedExisting += 1
            return
        }

        _ = try database.enqueueCloudKitPendingChange(
            entityType: payload.entityType,
            entityId: payload.entityId,
            changeKind: .upsert,
            reason: reason,
            now: createdAt
        )
        summary.enqueued += 1
        createdAt = createdAt.addingTimeInterval(0.001)
    }

    private func shouldSkip(payload: CloudKitRecordPayload) throws -> Bool {
        if try database.hasUnfinishedCloudKitPendingChange(
            entityType: payload.entityType,
            entityId: payload.entityId,
            changeKind: .upsert
        ) {
            return true
        }

        guard let state = try database.fetchCloudKitRecordState(
            entityType: payload.entityType,
            entityId: payload.entityId
        ) else {
            return false
        }

        guard state.cloudDeletedAt == nil,
              let lastKnownRecordJson = state.lastKnownRecordJson else {
            return false
        }

        if state.lastDownloadedAt != nil, state.lastUploadedAt == nil {
            return true
        }

        return lastKnownRecordJson == (try CloudKitRecordPayloadSnapshot.json(from: payload))
    }

    private func markStarted(_ runAt: Date) throws {
        var state = try database.fetchCloudKitSyncState(scope: Self.syncStateScope) ?? CloudKitSyncState(
            scope: Self.syncStateScope,
            serverChangeTokenData: nil,
            lastAccountStatus: nil,
            lastSyncStartedAt: nil,
            lastSyncFinishedAt: nil,
            lastErrorCode: nil,
            updatedAt: runAt
        )
        state.lastSyncStartedAt = runAt
        state.lastSyncFinishedAt = nil
        state.lastErrorCode = nil
        state.lastErrorMessage = nil
        state.updatedAt = runAt
        try database.upsertCloudKitSyncState(state)
    }

    private func markFinished(_ runAt: Date) throws {
        var state = try database.fetchCloudKitSyncState(scope: Self.syncStateScope) ?? CloudKitSyncState(
            scope: Self.syncStateScope,
            serverChangeTokenData: nil,
            lastAccountStatus: nil,
            lastSyncStartedAt: runAt,
            lastSyncFinishedAt: nil,
            lastErrorCode: nil,
            updatedAt: runAt
        )
        state.lastSyncStartedAt = state.lastSyncStartedAt ?? runAt
        state.lastSyncFinishedAt = runAt
        state.lastErrorCode = nil
        state.lastErrorMessage = nil
        state.updatedAt = runAt
        try database.upsertCloudKitSyncState(state)
    }
}
