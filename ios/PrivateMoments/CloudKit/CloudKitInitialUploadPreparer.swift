import Foundation

struct CloudKitInitialUploadSummary: Equatable {
    var enqueued: Int
    var skippedExisting: Int
}

final class CloudKitInitialUploadPreparer {
    static let syncStateScope = "cloudkit_initial_upload_v1"

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
                try enqueueAllLocalRecords(
                    runAt: runAt,
                    reason: "initial_upload",
                    assetReason: "initial_upload_asset",
                    summary: &summary
                )
            }
            try markFinished(runAt)
            return summary
        } catch {
            _ = try? database.markCloudKitSyncStateFailed(
                scope: Self.syncStateScope,
                errorCode: "cloudkit_initial_upload_prepare_failed",
                errorMessage: String(describing: error),
                now: runAt
            )
            throw error
        }
    }

    func isFinished() throws -> Bool {
        guard let state = try database.fetchCloudKitSyncState(scope: Self.syncStateScope) else {
            return false
        }

        return state.lastSyncFinishedAt != nil && state.lastErrorCode == nil
    }

    func markSkippedBecauseRemoteArchiveExists() throws {
        let runAt = now()
        try markStarted(runAt)
        try markFinished(runAt)
    }

    func markBlockedByExistingRemoteArchive() throws {
        let runAt = now()
        try markStarted(runAt)
        _ = try? database.markCloudKitSyncStateFailed(
            scope: Self.syncStateScope,
            errorCode: "cloudkit_initial_upload_conflict",
            errorMessage: CloudKitSyncCoordinatorError
                .nonEmptyLocalLibraryWithExistingCloudArchive
                .localizedDescription,
            now: runAt
        )
    }

    func prepareMissingLocalRecords(
        reason: String = "icloud_opt_in_recovery"
    ) throws -> CloudKitInitialUploadSummary {
        let runAt = now()
        var summary = CloudKitInitialUploadSummary(enqueued: 0, skippedExisting: 0)
        try database.transaction {
            try enqueueAllLocalRecords(
                runAt: runAt,
                reason: reason,
                assetReason: "\(reason)_asset",
                summary: &summary
            )
        }
        return summary
    }

    private func enqueueAllLocalRecords(
        runAt: Date,
        reason: String,
        assetReason: String,
        summary: inout CloudKitInitialUploadSummary
    ) throws {
        let shouldForceSingletonSnapshots = reason != "initial_upload"
        try enqueueTimelineRecords(
            runAt: runAt,
            reason: reason,
            assetReason: assetReason,
            summary: &summary
        )
        try enqueueTagRecords(runAt: runAt, reason: reason, summary: &summary)
        try enqueueCheckInRecords(
            runAt: runAt,
            reason: reason,
            assetReason: assetReason,
            summary: &summary
        )
        try enqueueWeeklyReviews(runAt: runAt, reason: reason, summary: &summary)
        try enqueuePreference(
            runAt: runAt,
            reason: reason,
            shouldSkipUploadedState: !shouldForceSingletonSnapshots,
            summary: &summary
        )
        try enqueueDrafts(
            runAt: runAt,
            reason: reason,
            shouldSkipUploadedState: !shouldForceSingletonSnapshots,
            summary: &summary
        )
    }

    private func enqueueTimelineRecords(
        runAt: Date,
        reason: String,
        assetReason: String,
        summary: inout CloudKitInitialUploadSummary
    ) throws {
        let items = try database.fetchTimelineItems()
            .filter { !WelcomeSampleContent.isSample($0) }
        var createdAt = runAt

        for item in items {
            try enqueueIfNeeded(
                .moment,
                item.post.id,
                .upsert,
                reason: reason,
                at: &createdAt,
                summary: &summary
            )

            for media in item.media where !WelcomeSampleContent.isSampleMediaId(media.id) {
                try enqueueIfNeeded(
                    .media,
                    media.id,
                    .upsert,
                    reason: reason,
                    at: &createdAt,
                    summary: &summary
                )
                if hasUploadableAsset(media) {
                    try enqueueIfNeeded(
                        .media,
                        media.id,
                        .assetUpload,
                        reason: assetReason,
                        at: &createdAt,
                        summary: &summary
                    )
                }
            }

            for comment in item.comments where !WelcomeSampleContent.isSampleCommentId(comment.id) {
                try enqueueIfNeeded(
                    .comment,
                    comment.id,
                    .upsert,
                    reason: reason,
                    at: &createdAt,
                    summary: &summary
                )
            }

            for aiSummary in item.aiSummaries where !WelcomeSampleContent.isSampleAISummaryId(aiSummary.id) {
                try enqueueIfNeeded(
                    .aiSummary,
                    aiSummary.id,
                    .upsert,
                    reason: reason,
                    at: &createdAt,
                    summary: &summary
                )
            }

            for assignedTag in item.tags where !WelcomeSampleContent.isSampleTagId(assignedTag.tagId) {
                try enqueueIfNeeded(
                    .postTag,
                    assignedTag.id,
                    .upsert,
                    reason: reason,
                    at: &createdAt,
                    summary: &summary
                )
            }
        }
    }

    private func enqueueTagRecords(
        runAt: Date,
        reason: String,
        summary: inout CloudKitInitialUploadSummary
    ) throws {
        var createdAt = runAt.addingTimeInterval(0.1)

        for tag in try database.fetchTags(includeArchived: true) where !WelcomeSampleContent.isSampleTagId(tag.id) {
            try enqueueIfNeeded(
                .tag,
                tag.id,
                .upsert,
                reason: reason,
                at: &createdAt,
                summary: &summary
            )
        }

        for alias in try database.fetchTagAliases() where !WelcomeSampleContent.isSampleTagId(alias.tagId) {
            try enqueueIfNeeded(
                .tagAlias,
                alias.id,
                .upsert,
                reason: reason,
                at: &createdAt,
                summary: &summary
            )
        }
    }

    private func enqueueCheckInRecords(
        runAt: Date,
        reason: String,
        assetReason: String,
        summary: inout CloudKitInitialUploadSummary
    ) throws {
        var createdAt = runAt.addingTimeInterval(0.2)

        for item in try database.fetchCheckInItems(includeArchived: true) {
            try enqueueIfNeeded(
                .checkInItem,
                item.id,
                .upsert,
                reason: reason,
                at: &createdAt,
                summary: &summary
            )
        }

        for entry in try database.fetchCheckInEntries() {
            try enqueueIfNeeded(
                .checkInEntry,
                entry.id,
                .upsert,
                reason: reason,
                at: &createdAt,
                summary: &summary
            )
        }

        for media in try database.fetchCheckInMedia() {
            try enqueueIfNeeded(
                .checkInMedia,
                media.id,
                .upsert,
                reason: reason,
                at: &createdAt,
                summary: &summary
            )
            if hasUploadableAsset(media) {
                try enqueueIfNeeded(
                    .checkInMedia,
                    media.id,
                    .assetUpload,
                    reason: assetReason,
                    at: &createdAt,
                    summary: &summary
                )
            }
        }

        for summaryRecord in try database.fetchCheckInAISummaries() {
            try enqueueIfNeeded(
                .checkInAISummary,
                summaryRecord.id,
                .upsert,
                reason: reason,
                at: &createdAt,
                summary: &summary
            )
        }
    }

    private func enqueueWeeklyReviews(
        runAt: Date,
        reason: String,
        summary: inout CloudKitInitialUploadSummary
    ) throws {
        var createdAt = runAt.addingTimeInterval(0.3)

        for review in AppSettings.localWeeklyReviews where review.deletedAt == nil {
            try enqueueIfNeeded(
                .weeklyReview,
                review.id,
                .upsert,
                reason: reason,
                at: &createdAt,
                summary: &summary
            )
        }
    }

    private func enqueuePreference(
        runAt: Date,
        reason: String,
        shouldSkipUploadedState: Bool,
        summary: inout CloudKitInitialUploadSummary
    ) throws {
        var createdAt = runAt.addingTimeInterval(0.4)
        try enqueueIfNeeded(
            .preference,
            CloudKitPreferenceSnapshot.recordId,
            .upsert,
            reason: reason,
            at: &createdAt,
            shouldSkipUploadedState: shouldSkipUploadedState,
            summary: &summary
        )
    }

    private func enqueueDrafts(
        runAt: Date,
        reason: String,
        shouldSkipUploadedState: Bool,
        summary: inout CloudKitInitialUploadSummary
    ) throws {
        var createdAt = runAt.addingTimeInterval(0.5)

        if CloudKitDraftSnapshot.currentComposer() != nil {
            try enqueueIfNeeded(
                .draft,
                CloudKitDraftSnapshot.composerRecordId,
                .upsert,
                reason: reason,
                at: &createdAt,
                shouldSkipUploadedState: shouldSkipUploadedState,
                summary: &summary
            )
        }

        for item in try database.fetchTimelineItems() where !WelcomeSampleContent.isSample(item) {
            let recordId = CloudKitDraftSnapshot.editRecordId(postId: item.post.id)
            if CloudKitDraftSnapshot.currentEdit(postId: item.post.id) != nil {
                try enqueueIfNeeded(
                    .draft,
                    recordId,
                    .upsert,
                    reason: reason,
                    at: &createdAt,
                    shouldSkipUploadedState: shouldSkipUploadedState,
                    summary: &summary
                )
            }
        }
    }

    private func enqueueIfNeeded(
        _ entityType: CloudKitSyncEntityType,
        _ entityId: String,
        _ changeKind: CloudKitPendingChangeKind,
        reason: String,
        at createdAt: inout Date,
        shouldSkipUploadedState: Bool = true,
        summary: inout CloudKitInitialUploadSummary
    ) throws {
        if try shouldSkip(
            entityType: entityType,
            entityId: entityId,
            changeKind: changeKind,
            shouldSkipUploadedState: shouldSkipUploadedState
        ) {
            summary.skippedExisting += 1
            return
        }

        _ = try database.enqueueCloudKitPendingChange(
            entityType: entityType,
            entityId: entityId,
            changeKind: changeKind,
            reason: reason,
            now: createdAt
        )
        summary.enqueued += 1
        createdAt = createdAt.addingTimeInterval(0.001)
    }

    private func shouldSkip(
        entityType: CloudKitSyncEntityType,
        entityId: String,
        changeKind: CloudKitPendingChangeKind,
        shouldSkipUploadedState: Bool
    ) throws -> Bool {
        if try database.hasUnfinishedCloudKitPendingChange(
            entityType: entityType,
            entityId: entityId,
            changeKind: changeKind
        ) {
            return true
        }

        guard shouldSkipUploadedState else {
            return false
        }

        guard let state = try database.fetchCloudKitRecordState(entityType: entityType, entityId: entityId) else {
            return false
        }

        return state.lastUploadedAt != nil && state.cloudDeletedAt == nil
    }

    private func hasUploadableAsset(_ media: TimelineMedia) -> Bool {
        hasLocalFile(media.localCompressedPath)
            || hasLocalFile(media.localThumbnailPath)
            || (media.originalPreserved && hasLocalFile(media.localOriginalStagingPath))
    }

    private func hasUploadableAsset(_ media: CheckInMedia) -> Bool {
        hasLocalFile(media.localCompressedPath)
    }

    private func hasLocalFile(_ path: String?) -> Bool {
        guard let path, !path.isEmpty else {
            return false
        }
        return FileManager.default.fileExists(atPath: path)
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
