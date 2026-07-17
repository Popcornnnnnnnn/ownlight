import Foundation

extension TimelineStore {
    func restoreICloudSyncOptInFromHistoryIfNeeded() throws {
        guard let database else {
            return
        }

        let didRestore = AppSettings.restoreICloudSyncOptInIfMissing(
            hasCloudKitHistory: try database.hasCloudKitSyncHistory()
        )
        guard didRestore else {
            return
        }

        _ = try CloudKitInitialUploadPreparer(database: database)
            .prepareMissingLocalRecords(reason: "icloud_opt_in_recovery")
    }

    func syncCloudKitAfterBootstrapIfNeeded() {
        guard canRunCloudKitAutoSync else {
            return
        }

        Task { [weak self] in
            await self?.syncCloudKitPendingWorkIfNeeded(reason: "bootstrap")
        }
    }

    func startCloudKitForegroundSyncLoop() {
        guard AppSettings.iCloudSyncEnabled, database != nil else {
            stopCloudKitForegroundSyncLoop()
            return
        }

        guard cloudKitForegroundSyncTask == nil else {
            return
        }

        let interval = cloudKitForegroundSyncIntervalNanoseconds
        cloudKitForegroundSyncTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: interval)
                } catch {
                    return
                }

                if Task.isCancelled {
                    return
                }

                await self?.syncCloudKitPendingWorkIfNeeded(reason: "foreground_poll")
            }
        }
    }

    func stopCloudKitForegroundSyncLoop() {
        cloudKitForegroundSyncTask?.cancel()
        cloudKitForegroundSyncTask = nil
    }

    func syncCloudKitPendingWorkIfNeeded(reason: String) async {
        guard canRunCloudKitAutoSync else {
            return
        }

        cloudKitAutoSyncTask?.cancel()
        cloudKitAutoSyncRetryTask?.cancel()
        cloudKitAutoSyncTask = nil
        cloudKitAutoSyncRetryTask = nil
        cloudKitAutoSyncRetryAttempt = 0
        await runCloudKitAutoSync(reason: reason)
    }

    func scheduleCloudKitAutoSync(reason: String, delayNanoseconds: UInt64? = nil) {
        guard canRunCloudKitAutoSync else {
            return
        }

        cloudKitAutoSyncTask?.cancel()
        cloudKitAutoSyncRetryTask?.cancel()
        cloudKitAutoSyncRetryTask = nil
        cloudKitAutoSyncRetryAttempt = 0

        let delay = delayNanoseconds ?? cloudKitAutoSyncDelayNanoseconds
        cloudKitAutoSyncTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: delay)
            } catch {
                return
            }

            await self?.runCloudKitAutoSync(reason: reason)
        }
    }

    func cancelCloudKitAutoSync() {
        cloudKitAutoSyncTask?.cancel()
        cloudKitAutoSyncRetryTask?.cancel()
        cloudKitForegroundSyncTask?.cancel()
        cloudKitAutoSyncTask = nil
        cloudKitAutoSyncRetryTask = nil
        cloudKitForegroundSyncTask = nil
        cloudKitAutoSyncRetryAttempt = 0
        needsCloudKitFollowUpSync = false
    }

    func enqueueCloudKitMomentUpsert(
        postId: String,
        reason: String,
        now: Date = Date()
    ) throws {
        try enqueueCloudKitChange(
            entityType: .moment,
            entityId: postId,
            kind: .upsert,
            reason: reason,
            now: now
        )
    }

    func enqueueCloudKitMomentDelete(
        postId: String,
        reason: String,
        now: Date = Date()
    ) throws {
        try enqueueCloudKitChange(
            entityType: .moment,
            entityId: postId,
            kind: .delete,
            reason: reason,
            now: now
        )
    }

    func enqueueCloudKitMomentTreeDelete(
        _ item: TimelineItem,
        now: Date = Date()
    ) throws {
        try enqueueCloudKitMomentDelete(postId: item.post.id, reason: "moment_delete", now: now)

        for media in item.media {
            try enqueueCloudKitMediaDelete(
                mediaId: media.id,
                reason: "moment_media_delete",
                now: now
            )
        }

        for comment in item.comments {
            try enqueueCloudKitCommentDelete(
                commentId: comment.id,
                reason: "moment_comment_delete",
                now: now
            )
        }

        for summary in item.aiSummaries {
            try enqueueCloudKitAISummaryDelete(
                summaryId: summary.id,
                reason: "moment_ai_summary_delete",
                now: now
            )
        }

        for assignedTag in item.tags {
            try enqueueCloudKitPostTagDelete(
                assignmentId: assignedTag.id,
                reason: "moment_post_tag_delete",
                now: now
            )
        }
    }

    func enqueueCloudKitMediaCreation(
        _ media: [TimelineMedia],
        now: Date = Date()
    ) throws {
        guard !media.isEmpty else {
            return
        }

        var nextCreatedAt = now.addingTimeInterval(0.001)
        for item in media {
            try enqueueCloudKitChange(
                entityType: .media,
                entityId: item.id,
                kind: .upsert,
                reason: "media_create",
                now: nextCreatedAt
            )
            nextCreatedAt = nextCreatedAt.addingTimeInterval(0.001)

            try enqueueCloudKitChange(
                entityType: .media,
                entityId: item.id,
                kind: .assetUpload,
                reason: "media_asset_upload",
                now: nextCreatedAt
            )
            nextCreatedAt = nextCreatedAt.addingTimeInterval(0.001)
        }
    }

    func enqueueCloudKitMediaUpsert(
        mediaId: String,
        reason: String,
        now: Date = Date()
    ) throws {
        try enqueueCloudKitChange(
            entityType: .media,
            entityId: mediaId,
            kind: .upsert,
            reason: reason,
            now: now
        )
    }

    func enqueueCloudKitMediaAssetUpload(
        mediaId: String,
        reason: String,
        now: Date = Date()
    ) throws {
        try enqueueCloudKitChange(
            entityType: .media,
            entityId: mediaId,
            kind: .assetUpload,
            reason: reason,
            now: now
        )
    }

    func enqueueCloudKitMediaDelete(
        mediaId: String,
        reason: String,
        now: Date = Date()
    ) throws {
        try enqueueCloudKitChange(
            entityType: .media,
            entityId: mediaId,
            kind: .delete,
            reason: reason,
            now: now
        )
    }

    func enqueueCloudKitCommentUpsert(
        commentId: String,
        reason: String,
        now: Date = Date()
    ) throws {
        try enqueueCloudKitChange(
            entityType: .comment,
            entityId: commentId,
            kind: .upsert,
            reason: reason,
            now: now
        )
    }

    func enqueueCloudKitCommentDelete(
        commentId: String,
        reason: String,
        now: Date = Date()
    ) throws {
        try enqueueCloudKitChange(
            entityType: .comment,
            entityId: commentId,
            kind: .delete,
            reason: reason,
            now: now
        )
    }

    func enqueueCloudKitAISummaryUpsert(
        summaryId: String,
        reason: String,
        now: Date = Date()
    ) throws {
        try enqueueCloudKitChange(
            entityType: .aiSummary,
            entityId: summaryId,
            kind: .upsert,
            reason: reason,
            now: now
        )
    }

    func enqueueCloudKitAISummaryDelete(
        summaryId: String,
        reason: String,
        now: Date = Date()
    ) throws {
        try enqueueCloudKitChange(
            entityType: .aiSummary,
            entityId: summaryId,
            kind: .delete,
            reason: reason,
            now: now
        )
    }

    func enqueueCloudKitTagUpsert(
        tagId: String,
        reason: String,
        now: Date = Date()
    ) throws {
        try enqueueCloudKitChange(
            entityType: .tag,
            entityId: tagId,
            kind: .upsert,
            reason: reason,
            now: now
        )
    }

    func enqueueCloudKitTagDelete(
        tagId: String,
        reason: String,
        now: Date = Date()
    ) throws {
        try enqueueCloudKitChange(
            entityType: .tag,
            entityId: tagId,
            kind: .delete,
            reason: reason,
            now: now
        )
    }

    func enqueueCloudKitTagAliasUpsert(
        aliasId: String,
        reason: String,
        now: Date = Date()
    ) throws {
        try enqueueCloudKitChange(
            entityType: .tagAlias,
            entityId: aliasId,
            kind: .upsert,
            reason: reason,
            now: now
        )
    }

    func enqueueCloudKitTagAliasDelete(
        aliasId: String,
        reason: String,
        now: Date = Date()
    ) throws {
        try enqueueCloudKitChange(
            entityType: .tagAlias,
            entityId: aliasId,
            kind: .delete,
            reason: reason,
            now: now
        )
    }

    func enqueueCloudKitPostTagUpsert(
        assignmentId: String,
        reason: String,
        now: Date = Date()
    ) throws {
        try enqueueCloudKitChange(
            entityType: .postTag,
            entityId: assignmentId,
            kind: .upsert,
            reason: reason,
            now: now
        )
    }

    func enqueueCloudKitPostTagDelete(
        assignmentId: String,
        reason: String,
        now: Date = Date()
    ) throws {
        try enqueueCloudKitChange(
            entityType: .postTag,
            entityId: assignmentId,
            kind: .delete,
            reason: reason,
            now: now
        )
    }

    func enqueueCloudKitCheckInItemUpsert(
        itemId: String,
        reason: String,
        now: Date = Date()
    ) throws {
        try enqueueCloudKitChange(
            entityType: .checkInItem,
            entityId: itemId,
            kind: .upsert,
            reason: reason,
            now: now
        )
    }

    func enqueueCloudKitCheckInItemDelete(
        itemId: String,
        reason: String,
        now: Date = Date()
    ) throws {
        try enqueueCloudKitChange(
            entityType: .checkInItem,
            entityId: itemId,
            kind: .delete,
            reason: reason,
            now: now
        )
    }

    func enqueueCloudKitCheckInEntryUpsert(
        entryId: String,
        reason: String,
        now: Date = Date()
    ) throws {
        try enqueueCloudKitChange(
            entityType: .checkInEntry,
            entityId: entryId,
            kind: .upsert,
            reason: reason,
            now: now
        )
    }

    func enqueueCloudKitCheckInEntryDelete(
        entryId: String,
        reason: String,
        now: Date = Date()
    ) throws {
        try enqueueCloudKitChange(
            entityType: .checkInEntry,
            entityId: entryId,
            kind: .delete,
            reason: reason,
            now: now
        )
    }

    func enqueueCloudKitCheckInMediaCreation(
        _ media: CheckInMedia?,
        now: Date = Date()
    ) throws {
        guard let media else {
            return
        }

        try enqueueCloudKitChange(
            entityType: .checkInMedia,
            entityId: media.id,
            kind: .upsert,
            reason: "checkin_media_upsert",
            now: now.addingTimeInterval(0.001)
        )
        try enqueueCloudKitChange(
            entityType: .checkInMedia,
            entityId: media.id,
            kind: .assetUpload,
            reason: "checkin_media_asset_upload",
            now: now.addingTimeInterval(0.002)
        )
    }

    func enqueueCloudKitCheckInMediaDelete(
        mediaId: String,
        reason: String,
        now: Date = Date()
    ) throws {
        try enqueueCloudKitChange(
            entityType: .checkInMedia,
            entityId: mediaId,
            kind: .delete,
            reason: reason,
            now: now
        )
    }

    func enqueueCloudKitCheckInAISummaryUpsert(
        summaryId: String,
        reason: String,
        now: Date = Date()
    ) throws {
        try enqueueCloudKitChange(
            entityType: .checkInAISummary,
            entityId: summaryId,
            kind: .upsert,
            reason: reason,
            now: now
        )
    }

    func enqueueCloudKitPreferenceUpsert(
        reason: String,
        now: Date = Date()
    ) throws {
        try enqueueCloudKitChange(
            entityType: .preference,
            entityId: CloudKitPreferenceSnapshot.recordId,
            kind: .upsert,
            reason: reason,
            now: now,
            syncDelayNanoseconds: cloudKitPreferenceSyncDelayNanoseconds
        )
    }

    func saveComposerDraft(
        text: String,
        occurredAt: Date,
        updatedAt: Date = Date(),
        reason: String
    ) throws {
        ComposerDraftStore.save(text: text, occurredAt: occurredAt, updatedAt: updatedAt)
        try enqueueCloudKitDraftUpsert(
            draftId: CloudKitDraftSnapshot.composerRecordId,
            reason: reason,
            now: updatedAt
        )
    }

    func clearComposerDraftTextAndDate(
        reason: String,
        now: Date = Date()
    ) throws {
        ComposerDraftStore.clearTextAndDate()
        try enqueueCloudKitDraftDelete(
            draftId: CloudKitDraftSnapshot.composerRecordId,
            reason: reason,
            now: now
        )
    }

    func clearComposerDraft(
        reason: String,
        now: Date = Date()
    ) throws {
        ComposerDraftStore.clear()
        try enqueueCloudKitDraftDelete(
            draftId: CloudKitDraftSnapshot.composerRecordId,
            reason: reason,
            now: now
        )
    }

    func saveEditDraft(
        postId: String,
        text: String,
        occurredAt: Date,
        updatedAt: Date = Date(),
        mediaItems: [MomentEditMediaItem],
        reason: String
    ) throws {
        try EditDraftStore.save(
            postId: postId,
            text: text,
            occurredAt: occurredAt,
            updatedAt: updatedAt,
            mediaItems: mediaItems
        )
        try enqueueCloudKitDraftUpsert(
            draftId: CloudKitDraftSnapshot.editRecordId(postId: postId),
            reason: reason,
            now: updatedAt
        )
    }

    func clearEditDraft(
        postId: String,
        reason: String,
        now: Date = Date()
    ) throws {
        EditDraftStore.clear(postId: postId)
        try enqueueCloudKitDraftDelete(
            draftId: CloudKitDraftSnapshot.editRecordId(postId: postId),
            reason: reason,
            now: now
        )
    }

    func enqueueCloudKitDraftUpsert(
        draftId: String,
        reason: String,
        now: Date = Date()
    ) throws {
        try enqueueCloudKitDraftChangeIfNeeded(
            draftId: draftId,
            kind: .upsert,
            reason: reason,
            now: now
        )
    }

    func enqueueCloudKitDraftDelete(
        draftId: String,
        reason: String,
        now: Date = Date()
    ) throws {
        try enqueueCloudKitDraftChangeIfNeeded(
            draftId: draftId,
            kind: .delete,
            reason: reason,
            now: now
        )
    }

    private func enqueueCloudKitChange(
        entityType: CloudKitSyncEntityType,
        entityId: String,
        kind: CloudKitPendingChangeKind,
        reason: String,
        now: Date,
        syncDelayNanoseconds: UInt64? = nil
    ) throws {
        guard AppSettings.iCloudSyncEnabled else {
            return
        }

        guard let database else {
            throw StoreError.notReady
        }

        _ = try database.enqueueCloudKitPendingChange(
            entityType: entityType,
            entityId: entityId,
            changeKind: kind,
            reason: reason,
            now: now
        )

        scheduleCloudKitAutoSync(reason: reason, delayNanoseconds: syncDelayNanoseconds)
    }

    private func enqueueCloudKitDraftChangeIfNeeded(
        draftId: String,
        kind: CloudKitPendingChangeKind,
        reason: String,
        now: Date
    ) throws {
        guard AppSettings.iCloudSyncEnabled else {
            return
        }

        guard let database else {
            throw StoreError.notReady
        }

        let hasQueuedSameKind = try database.hasQueuedCloudKitPendingChange(
            entityType: .draft,
            entityId: draftId,
            changeKind: kind
        )
        let hasQueuedDelete = try database.hasQueuedCloudKitPendingChange(
            entityType: .draft,
            entityId: draftId,
            changeKind: .delete
        )

        if kind == .delete && hasQueuedSameKind {
            return
        }

        if kind == .upsert && hasQueuedSameKind && !hasQueuedDelete {
            return
        }

        try enqueueCloudKitChange(
            entityType: .draft,
            entityId: draftId,
            kind: kind,
            reason: reason,
            now: now
        )
    }

    private var canRunCloudKitAutoSync: Bool {
        AppSettings.iCloudSyncEnabled && database != nil
    }

    private func runCloudKitAutoSync(reason: String) async {
        guard canRunCloudKitAutoSync else {
            return
        }

        cloudKitAutoSyncTask = nil

        if isCloudKitAutoSyncing {
            needsCloudKitFollowUpSync = true
            return
        }

        isCloudKitAutoSyncing = true

        do {
            let result = try await performCloudKitSyncNow()
            isCloudKitAutoSyncing = false
            try? await reload()
            refreshSyncedPreferencesFromAppSettings()
            handleCloudKitAutoSyncCompletion(result: result, reason: reason)
        } catch {
            isCloudKitAutoSyncing = false
            if shouldRetryCloudKitAutoSync(after: error) {
                scheduleCloudKitAutoSyncRetry(reason: reason)
            }
        }
    }

    private func performCloudKitSyncNow() async throws -> CloudKitManualSyncResult {
        if let cloudKitSyncNowOverride {
            return try await cloudKitSyncNowOverride()
        }

        guard let database else {
            throw StoreError.notReady
        }

        return try await CloudKitSyncCoordinator(database: database).syncNow()
    }

    private func handleCloudKitAutoSyncCompletion(result: CloudKitManualSyncResult, reason: String) {
        let hasFailures = result.uploadSummary.failed > 0 || result.pullSummary.failed > 0
        if hasFailures {
            scheduleCloudKitAutoSyncRetry(reason: reason)
            return
        }

        cloudKitAutoSyncRetryTask?.cancel()
        cloudKitAutoSyncRetryTask = nil
        cloudKitAutoSyncRetryAttempt = 0

        let hasMorePendingUploads: Bool
        if let database {
            hasMorePendingUploads = (try? database.fetchPendingCloudKitChanges(limit: 1).isEmpty) == false
        } else {
            hasMorePendingUploads = false
        }
        if result.pullSummary.moreComing || needsCloudKitFollowUpSync || hasMorePendingUploads {
            needsCloudKitFollowUpSync = false
            scheduleCloudKitAutoSync(reason: "\(reason)_follow_up")
        }
    }

    private func shouldRetryCloudKitAutoSync(after error: Error) -> Bool {
        guard AppSettings.iCloudSyncEnabled else {
            return false
        }

        if let coordinatorError = error as? CloudKitSyncCoordinatorError {
            switch coordinatorError {
            case .iCloudSyncDisabled, .notConfigured, .nonEmptyLocalLibraryWithExistingCloudArchive:
                return false
            }
        }

        return true
    }

    private func scheduleCloudKitAutoSyncRetry(reason: String) {
        guard AppSettings.iCloudSyncEnabled, database != nil else {
            return
        }

        cloudKitAutoSyncRetryTask?.cancel()
        let retryDelays = cloudKitAutoSyncRetryDelayNanoseconds
        let fallbackDelay: UInt64 = 300_000_000_000
        let retryDelay: UInt64
        if retryDelays.isEmpty {
            retryDelay = fallbackDelay
        } else {
            retryDelay = retryDelays[min(cloudKitAutoSyncRetryAttempt, retryDelays.count - 1)]
        }
        cloudKitAutoSyncRetryAttempt += 1

        cloudKitAutoSyncRetryTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: retryDelay)
            } catch {
                return
            }

            await self?.runCloudKitAutoSync(reason: "\(reason)_retry")
        }
    }
}
