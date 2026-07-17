import SQLite3
import XCTest
@testable import PrivateMoments

final class WelcomeSampleTests: XCTestCase {
    private var temporaryRoot: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryRoot = FileManager.default.temporaryDirectory
            .appending(path: "WelcomeSampleTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryRoot {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }
        try super.tearDownWithError()
    }

    func testSeedWelcomeSampleCreatesLocalOnlyTeachingMoment() throws {
        let database = try LocalDatabase.openForTesting(url: temporaryRoot.appending(path: "welcome.sqlite"))
        let now = Date(timeIntervalSince1970: 1_780_000_000)

        let didSeed = try database.seedWelcomeSampleIfNeeded(language: .english, now: now)

        XCTAssertTrue(didSeed)
        let item = try XCTUnwrap(database.fetchTimelineItem(postId: WelcomeSampleContent.postId))
        XCTAssertTrue(WelcomeSampleContent.isSample(item))
        XCTAssertEqual(item.media.map(\.id), [WelcomeSampleContent.audioMediaId])
        XCTAssertEqual(item.media.first?.uploadStatus, "synced")
        XCTAssertEqual(item.comments.map(\.id), [WelcomeSampleContent.commentId])
        XCTAssertEqual(item.aiSummaries.map(\.id), [WelcomeSampleContent.summaryId])
        XCTAssertEqual(item.tags.map(\.tagId).sorted(), WelcomeSampleContent.topicTagIds.sorted())
        XCTAssertTrue(try database.fetchPendingOperations().isEmpty)
        XCTAssertEqual(try database.pendingUploadCount(), 0)
    }

    func testWelcomeSampleDoesNotSeedIntoNonEmptyLibrary() throws {
        let database = try LocalDatabase.openForTesting(url: temporaryRoot.appending(path: "non-empty.sqlite"))
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        try database.insert(
            TimelinePost(
                id: "user-post",
                text: "Real user data",
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
        )

        let didSeed = try database.seedWelcomeSampleIfNeeded(language: .simplifiedChinese, now: now)

        XCTAssertFalse(didSeed)
        XCTAssertNil(try database.fetchTimelineItem(postId: WelcomeSampleContent.postId))
    }

    func testWelcomeSampleLocalMutationsStayOutOfOutbox() throws {
        let database = try LocalDatabase.openForTesting(url: temporaryRoot.appending(path: "mutations.sqlite"))
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        _ = try database.seedWelcomeSampleIfNeeded(language: .english, now: now)

        try database.updateWelcomeSampleFavorite(isFavorite: true, updatedAt: now.addingTimeInterval(5))
        try database.updateWelcomeSamplePinned(isPinned: true, pinnedAt: now.addingTimeInterval(6), updatedAt: now.addingTimeInterval(6))
        try database.softDeleteWelcomeSample(deletedAt: now.addingTimeInterval(7))

        XCTAssertNil(try database.fetchTimelineItem(postId: WelcomeSampleContent.postId))
        XCTAssertTrue(try database.fetchPendingOperations().isEmpty)
        XCTAssertEqual(try database.pendingUploadCount(), 0)
    }

    func testRefreshesExistingWelcomeSampleTeachingText() throws {
        let database = try LocalDatabase.openForTesting(url: temporaryRoot.appending(path: "refresh.sqlite"))
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        _ = try database.seedWelcomeSampleIfNeeded(language: .english, now: now)
        try overwriteWelcomeSampleText("## Welcome to Moments\n\nOld onboarding body", in: database)
        try overwriteWelcomeSampleCommentText("Old long comment body", in: database)

        let didRefresh = try database.refreshWelcomeSampleContentIfPresent(
            language: .simplifiedChinese,
            now: now.addingTimeInterval(10)
        )

        XCTAssertTrue(didRefresh)
        let item = try XCTUnwrap(database.fetchTimelineItem(postId: WelcomeSampleContent.postId))
        XCTAssertEqual(item.post.text, WelcomeSampleContent.postText(language: .simplifiedChinese))
        XCTAssertEqual(item.comments.first?.text, WelcomeSampleContent.comment(language: .simplifiedChinese, now: now).text)
        XCTAssertTrue(item.post.text.contains("# 你的第一条 Moment"))
        XCTAssertTrue(item.post.text.contains("## 一条记录可以很轻"))
        XCTAssertFalse(item.post.text.contains("## AI Summary"))
        XCTAssertTrue(try database.fetchPendingOperations().isEmpty)
        XCTAssertEqual(try database.pendingUploadCount(), 0)
    }

    func testWelcomeSampleTeachingTextFocusesOnPrivateTimeline() {
        let englishText = WelcomeSampleContent.postText(language: .english)
        let chineseText = WelcomeSampleContent.postText(language: .simplifiedChinese)

        XCTAssertTrue(englishText.contains("# Your first Moment"))
        XCTAssertTrue(englishText.contains("## A moment can stay light"))
        XCTAssertFalse(englishText.contains("## AI Summary"))
        XCTAssertFalse(englishText.contains("Small gestures"))
        XCTAssertFalse(englishText.contains("swipe left"))
        XCTAssertTrue(chineseText.contains("# 你的第一条 Moment"))
        XCTAssertTrue(chineseText.contains("## 一条记录可以很轻"))
        XCTAssertFalse(chineseText.contains("## AI Summary"))
        XCTAssertFalse(chineseText.contains("小操作"))
        XCTAssertFalse(chineseText.contains("左滑"))
    }

    func testWelcomeSampleSummaryKeepsAISettingsGuidanceConcise() {
        let englishSummary = WelcomeSampleContent.summary(language: .english, now: Date())
        let chineseSummary = WelcomeSampleContent.summary(language: .simplifiedChinese, now: Date())

        XCTAssertEqual(englishSummary.documentBlocks.count, 3)
        XCTAssertEqual(chineseSummary.documentBlocks.count, 3)
        XCTAssertTrue(englishSummary.oneLiner?.contains("Settings > AI & Analysis") ?? false)
        XCTAssertTrue(chineseSummary.oneLiner?.contains("Settings > AI & Analysis") ?? false)
        XCTAssertEqual(settingsGuidanceCount(in: englishSummary), 1)
        XCTAssertEqual(settingsGuidanceCount(in: chineseSummary), 1)
        XCTAssertFalse(englishSummary.documentBlocks.contains { $0.text.contains("Settings > AI & Analysis") })
        XCTAssertFalse(chineseSummary.documentBlocks.contains { $0.text.contains("Settings > AI & Analysis") })
        XCTAssertEqual(englishSummary.keyPoints.count, 2)
        XCTAssertEqual(chineseSummary.keyPoints.count, 2)
        XCTAssertLessThanOrEqual(englishSummary.documentBlocks.flatMap(\.items).count, 2)
        XCTAssertLessThanOrEqual(chineseSummary.documentBlocks.flatMap(\.items).count, 2)
    }

    func testRefreshesExistingWelcomeSampleSummaryContent() throws {
        let database = try LocalDatabase.openForTesting(url: temporaryRoot.appending(path: "summary-refresh.sqlite"))
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        _ = try database.seedWelcomeSampleIfNeeded(language: .english, now: now)
        try overwriteWelcomeSampleSummary(
            oneLiner: "AI summaries are optional; configure them later in Settings > AI & Analysis.",
            documentBlocks: [
                TimelineAISummaryBlock(kind: "heading", level: 2, text: "Where to set it up", items: []),
                TimelineAISummaryBlock(kind: "paragraph", level: 0, text: "Use Settings > AI & Analysis for Base URL, API key, and model.", items: []),
                TimelineAISummaryBlock(kind: "callout", level: 0, text: "This sample was not sent to any AI provider.", items: [])
            ],
            in: database
        )

        let didRefresh = try database.refreshWelcomeSampleContentIfPresent(
            language: .english,
            now: now.addingTimeInterval(10)
        )

        XCTAssertTrue(didRefresh)
        let item = try XCTUnwrap(database.fetchTimelineItem(postId: WelcomeSampleContent.postId))
        let summary = try XCTUnwrap(item.aiSummaries.first)
        XCTAssertEqual(settingsGuidanceCount(in: summary), 1)
        XCTAssertFalse(summary.documentBlocks.contains { $0.text.contains("Settings > AI & Analysis") })
        XCTAssertTrue(try database.fetchPendingOperations().isEmpty)
        XCTAssertEqual(try database.pendingUploadCount(), 0)
    }

    private func overwriteWelcomeSampleText(_ text: String, in database: LocalDatabase) throws {
        let statement = try database.prepare(
            """
            UPDATE local_posts
            SET text = ?
            WHERE id = ?
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try database.bind(text, to: 1, in: statement)
        try database.bind(WelcomeSampleContent.postId, to: 2, in: statement)
        try database.stepDone(statement)
    }

    private func overwriteWelcomeSampleCommentText(_ text: String, in database: LocalDatabase) throws {
        let statement = try database.prepare(
            """
            UPDATE local_comments
            SET text = ?
            WHERE id = ?
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try database.bind(text, to: 1, in: statement)
        try database.bind(WelcomeSampleContent.commentId, to: 2, in: statement)
        try database.stepDone(statement)
    }

    private func overwriteWelcomeSampleSummary(
        oneLiner: String,
        documentBlocks: [TimelineAISummaryBlock],
        in database: LocalDatabase
    ) throws {
        let data = try JSONEncoder().encode(documentBlocks)
        let blocksJson = String(decoding: data, as: UTF8.self)
        let statement = try database.prepare(
            """
            UPDATE local_ai_summaries
            SET oneLiner = ?,
                overview = ?,
                documentBlocksJson = ?
            WHERE id = ?
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try database.bind(oneLiner, to: 1, in: statement)
        try database.bind(oneLiner, to: 2, in: statement)
        try database.bind(blocksJson, to: 3, in: statement)
        try database.bind(WelcomeSampleContent.summaryId, to: 4, in: statement)
        try database.stepDone(statement)
    }

    private func settingsGuidanceCount(in summary: TimelineAISummary) -> Int {
        let text = ([
            summary.oneLiner,
            summary.summaryText
        ] + summary.keyPoints.map(Optional.some)
            + summary.documentBlocks.flatMap { block in
                [block.text] + block.items
            }.map(Optional.some))
            .compactMap { $0 }
            .joined(separator: "\n")

        return text.components(separatedBy: "Settings > AI & Analysis").count - 1
    }
}
