import XCTest
@testable import PrivateMoments

final class CloudKitSyncCoordinatorTests: XCTestCase {
    private var tempDirectory: URL!
    private var savedLocalWeeklyReviews: [ReviewPayload] = []

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "CloudKitSyncCoordinatorTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        savedLocalWeeklyReviews = AppSettings.localWeeklyReviews
        AppSettings.localWeeklyReviews = []
        UserDefaults.standard.removeObject(forKey: AppSettings.KeysForTesting.iCloudSyncEnabled)
        UserDefaults.standard.removeObject(forKey: AppSettings.KeysForTesting.cloudKitSmokeTestPostId)
        ComposerDraftStore.clear()
    }

    override func tearDownWithError() throws {
        AppSettings.localWeeklyReviews = savedLocalWeeklyReviews
        UserDefaults.standard.removeObject(forKey: AppSettings.KeysForTesting.iCloudSyncEnabled)
        UserDefaults.standard.removeObject(forKey: AppSettings.KeysForTesting.cloudKitSmokeTestPostId)
        ComposerDraftStore.clear()
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        try super.tearDownWithError()
    }

    func testICloudSyncDefaultsOff() {
        XCTAssertFalse(AppSettings.iCloudSyncEnabled)
    }

    func testSmokeTestUploadsOnlyOneExplicitSmokeMoment() async throws {
        AppSettings.iCloudSyncEnabled = true
        let database = try makeDatabase()
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        try database.insert(Self.timelinePost(id: "existing-long-term-post", text: "Existing private data", now: now))

        let transport = CoordinatorFakeCloudKitTransport()
        let coordinator = CloudKitSyncCoordinator(
            database: database,
            transport: transport,
            now: { now },
            idGenerator: { "smoke-id" }
        )

        let result = try await coordinator.runSmokeTest()

        XCTAssertEqual(result.postId, "cloudkit-smoke-smoke-id")
        XCTAssertEqual(transport.savedPayloads.map(\.entityId), [result.postId])
        XCTAssertFalse(transport.savedPayloads.map(\.entityId).contains("existing-long-term-post"))
        XCTAssertEqual(try database.fetchPosts().map(\.id).sorted(), ["cloudkit-smoke-smoke-id", "existing-long-term-post"])
        XCTAssertEqual(AppSettings.cloudKitSmokeTestPostId, result.postId)
        let state = try XCTUnwrap(database.fetchCloudKitRecordState(entityType: .moment, entityId: result.postId))
        XCTAssertEqual(state.lastUploadedAt, now)
        XCTAssertNotNil(state.lastKnownRecordJson)
    }

    func testSyncNowQueuesAndUploadsExistingLocalLibraryOnce() async throws {
        AppSettings.iCloudSyncEnabled = true
        let database = try makeDatabase()
        let now = Date(timeIntervalSince1970: 1_800_400_000)
        try database.insert(Self.timelinePost(id: "existing-long-term-post", text: "Existing private data", now: now))

        let transport = CoordinatorFakeCloudKitTransport()
        let coordinator = CloudKitSyncCoordinator(
            database: database,
            transport: transport,
            now: { now }
        )

        let firstResult = try await coordinator.syncNow(limit: 10)

        XCTAssertGreaterThanOrEqual(firstResult.uploadSummary.saved, 1)
        XCTAssertTrue(transport.savedPayloads.map(\.entityId).contains("existing-long-term-post"))
        let recordState = try XCTUnwrap(database.fetchCloudKitRecordState(
            entityType: .moment,
            entityId: "existing-long-term-post"
        ))
        XCTAssertEqual(recordState.lastUploadedAt, now)
        let initialUploadState = try XCTUnwrap(database.fetchCloudKitSyncState(
            scope: CloudKitInitialUploadPreparer.syncStateScope
        ))
        XCTAssertEqual(initialUploadState.lastSyncFinishedAt, now)

        let savedCountAfterFirstSync = transport.savedPayloads.count
        let secondResult = try await coordinator.syncNow(limit: 10)

        XCTAssertEqual(secondResult.uploadSummary.saved, 0)
        XCTAssertEqual(transport.savedPayloads.count, savedCountAfterFirstSync)
    }

    func testSyncNowBlocksInitialUploadWhenRemoteArchiveAndLocalLibraryBothHaveUserContent() async throws {
        AppSettings.iCloudSyncEnabled = true
        let database = try makeDatabase()
        let now = Date(timeIntervalSince1970: 1_800_500_000)
        try database.insert(Self.timelinePost(id: "local-existing-post", text: "Local private data", now: now))

        let remotePayload = CloudKitRecordMapper.payload(for: Self.timelinePost(
            id: "remote-existing-post",
            text: "Remote private data",
            now: now.addingTimeInterval(-60)
        ))
        let transport = CoordinatorFakeCloudKitTransport()
        transport.downloadedChangesQueue = [
            CloudKitDownloadedChanges(
                modifiedPayloads: [remotePayload],
                deletedRecords: [],
                serverChangeTokenData: Data([1]),
                moreComing: false
            )
        ]
        let coordinator = CloudKitSyncCoordinator(
            database: database,
            transport: transport,
            now: { now }
        )

        do {
            _ = try await coordinator.syncNow(limit: 10)
            XCTFail("Expected non-empty local library protection to stop the first sync.")
        } catch let error as CloudKitSyncCoordinatorError {
            XCTAssertEqual(error, .nonEmptyLocalLibraryWithExistingCloudArchive)
        }

        XCTAssertEqual(transport.savedPayloads, [])
        XCTAssertEqual(try database.fetchPendingCloudKitChanges(limit: 100), [])
        XCTAssertNotNil(try database.fetchPost(id: "local-existing-post"))
        XCTAssertNil(try database.fetchPost(id: "remote-existing-post"))
        let initialUploadState = try XCTUnwrap(database.fetchCloudKitSyncState(
            scope: CloudKitInitialUploadPreparer.syncStateScope
        ))
        XCTAssertEqual(initialUploadState.lastErrorCode, "cloudkit_initial_upload_conflict")
    }

    func testSyncNowPullsRemoteArchiveBeforeInitialUploadWhenLocalLibraryIsSampleOnly() async throws {
        AppSettings.iCloudSyncEnabled = true
        let database = try makeDatabase()
        let now = Date(timeIntervalSince1970: 1_800_600_000)
        _ = try database.seedWelcomeSampleIfNeeded(language: .english, now: now)

        let remotePayload = CloudKitRecordMapper.payload(for: Self.timelinePost(
            id: "remote-existing-post",
            text: "Remote private data",
            now: now.addingTimeInterval(-60)
        ))
        let transport = CoordinatorFakeCloudKitTransport()
        transport.downloadedChangesQueue = [
            CloudKitDownloadedChanges(
                modifiedPayloads: [remotePayload],
                deletedRecords: [],
                serverChangeTokenData: Data([1]),
                moreComing: false
            ),
            CloudKitDownloadedChanges(
                modifiedPayloads: [remotePayload],
                deletedRecords: [],
                serverChangeTokenData: Data([2]),
                moreComing: false
            )
        ]
        let coordinator = CloudKitSyncCoordinator(
            database: database,
            transport: transport,
            now: { now }
        )

        let result = try await coordinator.syncNow(limit: 10)

        XCTAssertEqual(transport.savedPayloads, [])
        XCTAssertEqual(result.uploadSummary.saved, 0)
        XCTAssertEqual(result.pullSummary.appliedUpserts, 1)
        XCTAssertNotNil(try database.fetchPost(id: "remote-existing-post"))
        XCTAssertNotNil(try database.fetchTimelineItem(postId: WelcomeSampleContent.postId))
        let initialUploadState = try XCTUnwrap(database.fetchCloudKitSyncState(
            scope: CloudKitInitialUploadPreparer.syncStateScope
        ))
        XCTAssertEqual(initialUploadState.lastSyncFinishedAt, now)
        XCTAssertNil(initialUploadState.lastErrorCode)
    }

    func testSyncNowDrainsAllDueUploadBatches() async throws {
        AppSettings.iCloudSyncEnabled = true
        let database = try makeDatabase()
        let now = Date(timeIntervalSince1970: 1_801_000_000)
        let postIds = (1...5).map { "historical-post-\($0)" }
        for postId in postIds {
            try database.insert(Self.timelinePost(id: postId, text: "Historical \(postId)", now: now))
        }

        let transport = CoordinatorFakeCloudKitTransport()
        let coordinator = CloudKitSyncCoordinator(
            database: database,
            transport: transport,
            now: { now }
        )

        let result = try await coordinator.syncNow(limit: 2)

        let uploadedMomentIds = transport.savedPayloads
            .filter { $0.entityType == .moment }
            .map(\.entityId)
            .sorted()
        XCTAssertEqual(uploadedMomentIds, postIds.sorted())
        XCTAssertGreaterThan(result.uploadSummary.claimed, 2)
        XCTAssertEqual(result.uploadSummary.saved, transport.savedPayloads.count)
        XCTAssertEqual(result.uploadSummary.failed, 0)
    }

    func testSyncNowDrainsPullBatchesUntilNoMoreChanges() async throws {
        AppSettings.iCloudSyncEnabled = true
        let database = try makeDatabase()
        let now = Date(timeIntervalSince1970: 1_801_200_000)
        try markInitialUploadFinished(database, at: now.addingTimeInterval(-60))

        let firstPayload = CloudKitRecordMapper.payload(for: Self.timelinePost(
            id: "remote-page-1",
            text: "Remote page 1",
            now: now
        ))
        let secondPayload = CloudKitRecordMapper.payload(for: Self.timelinePost(
            id: "remote-page-2",
            text: "Remote page 2",
            now: now.addingTimeInterval(10)
        ))
        let transport = CoordinatorFakeCloudKitTransport()
        transport.downloadedChangesQueue = [
            CloudKitDownloadedChanges(
                modifiedPayloads: [firstPayload],
                deletedRecords: [],
                serverChangeTokenData: Data([1]),
                moreComing: true
            ),
            CloudKitDownloadedChanges(
                modifiedPayloads: [secondPayload],
                deletedRecords: [],
                serverChangeTokenData: Data([2]),
                moreComing: false
            )
        ]
        let coordinator = CloudKitSyncCoordinator(
            database: database,
            transport: transport,
            now: { now }
        )

        let result = try await coordinator.syncNow(limit: 1)

        XCTAssertEqual(result.pullSummary.fetchedModified, 2)
        XCTAssertEqual(result.pullSummary.appliedUpserts, 2)
        XCTAssertEqual(result.pullSummary.failed, 0)
        XCTAssertEqual(transport.fetchChangesCallCount, 3)
        XCTAssertNotNil(try database.fetchPost(id: "remote-page-1"))
        XCTAssertNotNil(try database.fetchPost(id: "remote-page-2"))
        XCTAssertEqual(
            try database.fetchCloudKitSyncState(scope: CloudKitSyncDefaults.zoneName)?.serverChangeTokenData,
            Data([2])
        )
    }

    func testSyncNowRunsOneTimeFullReconciliationToRecoverHistoricalDerivedRecords() async throws {
        AppSettings.iCloudSyncEnabled = true
        let database = try makeDatabase()
        let now = Date(timeIntervalSince1970: 1_801_300_000)
        try markInitialUploadFinished(database, at: now.addingTimeInterval(-120))
        try database.upsertCloudKitSyncState(.init(
            scope: CloudKitSyncDefaults.zoneName,
            serverChangeTokenData: Data([42]),
            lastAccountStatus: "available",
            lastSyncStartedAt: now.addingTimeInterval(-70),
            lastSyncFinishedAt: now.addingTimeInterval(-60),
            lastErrorCode: nil,
            updatedAt: now.addingTimeInterval(-60)
        ))
        try database.insert(Self.timelinePost(id: "remote-post-with-missing-summary", text: "Audio note", now: now))
        try database.insert(Self.timelineMedia(
            id: "remote-audio-with-missing-summary",
            postId: "remote-post-with-missing-summary",
            now: now
        ))

        let summaryPayload = CloudKitRecordMapper.payload(for: TimelineAISummary(
            id: "remote-summary-reconcile",
            postId: "remote-post-with-missing-summary",
            mediaId: "remote-audio-with-missing-summary",
            status: "ready",
            format: "document",
            language: "zh-Hans",
            overview: nil,
            keyPoints: [],
            sections: [],
            summaryText: nil,
            documentTitle: "Recovered summary",
            oneLiner: "Recovered from the reconciliation pass.",
            documentBlocks: [
                TimelineAISummaryBlock(kind: "paragraph", level: 0, text: "Recovered from the reconciliation pass.", items: [])
            ],
            inputTranscriptLength: 120,
            inputDurationSeconds: 9,
            promptVersion: "media-summary-v4",
            provider: "openai-compatible",
            model: "private-model",
            errorCode: nil,
            errorMessage: nil,
            createdAt: now.addingTimeInterval(-20),
            updatedAt: now.addingTimeInterval(-10),
            deletedAt: nil
        ))
        let transport = CoordinatorFakeCloudKitTransport()
        transport.downloadedChangesQueue = [
            CloudKitDownloadedChanges(
                modifiedPayloads: [],
                deletedRecords: [],
                serverChangeTokenData: Data([43]),
                moreComing: false
            ),
            CloudKitDownloadedChanges(
                modifiedPayloads: [summaryPayload],
                deletedRecords: [],
                serverChangeTokenData: Data([99]),
                moreComing: false
            )
        ]
        let coordinator = CloudKitSyncCoordinator(
            database: database,
            transport: transport,
            now: { now }
        )

        let result = try await coordinator.syncNow(limit: 10)

        XCTAssertEqual(result.pullSummary.appliedUpserts, 1)
        XCTAssertNotNil(try database.fetchAISummary(id: "remote-summary-reconcile"))
        XCTAssertEqual(
            try database.fetchCloudKitSyncState(scope: CloudKitSyncDefaults.zoneName)?.serverChangeTokenData,
            Data([43])
        )
        XCTAssertEqual(
            try database.fetchCloudKitSyncState(scope: CloudKitSyncDefaults.fullReconciliationScope)?.serverChangeTokenData,
            Data([99])
        )
        XCTAssertEqual(transport.fetchRequests.map(\.sinceChangeTokenData), [Data([42]), nil])

        let secondResult = try await coordinator.syncNow(limit: 10)

        XCTAssertEqual(secondResult.pullSummary.appliedUpserts, 0)
        XCTAssertEqual(transport.fetchRequests.map(\.sinceChangeTokenData), [Data([42]), nil, Data([43])])
    }

    private func makeDatabase() throws -> LocalDatabase {
        try LocalDatabase.openForTesting(url: tempDirectory.appending(path: "test.sqlite"))
    }

    private func markInitialUploadFinished(_ database: LocalDatabase, at date: Date) throws {
        try database.upsertCloudKitSyncState(.init(
            scope: CloudKitInitialUploadPreparer.syncStateScope,
            serverChangeTokenData: nil,
            lastAccountStatus: "available",
            lastSyncStartedAt: date.addingTimeInterval(-1),
            lastSyncFinishedAt: date,
            lastErrorCode: nil,
            updatedAt: date
        ))
    }

    private static func timelinePost(id: String, text: String, now: Date) -> TimelinePost {
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

    private static func timelineMedia(id: String, postId: String, now: Date) -> TimelineMedia {
        TimelineMedia(
            id: id,
            postId: postId,
            kind: "audio",
            localCompressedPath: "/tmp/\(id).m4a",
            localOriginalStagingPath: nil,
            localThumbnailPath: nil,
            remoteCompressedPath: nil,
            remoteOriginalPath: nil,
            remoteThumbnailPath: nil,
            originalPreserved: false,
            uploadStatus: "uploaded",
            mimeType: "audio/mp4",
            durationSeconds: 9,
            transcriptionText: nil,
            transcriptionStatus: "not_requested",
            transcriptionError: nil,
            transcriptionUpdatedAt: nil,
            sortOrder: 0,
            checksum: nil,
            createdAt: now,
            updatedAt: now
        )
    }
}

private final class CoordinatorFakeCloudKitTransport: CloudKitSyncTransporting {
    struct FetchRequest: Equatable {
        var zoneName: String
        var sinceChangeTokenData: Data?
        var resultsLimit: Int?
    }

    private(set) var savedPayloads: [CloudKitRecordPayload] = []
    var downloadedChangesQueue: [CloudKitDownloadedChanges] = []
    private(set) var fetchChangesCallCount = 0
    private(set) var fetchRequests: [FetchRequest] = []

    func save(_ payload: CloudKitRecordPayload) async throws -> CloudKitSavedRecordMetadata {
        savedPayloads.append(payload)
        return CloudKitSavedRecordMetadata(
            recordChangeTag: "fake-tag-\(savedPayloads.count)",
            lastKnownRecordJson: try CloudKitRecordPayloadSnapshot.json(from: payload)
        )
    }

    func saveAssets(_ payload: CloudKitAssetRecordPayload) async throws -> CloudKitSavedRecordMetadata {
        CloudKitSavedRecordMetadata(
            recordChangeTag: "fake-asset-tag",
            lastKnownRecordJson: try CloudKitRecordPayloadSnapshot.json(from: payload.metadataPayload)
        )
    }

    func delete(recordType _: String, recordName _: String, zoneName _: String) async throws {}

    func fetchRecord(
        entityType _: CloudKitSyncEntityType,
        entityId _: String,
        zoneName _: String
    ) async throws -> CloudKitRecordPayload? {
        nil
    }

    func fetchChanges(
        zoneName: String,
        sinceChangeTokenData: Data?,
        resultsLimit: Int?
    ) async throws -> CloudKitDownloadedChanges {
        fetchChangesCallCount += 1
        fetchRequests.append(.init(
            zoneName: zoneName,
            sinceChangeTokenData: sinceChangeTokenData,
            resultsLimit: resultsLimit
        ))
        if !downloadedChangesQueue.isEmpty {
            return downloadedChangesQueue.removeFirst()
        }
        return CloudKitDownloadedChanges(
            modifiedPayloads: [],
            deletedRecords: [],
            serverChangeTokenData: nil,
            moreComing: false
        )
    }
}
