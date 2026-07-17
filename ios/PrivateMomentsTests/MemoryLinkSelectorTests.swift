import XCTest
@testable import PrivateMoments

final class MemoryLinkSelectorTests: XCTestCase {
    private var calendar: Calendar!
    private var now: Date!

    override func setUp() {
        super.setUp()
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        self.calendar = calendar
        self.now = date(year: 2026, month: 5, day: 31, hour: 10)
    }

    func testSelectsMeaningfulOldAudioSummaryForToday() {
        let oldAudio = item(
            id: "old-audio",
            text: "## Local-first archive voice note\n" + String(repeating: "A useful reflection about private capture, sync recovery, and what changed in the habit. ", count: 3),
            occurredAt: date(year: 2026, month: 2, day: 28, hour: 9),
            isFavorite: true,
            media: [media(id: "old-audio-media", postId: "old-audio", kind: "audio")],
            comments: [comment(id: "old-audio-comment", postId: "old-audio")],
            summaries: [summary(id: "old-audio-summary", postId: "old-audio", mediaId: "old-audio-media")],
            tags: [topicTag(postId: "old-audio")]
        )
        let weakText = item(
            id: "weak-text",
            text: "A tiny note.",
            occurredAt: date(year: 2026, month: 2, day: 28, hour: 12)
        )

        let link = MemoryLinkSelector.select(
            from: [weakText, oldAudio],
            history: [],
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(link?.postId, "old-audio")
        XCTAssertEqual(link?.sourceWindow, .threeMonths)
        XCTAssertEqual(link?.title, "3 months ago today")
        XCTAssertEqual(link?.subtitle, "Local-first archive voice note")
        XCTAssertGreaterThanOrEqual(link?.score ?? 0, 50)
    }

    func testDoesNotShowWhenFrequencyLimitWasReachedThisWeek() {
        let oldAudio = item(
            id: "old-audio",
            text: "## Local-first archive voice note\n" + String(repeating: "A useful reflection about private capture. ", count: 5),
            occurredAt: date(year: 2026, month: 2, day: 28, hour: 9),
            media: [media(id: "old-audio-media", postId: "old-audio", kind: "audio")],
            summaries: [summary(id: "old-audio-summary", postId: "old-audio", mediaId: "old-audio-media")]
        )
        let history = [
            historyEntry(postId: "shown-a", shownDate: date(year: 2026, month: 5, day: 26, hour: 0)),
            historyEntry(postId: "shown-b", shownDate: date(year: 2026, month: 5, day: 28, hour: 0)),
        ]

        let link = MemoryLinkSelector.select(
            from: [oldAudio],
            history: history,
            now: now,
            calendar: calendar
        )

        XCTAssertNil(link)
    }

    func testKeepsSameLinkForTheSameDayAfterItWasShown() {
        let oldAudio = item(
            id: "old-audio",
            text: "## Local-first archive voice note\n" + String(repeating: "A useful reflection about private capture. ", count: 5),
            occurredAt: date(year: 2026, month: 2, day: 28, hour: 9),
            media: [media(id: "old-audio-media", postId: "old-audio", kind: "audio")],
            summaries: [summary(id: "old-audio-summary", postId: "old-audio", mediaId: "old-audio-media")]
        )
        let betterOldText = item(
            id: "better-old-text",
            text: "## Better long reflection\n" + String(repeating: "This is a longer text entry that would otherwise score higher today. ", count: 6),
            occurredAt: date(year: 2026, month: 2, day: 28, hour: 8),
            isFavorite: true,
            comments: [comment(id: "better-comment", postId: "better-old-text")]
        )
        let history = [
            historyEntry(postId: "old-audio", shownDate: calendar.startOfDay(for: now))
        ]

        let link = MemoryLinkSelector.select(
            from: [betterOldText, oldAudio],
            history: history,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(link?.postId, "old-audio")
    }

    private func item(
        id: String,
        text: String,
        occurredAt: Date,
        isFavorite: Bool = false,
        isPinned: Bool = false,
        media: [TimelineMedia] = [],
        comments: [TimelineComment] = [],
        summaries: [TimelineAISummary] = [],
        tags: [TimelineAssignedTag] = []
    ) -> TimelineItem {
        TimelineItem(
            post: TimelinePost(
                id: id,
                text: text,
                isFavorite: isFavorite,
                isPinned: isPinned,
                pinnedAt: isPinned ? occurredAt : nil,
                aiTagProcessedAt: nil,
                tagsUserEditedAt: nil,
                occurredAt: occurredAt,
                localCreatedAt: occurredAt,
                localUpdatedAt: occurredAt,
                localEditedAt: nil,
                serverVersion: nil,
                syncStatus: "synced",
                deletedAt: nil
            ),
            media: media,
            comments: comments,
            aiSummaries: summaries,
            tags: tags
        )
    }

    private func media(id: String, postId: String, kind: String) -> TimelineMedia {
        TimelineMedia(
            id: id,
            postId: postId,
            kind: kind,
            localCompressedPath: "",
            localOriginalStagingPath: nil,
            localThumbnailPath: nil,
            remoteCompressedPath: nil,
            remoteOriginalPath: nil,
            remoteThumbnailPath: nil,
            originalPreserved: false,
            uploadStatus: "uploaded",
            mimeType: nil,
            durationSeconds: kind == "audio" ? 90 : nil,
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

    private func comment(id: String, postId: String) -> TimelineComment {
        TimelineComment(
            id: id,
            postId: postId,
            text: "Worth revisiting.",
            createdAt: now,
            updatedAt: now,
            serverVersion: nil,
            deletedAt: nil
        )
    }

    private func summary(id: String, postId: String, mediaId: String) -> TimelineAISummary {
        TimelineAISummary(
            id: id,
            postId: postId,
            mediaId: mediaId,
            status: "ready",
            format: "document-v1",
            language: "en",
            overview: "A structured summary.",
            keyPoints: ["One", "Two"],
            sections: [],
            summaryText: nil,
            documentTitle: "Local-first archive voice note",
            oneLiner: "A useful summary.",
            documentBlocks: [],
            inputTranscriptLength: 260,
            inputDurationSeconds: 90,
            promptVersion: "media-summary-v4",
            provider: "test",
            model: "fixture",
            errorCode: nil,
            errorMessage: nil,
            createdAt: now,
            updatedAt: now,
            deletedAt: nil
        )
    }

    private func topicTag(postId: String) -> TimelineAssignedTag {
        let tag = TimelineTag(
            id: "tag-topic-local-first",
            type: "topic",
            name: "local-first",
            normalizedName: "local-first",
            colorHex: nil,
            isDefault: false,
            isArchived: false,
            aiUsableAsPrimary: false,
            createdAt: now,
            updatedAt: now,
            archivedAt: nil
        )
        return TimelineAssignedTag(
            id: "assigned-\(postId)",
            postId: postId,
            tagId: tag.id,
            role: "topic",
            source: "manual",
            confidence: nil,
            aiSummaryId: nil,
            createdAt: now,
            updatedAt: now,
            deletedAt: nil,
            tag: tag
        )
    }

    private func historyEntry(postId: String, shownDate: Date) -> MemoryLinkHistoryEntry {
        MemoryLinkHistoryEntry(
            id: "history-\(postId)-\(Int(shownDate.timeIntervalSince1970))",
            postId: postId,
            shownDate: calendar.startOfDay(for: shownDate),
            sourceWindow: .threeMonths,
            score: 80,
            shownAt: shownDate,
            openedAt: nil,
            dismissedAt: nil
        )
    }

    private func date(year: Int, month: Int, day: Int, hour: Int) -> Date {
        let components = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour
        )
        return components.date!
    }
}
