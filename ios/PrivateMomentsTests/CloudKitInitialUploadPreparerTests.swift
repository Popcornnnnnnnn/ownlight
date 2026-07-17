import XCTest
@testable import PrivateMoments

final class CloudKitInitialUploadPreparerTests: XCTestCase {
    private var temporaryRoot: URL!
    private var createdMediaFiles: [URL] = []
    private var savedLocalWeeklyReviews: [ReviewPayload] = []

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryRoot = FileManager.default.temporaryDirectory
            .appending(path: "CloudKitInitialUploadPreparerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        savedLocalWeeklyReviews = AppSettings.localWeeklyReviews
        AppSettings.localWeeklyReviews = []
        ComposerDraftStore.clear()
        EditDraftStore.clear(postId: "post-1")
        createdMediaFiles = []
    }

    override func tearDownWithError() throws {
        AppSettings.localWeeklyReviews = savedLocalWeeklyReviews
        ComposerDraftStore.clear()
        EditDraftStore.clear(postId: "post-1")
        for url in createdMediaFiles {
            try? FileManager.default.removeItem(at: url)
        }
        createdMediaFiles = []
        if let temporaryRoot {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }
        temporaryRoot = nil
        try super.tearDownWithError()
    }

    func testPrepareIfNeededEnqueuesVisibleTimelineRecordsOnceAndSkipsWelcomeSample() throws {
        let database = try makeDatabase(named: "timeline.sqlite")
        let now = Date(timeIntervalSince1970: 1_800_300_000)
        _ = try database.seedWelcomeSampleIfNeeded(language: .english, now: now)
        try seedTimelineLibrary(database: database, now: now)

        let summary = try CloudKitInitialUploadPreparer(
            database: database,
            now: { now }
        ).prepareIfNeeded()

        let changes = try database.fetchPendingCloudKitChanges(limit: 100)
        XCTAssertEqual(summary.enqueued, changes.count)
        XCTAssertEqual(summary.skippedExisting, 0)
        XCTAssertTrue(changes.contains(.moment, "post-1", .upsert, "initial_upload"))
        XCTAssertTrue(changes.contains(.media, "media-1", .upsert, "initial_upload"))
        XCTAssertTrue(changes.contains(.media, "media-1", .assetUpload, "initial_upload_asset"))
        XCTAssertTrue(changes.contains(.comment, "comment-1", .upsert, "initial_upload"))
        XCTAssertTrue(changes.contains(.tag, "topic-1", .upsert, "initial_upload"))
        XCTAssertTrue(changes.contains(.tagAlias, "alias-1", .upsert, "initial_upload"))
        XCTAssertTrue(changes.contains(.postTag, "assignment-1", .upsert, "initial_upload"))
        XCTAssertFalse(changes.contains { $0.entityId.hasPrefix("welcome-sample-") })

        let state = try XCTUnwrap(database.fetchCloudKitSyncState(scope: CloudKitInitialUploadPreparer.syncStateScope))
        XCTAssertEqual(state.lastSyncStartedAt, now)
        XCTAssertEqual(state.lastSyncFinishedAt, now)
        XCTAssertNil(state.lastErrorCode)

        let secondSummary = try CloudKitInitialUploadPreparer(
            database: database,
            now: { now.addingTimeInterval(10) }
        ).prepareIfNeeded()
        XCTAssertEqual(secondSummary.enqueued, 0)
        XCTAssertEqual(try database.fetchPendingCloudKitChanges(limit: 100).count, changes.count)
    }

    func testPrepareIfNeededEnqueuesCheckInsReviewsPreferencesAndDrafts() throws {
        let database = try makeDatabase(named: "broader-library.sqlite")
        let now = Date(timeIntervalSince1970: 1_800_301_000)
        try seedTimelineLibrary(database: database, now: now)
        try seedCheckInLibrary(database: database, now: now)
        AppSettings.localWeeklyReviews = [
            Self.weeklyReview(id: "review-1", updatedAt: "2026-06-07T09:00:00Z", deletedAt: nil),
            Self.weeklyReview(id: "review-deleted", updatedAt: "2026-06-07T10:00:00Z", deletedAt: "2026-06-07T10:30:00Z")
        ]
        ComposerDraftStore.save(
            text: "Draft text",
            occurredAt: now.addingTimeInterval(-30),
            updatedAt: now.addingTimeInterval(3)
        )
        try EditDraftStore.saveMetadata(
            postId: "post-1",
            text: "Edit draft",
            occurredAt: now.addingTimeInterval(-20),
            updatedAt: now.addingTimeInterval(4),
            existingMediaIds: ["media-1"]
        )

        let summary = try CloudKitInitialUploadPreparer(
            database: database,
            now: { now }
        ).prepareIfNeeded()

        let changes = try database.fetchPendingCloudKitChanges(limit: 200)
        XCTAssertEqual(summary.enqueued, changes.count)
        XCTAssertTrue(changes.contains(.checkInItem, "checkin-item-1", .upsert, "initial_upload"))
        XCTAssertTrue(changes.contains(.checkInEntry, "checkin-entry-1", .upsert, "initial_upload"))
        XCTAssertTrue(changes.contains(.checkInMedia, "checkin-media-1", .upsert, "initial_upload"))
        XCTAssertTrue(changes.contains(.checkInMedia, "checkin-media-1", .assetUpload, "initial_upload_asset"))
        XCTAssertTrue(changes.contains(.checkInAISummary, "checkin-summary-1", .upsert, "initial_upload"))
        XCTAssertTrue(changes.contains(.weeklyReview, "review-1", .upsert, "initial_upload"))
        XCTAssertFalse(changes.contains(.weeklyReview, "review-deleted", .upsert, "initial_upload"))
        XCTAssertTrue(changes.contains(.preference, CloudKitPreferenceSnapshot.recordId, .upsert, "initial_upload"))
        XCTAssertTrue(changes.contains(.draft, CloudKitDraftSnapshot.composerRecordId, .upsert, "initial_upload"))
        XCTAssertTrue(changes.contains(.draft, CloudKitDraftSnapshot.editRecordId(postId: "post-1"), .upsert, "initial_upload"))
    }

    func testPrepareMissingLocalRecordsCanRecoverDraftsPreferencesAndCheckInsAfterInitialUploadFinished() throws {
        let database = try makeDatabase(named: "opt-in-recovery.sqlite")
        let now = Date(timeIntervalSince1970: 1_800_301_500)
        try seedCheckInLibrary(database: database, now: now)
        ComposerDraftStore.save(
            text: "Recovered draft",
            occurredAt: now.addingTimeInterval(-30),
            updatedAt: now.addingTimeInterval(3)
        )
        try database.upsertCloudKitRecordState(CloudKitRecordState(
            entityType: .checkInItem,
            entityId: "checkin-item-1",
            lastMappedAt: now,
            lastUploadedAt: now
        ))
        try database.upsertCloudKitRecordState(CloudKitRecordState(
            entityType: .preference,
            entityId: CloudKitPreferenceSnapshot.recordId,
            lastMappedAt: now,
            lastUploadedAt: now
        ))
        try database.upsertCloudKitRecordState(CloudKitRecordState(
            entityType: .draft,
            entityId: CloudKitDraftSnapshot.composerRecordId,
            lastMappedAt: now,
            lastUploadedAt: now
        ))
        try database.upsertCloudKitSyncState(CloudKitSyncState(
            scope: CloudKitInitialUploadPreparer.syncStateScope,
            serverChangeTokenData: nil,
            lastAccountStatus: nil,
            lastSyncStartedAt: now.addingTimeInterval(-120),
            lastSyncFinishedAt: now.addingTimeInterval(-60),
            lastErrorCode: nil,
            updatedAt: now.addingTimeInterval(-60)
        ))

        let summary = try CloudKitInitialUploadPreparer(
            database: database,
            now: { now }
        ).prepareMissingLocalRecords(reason: "icloud_opt_in_recovery")

        let changes = try database.fetchPendingCloudKitChanges(limit: 100)
        XCTAssertEqual(summary.enqueued, changes.count)
        XCTAssertGreaterThanOrEqual(summary.skippedExisting, 1)
        XCTAssertFalse(changes.contains(.checkInItem, "checkin-item-1", .upsert, "icloud_opt_in_recovery"))
        XCTAssertTrue(changes.contains(.checkInEntry, "checkin-entry-1", .upsert, "icloud_opt_in_recovery"))
        XCTAssertTrue(changes.contains(.checkInMedia, "checkin-media-1", .upsert, "icloud_opt_in_recovery"))
        XCTAssertTrue(changes.contains(.checkInMedia, "checkin-media-1", .assetUpload, "icloud_opt_in_recovery_asset"))
        XCTAssertTrue(changes.contains(.checkInAISummary, "checkin-summary-1", .upsert, "icloud_opt_in_recovery"))
        XCTAssertTrue(changes.contains(.preference, CloudKitPreferenceSnapshot.recordId, .upsert, "icloud_opt_in_recovery"))
        XCTAssertTrue(changes.contains(.draft, CloudKitDraftSnapshot.composerRecordId, .upsert, "icloud_opt_in_recovery"))
    }

    func testDerivedBackfillEnqueuesMissingLocalDerivedTimelineRecords() throws {
        let database = try makeDatabase(named: "derived-backfill.sqlite")
        let now = Date(timeIntervalSince1970: 1_800_302_000)
        try seedTimelineLibrary(database: database, now: now)
        try database.upsertAISummary(Self.timelineSummary(
            id: "summary-1",
            postId: "post-1",
            mediaId: "media-1",
            now: now
        ))

        let summary = try CloudKitDerivedContentBackfillPreparer(
            database: database,
            now: { now }
        ).prepareIfNeeded()

        let changes = try database.fetchPendingCloudKitChanges(limit: 100)
        XCTAssertEqual(summary.enqueued, changes.count)
        XCTAssertTrue(changes.contains(.comment, "comment-1", .upsert, "derived_backfill"))
        XCTAssertTrue(changes.contains(.aiSummary, "summary-1", .upsert, "derived_backfill"))
        XCTAssertTrue(changes.contains(.tag, "topic-1", .upsert, "derived_backfill"))
        XCTAssertTrue(changes.contains(.tagAlias, "alias-1", .upsert, "derived_backfill"))
        XCTAssertTrue(changes.contains(.postTag, "assignment-1", .upsert, "derived_backfill"))

        let secondSummary = try CloudKitDerivedContentBackfillPreparer(
            database: database,
            now: { now.addingTimeInterval(10) }
        ).prepareIfNeeded()
        XCTAssertEqual(secondSummary.enqueued, 0)
        XCTAssertEqual(try database.fetchPendingCloudKitChanges(limit: 100).count, changes.count)
    }

    func testDerivedBackfillSkipsDownloadedRecordsWithMatchingCloudKitState() throws {
        let database = try makeDatabase(named: "derived-backfill-downloaded.sqlite")
        let now = Date(timeIntervalSince1970: 1_800_302_500)
        try database.insert(Self.post(id: "post-downloaded", text: "Downloaded", now: now))
        let mediaURL = try makeStoredMediaFile(name: "media-downloaded.m4a", contents: "audio")
        try database.insert(TimelineMedia(
            id: "media-downloaded",
            postId: "post-downloaded",
            kind: "audio",
            localCompressedPath: mediaURL.path,
            localOriginalStagingPath: nil,
            localThumbnailPath: nil,
            remoteCompressedPath: nil,
            remoteOriginalPath: nil,
            remoteThumbnailPath: nil,
            originalPreserved: false,
            uploadStatus: "synced",
            mimeType: "audio/mp4",
            durationSeconds: 12,
            transcriptionText: nil,
            transcriptionStatus: "ready",
            transcriptionError: nil,
            transcriptionUpdatedAt: now,
            sortOrder: 0,
            checksum: nil,
            createdAt: now,
            updatedAt: now
        ))
        let comment = TimelineComment(
            id: "comment-downloaded",
            postId: "post-downloaded",
            text: "Already from CloudKit",
            createdAt: now,
            updatedAt: now,
            serverVersion: nil,
            deletedAt: nil
        )
        try database.insert(comment)
        let aiSummary = Self.timelineSummary(
            id: "summary-downloaded",
            postId: "post-downloaded",
            mediaId: "media-downloaded",
            now: now
        )
        try database.upsertAISummary(aiSummary)
        try database.upsertCloudKitRecordState(Self.downloadedState(for: CloudKitRecordMapper.payload(for: comment), now: now))
        try database.upsertCloudKitRecordState(Self.downloadedState(for: CloudKitRecordMapper.payload(for: aiSummary), now: now))

        let summary = try CloudKitDerivedContentBackfillPreparer(
            database: database,
            now: { now }
        ).prepareIfNeeded()

        let changes = try database.fetchPendingCloudKitChanges(limit: 100)
        XCTAssertEqual(summary.enqueued, changes.count)
        XCTAssertGreaterThanOrEqual(summary.skippedExisting, 2)
        XCTAssertFalse(changes.contains(.comment, "comment-downloaded", .upsert, "derived_backfill"))
        XCTAssertFalse(changes.contains(.aiSummary, "summary-downloaded", .upsert, "derived_backfill"))
    }

    private func makeDatabase(named name: String) throws -> LocalDatabase {
        try LocalDatabase.openForTesting(url: temporaryRoot.appending(path: name))
    }

    private func seedTimelineLibrary(database: LocalDatabase, now: Date) throws {
        try database.insert(Self.post(id: "post-1", text: "Historical Moment", now: now))
        let mediaURL = try makeStoredMediaFile(name: "media-1.m4a", contents: "audio")
        try database.insert(TimelineMedia(
            id: "media-1",
            postId: "post-1",
            kind: "audio",
            localCompressedPath: mediaURL.path,
            localOriginalStagingPath: nil,
            localThumbnailPath: nil,
            remoteCompressedPath: nil,
            remoteOriginalPath: nil,
            remoteThumbnailPath: nil,
            originalPreserved: false,
            uploadStatus: "synced",
            mimeType: "audio/mp4",
            durationSeconds: 12,
            transcriptionText: nil,
            transcriptionStatus: "ready",
            transcriptionError: nil,
            transcriptionUpdatedAt: now,
            sortOrder: 0,
            checksum: nil,
            createdAt: now,
            updatedAt: now
        ))
        try database.insert(TimelineComment(
            id: "comment-1",
            postId: "post-1",
            text: "A follow-up",
            createdAt: now.addingTimeInterval(1),
            updatedAt: now.addingTimeInterval(1),
            serverVersion: nil,
            deletedAt: nil
        ))
        let tag = TimelineTag(
            id: "topic-1",
            type: "topic",
            name: "CloudKit",
            normalizedName: LocalDatabase.normalizedTagName("CloudKit"),
            colorHex: nil,
            isDefault: false,
            isArchived: false,
            aiUsableAsPrimary: false,
            createdAt: now,
            updatedAt: now,
            archivedAt: nil,
            areaId: TopicTagArea.technology.rawValue
        )
        try database.upsertTag(tag)
        try database.upsertTagAlias(TimelineTagAlias(
            id: "alias-1",
            tagId: tag.id,
            alias: "Apple Cloud",
            normalizedAlias: LocalDatabase.normalizedTagName("Apple Cloud"),
            createdAt: now,
            deletedAt: nil
        ))
        try database.upsertAssignedTag(TimelineAssignedTag(
            id: "assignment-1",
            postId: "post-1",
            tagId: tag.id,
            role: "topic",
            source: "ai",
            confidence: 0.9,
            aiSummaryId: nil,
            createdAt: now,
            updatedAt: now,
            deletedAt: nil,
            tag: tag
        ))
    }

    private func seedCheckInLibrary(database: LocalDatabase, now: Date) throws {
        try database.upsertCheckInItemOnly(CheckInItem(
            id: "checkin-item-1",
            name: "Run",
            symbolName: "figure.run",
            colorHex: "#00AA00",
            recordMode: .oncePerDay,
            timeVisualization: .none,
            dayStartHour: 0,
            activeWeekdays: [1, 2, 3, 4, 5, 6, 7],
            sortOrder: 0,
            defaultShowInTimeline: true,
            tagId: nil,
            createdAt: now,
            updatedAt: now,
            archivedAt: nil,
            deletedAt: nil,
            syncStatus: "synced"
        ))
        try database.upsertCheckInEntryOnly(CheckInEntry(
            id: "checkin-entry-1",
            itemId: "checkin-item-1",
            occurredAt: now.addingTimeInterval(2),
            note: "Morning run",
            showInTimeline: true,
            createdAt: now.addingTimeInterval(2),
            updatedAt: now.addingTimeInterval(2),
            deletedAt: nil,
            syncStatus: "synced"
        ))
        let mediaURL = try makeStoredMediaFile(name: "checkin-media-1.m4a", contents: "checkin-audio")
        try database.upsertCheckInMediaOnly(CheckInMedia(
            id: "checkin-media-1",
            entryId: "checkin-entry-1",
            kind: "audio",
            localCompressedPath: mediaURL.path,
            remoteCompressedPath: nil,
            uploadStatus: "synced",
            uploadError: nil,
            mimeType: "audio/mp4",
            durationSeconds: 9,
            transcriptionText: nil,
            transcriptionStatus: "ready",
            transcriptionError: nil,
            transcriptionUpdatedAt: now,
            sortOrder: 0,
            checksum: nil,
            createdAt: now,
            updatedAt: now,
            deletedAt: nil
        ))
        try database.upsertCheckInAISummary(CheckInAISummary(
            id: "checkin-summary-1",
            entryId: "checkin-entry-1",
            mediaId: "checkin-media-1",
            status: "ready",
            format: "document",
            language: "en",
            overview: "Run summary",
            keyPoints: ["Finished"],
            sections: [],
            summaryText: "A short run.",
            documentTitle: "Run",
            oneLiner: "A short run.",
            documentBlocks: [],
            inputTranscriptLength: nil,
            inputDurationSeconds: 9,
            inputTokenCount: nil,
            outputTokenCount: nil,
            totalTokenCount: nil,
            promptVersion: "test",
            provider: nil,
            model: nil,
            errorCode: nil,
            errorMessage: nil,
            createdAt: now,
            updatedAt: now,
            deletedAt: nil
        ))
    }

    private func makeStoredMediaFile(name: String, contents: String) throws -> URL {
        let url = try AppDirectories.mediaDirectory()
            .appending(path: "cloudkit-initial-upload-\(UUID().uuidString)-\(name)")
        try Data(contents.utf8).write(to: url)
        createdMediaFiles.append(url)
        return url
    }

    private static func post(id: String, text: String, now: Date) -> TimelinePost {
        TimelinePost(
            id: id,
            text: text,
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

    private static func weeklyReview(
        id: String,
        updatedAt: String,
        deletedAt: String?
    ) -> ReviewPayload {
        ReviewPayload(
            id: id,
            kind: "weekly",
            rangeMode: "week",
            rangeStart: "2026-06-01T00:00:00Z",
            rangeEnd: "2026-06-07T23:59:59Z",
            status: "ready",
            trigger: "manual",
            content: ReviewContentPayload(
                title: "Review",
                subtitle: nil,
                bodyMarkdown: "Body",
                oneLiner: "One line",
                keywords: nil,
                themes: nil,
                emotionalReflection: nil,
                progressAndOpenLoops: nil,
                rhythm: nil,
                notableMoments: nil,
                gentleSuggestions: nil,
                uncertainty: nil
            ),
            promptVersion: "test",
            provider: nil,
            model: nil,
            language: "en",
            errorCode: nil,
            errorMessage: nil,
            generatedAt: updatedAt,
            regeneratedFromReviewId: nil,
            publishedPostId: nil,
            createdAt: "2026-06-07T08:00:00Z",
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            feedback: nil
        )
    }

    private static func timelineSummary(
        id: String,
        postId: String,
        mediaId: String,
        now: Date
    ) -> TimelineAISummary {
        TimelineAISummary(
            id: id,
            postId: postId,
            mediaId: mediaId,
            status: "ready",
            format: "document_v1",
            language: "en",
            overview: "Summary",
            keyPoints: ["One"],
            sections: [],
            summaryText: "Summary",
            documentTitle: "Audio Note",
            oneLiner: "One line",
            documentBlocks: [
                TimelineAISummaryBlock(kind: "paragraph", level: 0, text: "Summary", items: [])
            ],
            inputTranscriptLength: nil,
            inputDurationSeconds: 12,
            inputTokenCount: nil,
            outputTokenCount: nil,
            totalTokenCount: nil,
            promptVersion: "media-summary-v4",
            provider: nil,
            model: nil,
            errorCode: nil,
            errorMessage: nil,
            createdAt: now,
            updatedAt: now,
            deletedAt: nil
        )
    }

    private static func downloadedState(
        for payload: CloudKitRecordPayload,
        now: Date
    ) throws -> CloudKitRecordState {
        CloudKitRecordState(
            entityType: payload.entityType,
            entityId: payload.entityId,
            recordChangeTag: "downloaded",
            lastKnownRecordJson: try CloudKitRecordPayloadSnapshot.json(from: payload),
            cloudDeletedAt: nil,
            lastMappedAt: now,
            lastDownloadedAt: now,
            zoneName: payload.zoneName
        )
    }
}

private extension Array where Element == CloudKitPendingChange {
    func contains(
        _ entityType: CloudKitSyncEntityType,
        _ entityId: String,
        _ changeKind: CloudKitPendingChangeKind,
        _ reason: String
    ) -> Bool {
        contains { change in
            change.entityType == entityType
                && change.entityId == entityId
                && change.changeKind == changeKind
                && change.reason == reason
        }
    }
}
