import XCTest
@testable import PrivateMoments

@MainActor
final class LocalArchiveExporterTests: XCTestCase {
    private var temporaryRoot: URL!

    override func setUpWithError() throws {
        temporaryRoot = FileManager.default.temporaryDirectory
            .appending(path: "private-moments-export-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        try KeychainStore.saveAIProviderAPIKey("SECRET_EXPORT_API_KEY", profileId: "export-provider")
        AppSettings.localWeeklyReviews = []
        AppSettings.welcomeSampleDeleted = false
    }

    override func tearDownWithError() throws {
        try? KeychainStore.clearAIProviderAPIKey(profileId: "export-provider")
        AppSettings.localWeeklyReviews = []
        AppSettings.welcomeSampleDeleted = false
        if let temporaryRoot {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }
    }

    func testExportArchiveOmitsCredentialsAndPrivateTranscriptText() async throws {
        let mediaURL = temporaryRoot.appending(path: "voice.m4a")
        try Data("local media bytes".utf8).write(to: mediaURL)

        let now = Date(timeIntervalSince1970: 1_775_000_000)
        let post = TimelinePost(
            id: "post-export",
            text: "Private journal text",
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
            syncStatus: "local",
            deletedAt: nil
        )
        let media = TimelineMedia(
            id: "media-export",
            postId: post.id,
            kind: "audio",
            localCompressedPath: mediaURL.path,
            localOriginalStagingPath: nil,
            localThumbnailPath: nil,
            remoteCompressedPath: nil,
            remoteOriginalPath: nil,
            remoteThumbnailPath: nil,
            originalPreserved: false,
            uploadStatus: "local",
            mimeType: "audio/mp4",
            durationSeconds: 12,
            transcriptionText: "SECRET_PRIVATE_TRANSCRIPT",
            transcriptionStatus: "ready",
            transcriptionError: nil,
            transcriptionUpdatedAt: now,
            sortOrder: 0,
            checksum: nil,
            createdAt: now,
            updatedAt: now
        )
        let item = TimelineItem(post: post, media: [media], comments: [], aiSummaries: [], tags: [])
        let store = TimelineStore()
        store.items = [item]

        let result = try await LocalArchiveExporter.export(from: store)
        let data = try Data(contentsOf: result.url)

        XCTAssertEqual(result.mediaFilesIncluded, 1)
        XCTAssertEqual(result.missingMediaCount, 0)
        XCTAssertContains(data, "manifest.json")
        XCTAssertContains(data, "\"containsProviderAPIKeys\" : false")
        XCTAssertContains(data, "\"containsPrivateTranscriptText\" : false")
        XCTAssertContains(data, "\"transcriptLength\" : 25")
        XCTAssertFalse(data.containsString("SECRET_EXPORT_API_KEY"))
        XCTAssertFalse(data.containsString("SECRET_PRIVATE_TRANSCRIPT"))
        XCTAssertFalse(data.containsString("\"transcriptionText\""))
    }

    func testExportArchiveExcludesWelcomeSampleTeachingData() async throws {
        let now = Date(timeIntervalSince1970: 1_775_000_010)
        let database = try LocalDatabase.openForTesting(url: temporaryRoot.appending(path: "welcome-export.sqlite"))
        _ = try database.seedWelcomeSampleIfNeeded(language: .english, now: now)

        let store = TimelineStore()
        store.items = try database.fetchTimelineItems()
        store.tags = try database.fetchTags(includeArchived: true)

        let result = try await LocalArchiveExporter.export(from: store)
        let data = try Data(contentsOf: result.url)

        XCTAssertEqual(result.mediaFilesIncluded, 0)
        XCTAssertEqual(result.missingMediaCount, 0)
        XCTAssertContains(data, "\"posts\" : 0")
        XCTAssertFalse(data.containsString(WelcomeSampleContent.postId))
        XCTAssertFalse(data.containsString(WelcomeSampleContent.audioMediaId))
        XCTAssertFalse(data.containsString(WelcomeSampleContent.summaryId))
    }

    func testPreviewSummarizesLocalArchive() async throws {
        let result = try await makeTextOnlyArchive()

        let preview = try LocalArchiveImporter.preview(archiveURL: result.url)

        XCTAssertEqual(preview.counts.posts, 1)
        XCTAssertEqual(preview.counts.comments, 1)
        XCTAssertEqual(preview.counts.postMedia, 0)
        XCTAssertEqual(preview.counts.mediaFilesIncluded, 0)
        XCTAssertEqual(preview.counts.missingMedia, 0)
        XCTAssertFalse(preview.privacy.containsProviderAPIKeys)
        XCTAssertFalse(preview.privacy.containsPrivateTranscriptText)
    }

    func testImportRestoresArchiveIntoEmptyDatabase() async throws {
        let result = try await makeTextOnlyArchive(weeklyReviews: [makeReview(id: "review-import")])
        let database = try LocalDatabase.openForTesting(url: temporaryRoot.appending(path: "restore.sqlite"))

        let importResult = try LocalArchiveImporter.importArchive(from: result.url, into: database)

        XCTAssertEqual(importResult.imported.posts, 1)
        XCTAssertEqual(importResult.imported.comments, 1)
        XCTAssertEqual(importResult.imported.weeklyReviews, 1)

        let items = try database.fetchTimelineItems()
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.post.id, "post-import")
        XCTAssertEqual(items.first?.post.text, "Import me")
        XCTAssertEqual(items.first?.comments.map(\.text), ["Imported comment"])
        XCTAssertTrue(try database.fetchPendingOperations().isEmpty)
        XCTAssertEqual(AppSettings.localWeeklyReviews.map(\.id), ["review-import"])
    }

    func testImportTreatsWelcomeSampleAsTeachingDataOnEmptyTarget() async throws {
        let result = try await makeTextOnlyArchive()
        let database = try LocalDatabase.openForTesting(url: temporaryRoot.appending(path: "welcome-only-target.sqlite"))
        _ = try database.seedWelcomeSampleIfNeeded(
            language: .english,
            now: Date(timeIntervalSince1970: 1_775_000_090)
        )

        XCTAssertNotNil(try database.fetchTimelineItem(postId: WelcomeSampleContent.postId))

        let importResult = try LocalArchiveImporter.importArchive(from: result.url, into: database)

        XCTAssertEqual(importResult.imported.posts, 1)
        let items = try database.fetchTimelineItems()
        XCTAssertEqual(items.map(\.post.id), ["post-import"])
        XCTAssertTrue(AppSettings.welcomeSampleDeleted)
    }

    func testImportRejectsNonEmptyDatabase() async throws {
        let result = try await makeTextOnlyArchive()
        let database = try LocalDatabase.openForTesting(url: temporaryRoot.appending(path: "non-empty.sqlite"))
        let now = Date(timeIntervalSince1970: 1_775_000_050)
        try database.insert(
            TimelinePost(
                id: "existing-post",
                text: "Already here",
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
                syncStatus: "local",
                deletedAt: nil
            )
        )

        XCTAssertThrowsError(try LocalArchiveImporter.importArchive(from: result.url, into: database)) { error in
            guard case LocalArchiveImportError.targetDatabaseNotEmpty = error else {
                return XCTFail("Expected targetDatabaseNotEmpty, got \(error)")
            }
        }
        XCTAssertEqual(try database.fetchTimelineItems().map(\.post.id), ["existing-post"])
    }

    func testImportRejectsExistingLocalWeeklyReviews() async throws {
        let result = try await makeTextOnlyArchive()
        let database = try LocalDatabase.openForTesting(url: temporaryRoot.appending(path: "reviews-non-empty.sqlite"))
        AppSettings.localWeeklyReviews = [makeReview(id: "existing-review")]

        XCTAssertThrowsError(try LocalArchiveImporter.importArchive(from: result.url, into: database)) { error in
            guard case LocalArchiveImportError.targetDatabaseNotEmpty = error else {
                return XCTFail("Expected targetDatabaseNotEmpty, got \(error)")
            }
        }
        XCTAssertEqual(AppSettings.localWeeklyReviews.map(\.id), ["existing-review"])
    }

    private func makeTextOnlyArchive(weeklyReviews: [ReviewPayload] = []) async throws -> LocalArchiveExportResult {
        let now = Date(timeIntervalSince1970: 1_775_000_100)
        let post = TimelinePost(
            id: "post-import",
            text: "Import me",
            isFavorite: true,
            isPinned: false,
            pinnedAt: nil,
            aiTagProcessedAt: nil,
            tagsUserEditedAt: nil,
            occurredAt: now,
            localCreatedAt: now,
            localUpdatedAt: now,
            localEditedAt: nil,
            serverVersion: nil,
            syncStatus: "local",
            deletedAt: nil
        )
        let comment = TimelineComment(
            id: "comment-import",
            postId: post.id,
            text: "Imported comment",
            createdAt: now,
            updatedAt: now,
            serverVersion: nil,
            deletedAt: nil
        )
        let item = TimelineItem(post: post, media: [], comments: [comment], aiSummaries: [], tags: [])
        let store = TimelineStore()
        store.items = [item]
        store.weeklyReviews = weeklyReviews
        return try await LocalArchiveExporter.export(from: store)
    }

    private func makeReview(id: String) -> ReviewPayload {
        let timestamp = "2026-05-31T00:00:00Z"
        return ReviewPayload(
            id: id,
            kind: "weekly",
            rangeMode: "weekly",
            rangeStart: timestamp,
            rangeEnd: timestamp,
            status: "ready",
            trigger: "test",
            content: ReviewContentPayload(
                title: "Test Review",
                subtitle: nil,
                bodyMarkdown: "Review body",
                oneLiner: nil,
                keywords: nil,
                themes: nil,
                emotionalReflection: nil,
                progressAndOpenLoops: nil,
                rhythm: nil,
                notableMoments: nil,
                gentleSuggestions: nil,
                uncertainty: nil
            ),
            promptVersion: "weekly-review-v1",
            provider: nil,
            model: nil,
            language: nil,
            errorCode: nil,
            errorMessage: nil,
            generatedAt: timestamp,
            regeneratedFromReviewId: nil,
            publishedPostId: nil,
            createdAt: timestamp,
            updatedAt: timestamp,
            deletedAt: nil,
            feedback: nil
        )
    }

    private func XCTAssertContains(
        _ data: Data,
        _ string: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(data.containsString(string), "Expected archive bytes to contain \(string)", file: file, line: line)
    }
}

private extension Data {
    func containsString(_ string: String) -> Bool {
        range(of: Data(string.utf8)) != nil
    }
}
