import XCTest
@testable import PrivateMoments

@MainActor
final class CloudKitAutoSyncTests: XCTestCase {
    private var temporaryRoot: URL!
    private var savedPreferenceState: CloudKitAutoSyncAppSettingsState!

    override func setUpWithError() throws {
        try super.setUpWithError()
        savedPreferenceState = CloudKitAutoSyncAppSettingsState.capture()
        temporaryRoot = FileManager.default.temporaryDirectory
            .appending(path: "CloudKitAutoSyncTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        UserDefaults.standard.removeObject(forKey: AppSettings.KeysForTesting.iCloudSyncEnabled)
    }

    override func tearDownWithError() throws {
        UserDefaults.standard.removeObject(forKey: AppSettings.KeysForTesting.iCloudSyncEnabled)
        savedPreferenceState?.restore()
        savedPreferenceState = nil
        if let temporaryRoot {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }
        temporaryRoot = nil
        try super.tearDownWithError()
    }

    func testCreatingMomentSchedulesAutomaticCloudKitSyncWhenEnabled() async throws {
        AppSettings.iCloudSyncEnabled = true
        let database = try makeDatabase()
        let store = try await makeStore(database: database)
        store.cloudKitAutoSyncDelayNanoseconds = 10_000_000
        let syncCalled = expectation(description: "CloudKit auto sync called")
        var callCount = 0
        store.cloudKitSyncNowOverride = {
            callCount += 1
            syncCalled.fulfill()
            return Self.emptySyncResult()
        }

        let didCreate = await store.createPost(
            text: "Auto sync me",
            imageData: [],
            occurredAt: Date(timeIntervalSince1970: 1_800_100_000)
        )

        XCTAssertTrue(didCreate)
        await fulfillment(of: [syncCalled], timeout: 1)
        XCTAssertEqual(callCount, 1)
    }

    func testCreatingCommentEnqueuesCloudKitCommentWhenEnabled() async throws {
        AppSettings.iCloudSyncEnabled = true
        let database = try makeDatabase()
        let now = Date(timeIntervalSince1970: 1_800_102_000)
        try database.insert(Self.post(id: "post-comment", text: "Comment target", now: now))
        let store = try await makeStore(database: database)

        let comment = await store.createComment(postId: "post-comment", text: "sync this reply")

        let createdComment = try XCTUnwrap(comment)
        let changes = try database.fetchPendingCloudKitChanges(limit: 10)
        XCTAssertTrue(changes.contains(.comment, createdComment.id, .upsert, "comment_create"))
    }

    func testDeletingCommentEnqueuesCloudKitCommentDeleteWhenEnabled() async throws {
        AppSettings.iCloudSyncEnabled = true
        let database = try makeDatabase()
        let now = Date(timeIntervalSince1970: 1_800_102_500)
        try database.insert(Self.post(id: "post-comment-delete", text: "Comment target", now: now))
        let comment = TimelineComment(
            id: "comment-delete",
            postId: "post-comment-delete",
            text: "remove me",
            createdAt: now,
            updatedAt: now,
            serverVersion: nil,
            deletedAt: nil
        )
        try database.insert(comment)
        let store = try await makeStore(database: database)

        await store.deleteComment(comment)

        let changes = try database.fetchPendingCloudKitChanges(limit: 10)
        XCTAssertTrue(changes.contains(.comment, comment.id, .delete, "comment_delete"))
    }

    func testForegroundSyncRunsImmediatelyWhenEnabled() async throws {
        AppSettings.iCloudSyncEnabled = true
        let database = try makeDatabase()
        let store = try await makeStore(database: database)
        var callCount = 0
        store.cloudKitSyncNowOverride = {
            callCount += 1
            return Self.emptySyncResult()
        }

        await store.syncCloudKitPendingWorkIfNeeded(reason: "foreground")

        XCTAssertEqual(callCount, 1)
    }

    func testBootstrapCloudKitSyncRunsImmediatelyWhenEnabled() async throws {
        AppSettings.iCloudSyncEnabled = true
        let database = try makeDatabase()
        let store = try await makeStore(database: database)
        store.cloudKitAutoSyncDelayNanoseconds = 1_000_000_000
        let syncCalled = expectation(description: "CloudKit bootstrap sync called")
        var callCount = 0
        store.cloudKitSyncNowOverride = {
            callCount += 1
            syncCalled.fulfill()
            return Self.emptySyncResult()
        }

        store.syncCloudKitAfterBootstrapIfNeeded()

        await fulfillment(of: [syncCalled], timeout: 0.3)
        XCTAssertEqual(callCount, 1)
    }

    func testAutomaticCloudKitSyncRefreshesPublishedPreferencesAfterRemoteApply() async throws {
        AppSettings.iCloudSyncEnabled = true
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
        AppSettings.autoWeeklyReviewEnabled = false
        AppSettings.publishWeeklyReviewToMoments = false
        AppSettings.markdownMathRenderingEnabled = false
        AppSettings.markdownRemoteImagesEnabled = true
        AppSettings.markdownRawHTMLRenderingEnabled = false
        let database = try makeDatabase()
        let store = try await makeStore(database: database)
        XCTAssertTrue(store.showTagsInTimeline)
        XCTAssertFalse(store.showCheckInSummaries)
        XCTAssertTrue(store.memoryLinksEnabled)
        XCTAssertFalse(store.aiTitleAutoInsertEnabled)
        XCTAssertEqual(store.appAppearanceMode, .light)
        XCTAssertEqual(store.appLanguageMode, .english)
        XCTAssertEqual(store.aiLanguageMode, .english)
        XCTAssertFalse(store.aiAnalysisEnabled)
        XCTAssertFalse(store.aiExternalProcessingConsentAccepted)
        XCTAssertFalse(store.useTextProviderForTranscription)
        XCTAssertEqual(store.transcriptionProviderMode, .iPhoneOnDevice)
        XCTAssertFalse(store.autoWeeklyReviewEnabled)
        XCTAssertFalse(store.publishWeeklyReviewToMoments)
        XCTAssertFalse(store.markdownMathRenderingEnabled)
        XCTAssertTrue(store.markdownRemoteImagesEnabled)
        XCTAssertFalse(store.markdownRawHTMLRenderingEnabled)
        store.cloudKitSyncNowOverride = {
            AppSettings.showTagsInTimeline = false
            AppSettings.showCheckInSummaries = true
            AppSettings.memoryLinksEnabled = false
            AppSettings.aiTitleAutoInsertEnabled = true
            AppSettings.appAppearanceMode = .dark
            AppSettings.appLanguageMode = .simplifiedChinese
            AppSettings.aiLanguageMode = .chinese
            AppSettings.aiAnalysisEnabled = true
            AppSettings.aiExternalProcessingConsentAccepted = true
            AppSettings.useTextProviderForTranscription = true
            AppSettings.transcriptionProviderMode = .customOpenAICompatible
            AppSettings.autoWeeklyReviewEnabled = true
            AppSettings.publishWeeklyReviewToMoments = true
            AppSettings.markdownMathRenderingEnabled = true
            AppSettings.markdownRemoteImagesEnabled = false
            AppSettings.markdownRawHTMLRenderingEnabled = true
            return Self.emptySyncResult()
        }

        await store.syncCloudKitPendingWorkIfNeeded(reason: "foreground")

        XCTAssertFalse(store.showTagsInTimeline)
        XCTAssertTrue(store.showCheckInSummaries)
        XCTAssertFalse(store.memoryLinksEnabled)
        XCTAssertTrue(store.aiTitleAutoInsertEnabled)
        XCTAssertEqual(store.appAppearanceMode, .dark)
        XCTAssertEqual(store.appLanguageMode, .simplifiedChinese)
        XCTAssertEqual(store.aiLanguageMode, .chinese)
        XCTAssertTrue(store.aiAnalysisEnabled)
        XCTAssertTrue(store.aiExternalProcessingConsentAccepted)
        XCTAssertTrue(store.useTextProviderForTranscription)
        XCTAssertEqual(store.transcriptionProviderMode, .customOpenAICompatible)
        XCTAssertTrue(store.autoWeeklyReviewEnabled)
        XCTAssertTrue(store.publishWeeklyReviewToMoments)
        XCTAssertTrue(store.markdownMathRenderingEnabled)
        XCTAssertFalse(store.markdownRemoteImagesEnabled)
        XCTAssertTrue(store.markdownRawHTMLRenderingEnabled)
    }

    func testPreferenceChangeUsesShorterAutomaticCloudKitSyncDelay() async throws {
        AppSettings.iCloudSyncEnabled = true
        AppSettings.showTagsInTimeline = true
        let database = try makeDatabase()
        let store = try await makeStore(database: database)
        store.cloudKitAutoSyncDelayNanoseconds = 1_000_000_000
        store.cloudKitPreferenceSyncDelayNanoseconds = 10_000_000
        let syncCalled = expectation(description: "CloudKit preference sync called")
        store.cloudKitSyncNowOverride = {
            syncCalled.fulfill()
            return Self.emptySyncResult()
        }

        store.setShowTagsInTimeline(false)

        await fulfillment(of: [syncCalled], timeout: 0.5)
        store.cancelCloudKitAutoSync()
    }

    func testManualSyncSummaryIncludesFailedAndDeferredCounts() {
        let result = CloudKitManualSyncResult(
            uploadSummary: CloudKitSyncRunSummary(claimed: 3, saved: 0, deleted: 0, failed: 2),
            pullSummary: CloudKitPullRunSummary(
                fetchedModified: 4,
                fetchedDeleted: 0,
                appliedUpserts: 0,
                appliedDeletes: 0,
                deferred: 1,
                ignored: 0,
                failed: 1,
                moreComing: false
            )
        )

        XCTAssertEqual(
            result.displaySummary(language: .english),
            "Sync finished: 0 uploaded, 0 downloaded, 0 deleted, 3 failed, 1 deferred."
        )
    }

    func testAutomaticCloudKitSyncDoesNotRunWhenDisabled() async throws {
        AppSettings.iCloudSyncEnabled = false
        let database = try makeDatabase()
        let store = try await makeStore(database: database)
        store.cloudKitAutoSyncDelayNanoseconds = 10_000_000
        var callCount = 0
        store.cloudKitSyncNowOverride = {
            callCount += 1
            return Self.emptySyncResult()
        }

        store.scheduleCloudKitAutoSync(reason: "disabled")
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(callCount, 0)
    }

    func testFailedAutomaticCloudKitSyncRetries() async throws {
        AppSettings.iCloudSyncEnabled = true
        let database = try makeDatabase()
        let store = try await makeStore(database: database)
        store.cloudKitAutoSyncDelayNanoseconds = 10_000_000
        store.cloudKitAutoSyncRetryDelayNanoseconds = [10_000_000]
        let syncCalled = expectation(description: "CloudKit auto sync retried")
        syncCalled.expectedFulfillmentCount = 2
        var callCount = 0
        store.cloudKitSyncNowOverride = {
            callCount += 1
            syncCalled.fulfill()
            if callCount == 1 {
                throw AutoSyncTestError.firstAttemptFailed
            }
            return Self.emptySyncResult()
        }

        store.scheduleCloudKitAutoSync(reason: "retry")

        await fulfillment(of: [syncCalled], timeout: 1)
        XCTAssertEqual(callCount, 2)
    }

    func testForegroundSyncLoopPollsCloudKitWhileEnabled() async throws {
        AppSettings.iCloudSyncEnabled = true
        let database = try makeDatabase()
        let store = try await makeStore(database: database)
        store.cloudKitForegroundSyncIntervalNanoseconds = 10_000_000
        let syncCalled = expectation(description: "CloudKit foreground polling called")
        var callCount = 0
        var didFulfill = false
        store.cloudKitSyncNowOverride = {
            callCount += 1
            if callCount >= 2, !didFulfill {
                didFulfill = true
                syncCalled.fulfill()
            }
            return Self.emptySyncResult()
        }

        store.startCloudKitForegroundSyncLoop()

        await fulfillment(of: [syncCalled], timeout: 1)
        store.stopCloudKitForegroundSyncLoop()
        XCTAssertGreaterThanOrEqual(callCount, 2)
    }

    func testCancelDoesNotClearInFlightCloudKitSync() async throws {
        AppSettings.iCloudSyncEnabled = true
        let database = try makeDatabase()
        let store = try await makeStore(database: database)
        let syncStarted = expectation(description: "CloudKit sync started")
        var callCount = 0
        var finishSync: CheckedContinuation<CloudKitManualSyncResult, Error>?
        store.cloudKitSyncNowOverride = {
            callCount += 1
            syncStarted.fulfill()
            return try await withCheckedThrowingContinuation { continuation in
                finishSync = continuation
            }
        }

        let syncTask = Task {
            await store.syncCloudKitPendingWorkIfNeeded(reason: "foreground")
        }
        await fulfillment(of: [syncStarted], timeout: 1)

        store.cancelCloudKitAutoSync()
        await store.syncCloudKitPendingWorkIfNeeded(reason: "foreground_again")

        XCTAssertEqual(callCount, 1)
        finishSync?.resume(returning: Self.emptySyncResult())
        await syncTask.value
        store.cancelCloudKitAutoSync()
    }

    private func makeDatabase() throws -> LocalDatabase {
        try LocalDatabase.openForTesting(url: temporaryRoot.appending(path: "test.sqlite"))
    }

    private func makeStore(database: LocalDatabase) async throws -> TimelineStore {
        let store = TimelineStore()
        store.database = database
        try await store.reload()
        return store
    }

    private static func emptySyncResult() -> CloudKitManualSyncResult {
        CloudKitManualSyncResult(
            uploadSummary: CloudKitSyncRunSummary(claimed: 0, saved: 0, deleted: 0, failed: 0),
            pullSummary: CloudKitPullRunSummary(
                fetchedModified: 0,
                fetchedDeleted: 0,
                appliedUpserts: 0,
                appliedDeletes: 0,
                deferred: 0,
                ignored: 0,
                failed: 0,
                moreComing: false
            )
        )
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
}

private enum AutoSyncTestError: Error {
    case firstAttemptFailed
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

private struct CloudKitAutoSyncAppSettingsState {
    var showTagsInTimeline: Bool
    var showCheckInSummaries: Bool
    var memoryLinksEnabled: Bool
    var aiTitleAutoInsertEnabled: Bool
    var appAppearanceMode: AppAppearanceMode
    var appLanguageMode: AppLanguageMode
    var aiLanguageMode: AILanguageMode
    var aiAnalysisEnabled: Bool
    var aiExternalProcessingConsentAccepted: Bool
    var useTextProviderForTranscription: Bool
    var transcriptionProviderMode: TranscriptionProviderMode
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
            useTextProviderForTranscription: AppSettings.useTextProviderForTranscription,
            transcriptionProviderMode: AppSettings.transcriptionProviderMode,
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
        AppSettings.useTextProviderForTranscription = useTextProviderForTranscription
        AppSettings.transcriptionProviderMode = transcriptionProviderMode
        AppSettings.autoWeeklyReviewEnabled = autoWeeklyReviewEnabled
        AppSettings.publishWeeklyReviewToMoments = publishWeeklyReviewToMoments
        AppSettings.markdownMathRenderingEnabled = markdownMathRenderingEnabled
        AppSettings.markdownRemoteImagesEnabled = markdownRemoteImagesEnabled
        AppSettings.markdownRawHTMLRenderingEnabled = markdownRawHTMLRenderingEnabled
    }
}
