import Foundation

struct CloudKitManualSyncResult: Equatable {
    var uploadSummary: CloudKitSyncRunSummary
    var pullSummary: CloudKitPullRunSummary

    func displaySummary(language: AppResolvedLanguage) -> String {
        let failedCount = uploadSummary.failed + pullSummary.failed
        let deferredCount = pullSummary.deferred

        if failedCount > 0 || deferredCount > 0 {
            return String(
                format: L10n.t(
                    "Sync finished: %d uploaded, %d downloaded, %d deleted, %d failed, %d deferred.",
                    language
                ),
                uploadSummary.saved,
                pullSummary.appliedUpserts,
                pullSummary.appliedDeletes,
                failedCount,
                deferredCount
            )
        }

        return String(
            format: L10n.t("Sync finished: %d uploaded, %d downloaded, %d deleted.", language),
            uploadSummary.saved,
            pullSummary.appliedUpserts,
            pullSummary.appliedDeletes
        )
    }
}

struct CloudKitSmokeTestResult: Equatable {
    var postId: String
    var recordChangeTag: String?
}

enum CloudKitSyncCoordinatorError: LocalizedError, Equatable {
    case iCloudSyncDisabled
    case notConfigured
    case nonEmptyLocalLibraryWithExistingCloudArchive

    var errorDescription: String? {
        switch self {
        case .iCloudSyncDisabled:
            return "Turn on iCloud Sync before running CloudKit actions."
        case .notConfigured:
            return "CloudKit is not configured for this build."
        case .nonEmptyLocalLibraryWithExistingCloudArchive:
            return "iCloud already has an Ownlight library, and this device also has local Ownlight data. To avoid silently merging or overwriting private data, export or clear this device before turning on iCloud Sync."
        }
    }
}

final class CloudKitSyncCoordinator {
    private let database: LocalDatabase
    private let transport: CloudKitSyncTransporting
    private let now: () -> Date
    private let idGenerator: () -> String

    init(
        database: LocalDatabase,
        transport: CloudKitSyncTransporting,
        now: @escaping () -> Date = Date.init,
        idGenerator: @escaping () -> String = { UUID().uuidString }
    ) {
        self.database = database
        self.transport = transport
        self.now = now
        self.idGenerator = idGenerator
    }

    convenience init(
        database: LocalDatabase,
        configuration: CloudKitConfiguration = CloudKitConfiguration(),
        now: @escaping () -> Date = Date.init,
        idGenerator: @escaping () -> String = { UUID().uuidString }
    ) throws {
        guard configuration.isConfigured else {
            throw CloudKitSyncCoordinatorError.notConfigured
        }

        try self.init(
            database: database,
            transport: CloudKitDefaultSyncTransport(configuration: configuration),
            now: now,
            idGenerator: idGenerator
        )
    }

    func syncNow(limit: Int = 50) async throws -> CloudKitManualSyncResult {
        guard AppSettings.iCloudSyncEnabled else {
            throw CloudKitSyncCoordinatorError.iCloudSyncDisabled
        }

        let initialUploadMode = try await prepareInitialUploadIfNeeded()
        if initialUploadMode.shouldRunLocalDerivedBackfill {
            _ = try CloudKitDerivedContentBackfillPreparer(database: database, now: now)
                .prepareIfNeeded()
        }

        let runner = CloudKitSyncRunner(
            database: database,
            payloadResolver: CloudKitLocalPayloadResolver(database: database),
            transport: transport,
            incomingRecordApplier: CloudKitLocalRecordApplier(database: database),
            now: now
        )
        let batchLimit = max(1, limit)
        let uploadSummary = await runUploadBatches(runner: runner, limit: batchLimit)
        var pullSummary = await runPullBatches(runner: runner, limit: batchLimit)
        if uploadSummary.failed == 0 && pullSummary.failed == 0 {
            let reconciliationSummary = await runFullReconciliationIfNeeded(runner: runner, limit: batchLimit)
            pullSummary.merge(reconciliationSummary)
        }
        return CloudKitManualSyncResult(
            uploadSummary: uploadSummary,
            pullSummary: pullSummary
        )
    }

    private func prepareInitialUploadIfNeeded() async throws -> InitialUploadMode {
        let preparer = CloudKitInitialUploadPreparer(database: database, now: now)
        guard try !preparer.isFinished() else {
            return .alreadyFinished
        }

        switch try await probeRemoteArchive() {
        case .emptyOrSmokeOnly:
            _ = try preparer.prepareIfNeeded()
            return .preparedLocalArchive
        case .hasUserArchive:
            if try CloudKitLocalLibraryProbe(database: database).hasUserContent() {
                try preparer.markBlockedByExistingRemoteArchive()
                throw CloudKitSyncCoordinatorError.nonEmptyLocalLibraryWithExistingCloudArchive
            }
            try preparer.markSkippedBecauseRemoteArchiveExists()
            return .remoteArchiveWillBePulled
        }
    }

    private func probeRemoteArchive() async throws -> RemoteArchiveProbeResult {
        let changes = try await transport.fetchChanges(
            zoneName: CloudKitSyncDefaults.zoneName,
            sinceChangeTokenData: nil,
            resultsLimit: 20
        )

        if changes.moreComing {
            return .hasUserArchive
        }

        if changes.modifiedPayloads.contains(where: { !Self.isSmokeTestRecord(entityType: $0.entityType, entityId: $0.entityId) }) {
            return .hasUserArchive
        }

        if changes.modifiedAssetRecords.contains(where: {
            !Self.isSmokeTestRecord(entityType: $0.payload.entityType, entityId: $0.payload.entityId)
        }) {
            return .hasUserArchive
        }

        if changes.deletedRecords.contains(where: { !Self.isSmokeTestRecord(entityType: $0.entityType, entityId: $0.entityId) }) {
            return .hasUserArchive
        }

        return .emptyOrSmokeOnly
    }

    private static func isSmokeTestRecord(
        entityType: CloudKitSyncEntityType,
        entityId: String
    ) -> Bool {
        guard entityType == .moment else {
            return false
        }

        if entityId.hasPrefix("cloudkit-smoke-") {
            return true
        }

        return entityId == AppSettings.cloudKitSmokeTestPostId
    }

    func runSmokeTest() async throws -> CloudKitSmokeTestResult {
        guard AppSettings.iCloudSyncEnabled else {
            throw CloudKitSyncCoordinatorError.iCloudSyncDisabled
        }

        let runAt = now()
        let post = try smokeTestPost(now: runAt)
        let payload = CloudKitRecordMapper.payload(for: post)
        let metadata = try await transport.save(payload)
        try markUploadApplied(payload: payload, metadata: metadata, uploadedAt: runAt)
        AppSettings.cloudKitSmokeTestPostId = post.id
        return CloudKitSmokeTestResult(
            postId: post.id,
            recordChangeTag: metadata.recordChangeTag
        )
    }

    private func smokeTestPost(now: Date) throws -> TimelinePost {
        if let postId = AppSettings.cloudKitSmokeTestPostId,
           let existingPost = try database.fetchPost(id: postId),
           existingPost.deletedAt == nil {
            return existingPost
        }

        let post = TimelinePost(
            id: "cloudkit-smoke-\(idGenerator())",
            text: """
            # CloudKit Smoke Test

            This is one explicit test Moment for iCloud Sync verification. It does not upload your existing library automatically.
            """,
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
        try database.insert(post)
        AppSettings.cloudKitSmokeTestPostId = post.id
        return post
    }

    private func markUploadApplied(
        payload: CloudKitRecordPayload,
        metadata: CloudKitSavedRecordMetadata,
        uploadedAt: Date
    ) throws {
        var state = try database.fetchCloudKitRecordState(
            entityType: payload.entityType,
            entityId: payload.entityId
        ) ?? CloudKitRecordState(
            entityType: payload.entityType,
            entityId: payload.entityId,
            lastMappedAt: uploadedAt,
            zoneName: payload.zoneName
        )
        state.recordChangeTag = metadata.recordChangeTag
        state.lastKnownRecordJson = metadata.lastKnownRecordJson
        state.cloudDeletedAt = nil
        state.lastMappedAt = uploadedAt
        state.lastUploadedAt = uploadedAt
        state.zoneName = payload.zoneName
        try database.upsertCloudKitRecordState(state)
    }

    private func runUploadBatches(
        runner: CloudKitSyncRunner,
        limit: Int
    ) async -> CloudKitSyncRunSummary {
        var combined = CloudKitSyncRunSummary(claimed: 0, saved: 0, deleted: 0, failed: 0)

        for _ in 0..<100 {
            let batch = await runner.runOnce(limit: limit)
            combined.merge(batch)

            if batch.failed > 0 || batch.claimed < limit {
                break
            }
        }

        return combined
    }

    private func runPullBatches(
        runner: CloudKitSyncRunner,
        limit: Int,
        stateScope: String = CloudKitSyncDefaults.zoneName
    ) async -> CloudKitPullRunSummary {
        var combined = CloudKitPullRunSummary(
            fetchedModified: 0,
            fetchedDeleted: 0,
            appliedUpserts: 0,
            appliedDeletes: 0,
            deferred: 0,
            ignored: 0,
            failed: 0,
            moreComing: false
        )

        for _ in 0..<100 {
            let batch = await runner.pullOnce(stateScope: stateScope, resultsLimit: limit)
            combined.merge(batch)

            if batch.failed > 0 || batch.deferred > 0 || !batch.moreComing {
                break
            }
        }

        return combined
    }

    private func runFullReconciliationIfNeeded(
        runner: CloudKitSyncRunner,
        limit: Int
    ) async -> CloudKitPullRunSummary {
        do {
            if let state = try database.fetchCloudKitSyncState(scope: CloudKitSyncDefaults.fullReconciliationScope),
               state.lastSyncFinishedAt != nil,
               state.lastErrorCode == nil {
                return CloudKitPullRunSummary.empty
            }
        } catch {
            return CloudKitPullRunSummary.empty
        }

        let summary = await runPullBatches(
            runner: runner,
            limit: limit,
            stateScope: CloudKitSyncDefaults.fullReconciliationScope
        )
        if summary.failed > 0 || summary.deferred > 0 || summary.moreComing {
            _ = try? database.markCloudKitSyncStateFailed(
                scope: CloudKitSyncDefaults.fullReconciliationScope,
                errorCode: "cloudkit_full_reconcile_incomplete",
                errorMessage: "Full reconciliation could not finish cleanly. It will retry on a later sync.",
                now: now()
            )
        }
        return summary
    }
}

private enum InitialUploadMode {
    case alreadyFinished
    case preparedLocalArchive
    case remoteArchiveWillBePulled

    var shouldRunLocalDerivedBackfill: Bool {
        switch self {
        case .alreadyFinished, .preparedLocalArchive:
            return true
        case .remoteArchiveWillBePulled:
            return false
        }
    }
}

private enum RemoteArchiveProbeResult {
    case emptyOrSmokeOnly
    case hasUserArchive
}

private struct CloudKitLocalLibraryProbe {
    let database: LocalDatabase

    func hasUserContent() throws -> Bool {
        if try database.realLocalObjectCountIgnoringWelcomeSample() > 0 {
            return true
        }

        if AppSettings.localWeeklyReviews.contains(where: { $0.deletedAt == nil }) {
            return true
        }

        if CloudKitDraftSnapshot.currentComposer() != nil {
            return true
        }

        return try database.fetchTimelineItems()
            .filter { !WelcomeSampleContent.isSample($0) }
            .contains { CloudKitDraftSnapshot.currentEdit(postId: $0.post.id) != nil }
    }
}

private extension CloudKitSyncRunSummary {
    mutating func merge(_ other: CloudKitSyncRunSummary) {
        claimed += other.claimed
        saved += other.saved
        deleted += other.deleted
        failed += other.failed
    }
}

private extension CloudKitPullRunSummary {
    static var empty: CloudKitPullRunSummary {
        CloudKitPullRunSummary(
            fetchedModified: 0,
            fetchedDeleted: 0,
            appliedUpserts: 0,
            appliedDeletes: 0,
            deferred: 0,
            ignored: 0,
            failed: 0,
            moreComing: false
        )
    }

    mutating func merge(_ other: CloudKitPullRunSummary) {
        fetchedModified += other.fetchedModified
        fetchedDeleted += other.fetchedDeleted
        appliedUpserts += other.appliedUpserts
        appliedDeletes += other.appliedDeletes
        deferred += other.deferred
        ignored += other.ignored
        failed += other.failed
        moreComing = other.moreComing
    }
}
