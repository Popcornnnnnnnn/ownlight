import Foundation
import SQLite3

extension LocalDatabase {
    func seedWelcomeSampleIfNeeded(language: AppResolvedLanguage, now: Date = Date()) throws -> Bool {
        if try welcomeSampleExists() {
            _ = try refreshWelcomeSampleContentIfPresent(language: language, now: now)
            return false
        }

        guard try isLibraryEmptyForWelcomeSample() else {
            return false
        }

        let post = TimelinePost(
            id: WelcomeSampleContent.postId,
            text: WelcomeSampleContent.postText(language: language),
            isFavorite: false,
            isPinned: false,
            pinnedAt: nil,
            aiTagProcessedAt: now,
            tagsUserEditedAt: nil,
            occurredAt: now,
            localCreatedAt: now,
            localUpdatedAt: now,
            localEditedAt: nil,
            serverVersion: nil,
            syncStatus: "synced",
            deletedAt: nil
        )
        let media = WelcomeSampleContent.audioMedia(now: now)
        let summary = WelcomeSampleContent.summary(language: language, now: now)
        let comment = WelcomeSampleContent.comment(language: language, now: now)
        let tags = WelcomeSampleContent.topicTags(language: language, now: now)

        try transaction {
            try insert(post)
            try insert(media)
            try insert(comment)
            try upsertAISummary(summary)

            for tag in tags {
                try upsertAssignedTag(
                    TimelineAssignedTag(
                        id: "welcome-sample-assignment-\(tag.id)",
                        postId: post.id,
                        tagId: tag.id,
                        role: "topic",
                        source: "sample",
                        confidence: 1,
                        aiSummaryId: summary.id,
                        createdAt: now,
                        updatedAt: now,
                        deletedAt: nil,
                        tag: tag
                    )
                )
            }
        }

        return true
    }

    @discardableResult
    func refreshWelcomeSampleContentIfPresent(language: AppResolvedLanguage, now: Date = Date()) throws -> Bool {
        guard try activeWelcomeSampleExists() else {
            return false
        }

        var didRefresh = false
        try transaction {
            didRefresh = try refreshWelcomeSamplePostText(language: language, now: now) || didRefresh
            didRefresh = try refreshWelcomeSampleCommentText(language: language, now: now) || didRefresh
            didRefresh = try refreshWelcomeSampleSummary(language: language, now: now) || didRefresh
        }

        return didRefresh
    }

    func updateWelcomeSampleFavorite(isFavorite: Bool, updatedAt: Date) throws {
        guard try welcomeSampleExists() else {
            return
        }

        let statement = try prepare(
            """
            UPDATE local_posts
            SET isFavorite = ?,
                syncStatus = 'synced',
                localUpdatedAt = ?
            WHERE id = ?
              AND deletedAt IS NULL
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(isFavorite ? 1 : 0, to: 1, in: statement)
        try bind(updatedAt, to: 2, in: statement)
        try bind(WelcomeSampleContent.postId, to: 3, in: statement)
        try stepDone(statement)
    }

    func updateWelcomeSamplePinned(isPinned: Bool, pinnedAt: Date?, updatedAt: Date) throws {
        guard try welcomeSampleExists() else {
            return
        }

        let statement = try prepare(
            """
            UPDATE local_posts
            SET isPinned = ?,
                pinnedAt = ?,
                syncStatus = 'synced',
                localUpdatedAt = ?
            WHERE id = ?
              AND deletedAt IS NULL
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(isPinned ? 1 : 0, to: 1, in: statement)
        try bind(isPinned ? pinnedAt : nil, to: 2, in: statement)
        try bind(updatedAt, to: 3, in: statement)
        try bind(WelcomeSampleContent.postId, to: 4, in: statement)
        try stepDone(statement)
    }

    func insertWelcomeSampleComment(_ comment: TimelineComment) throws {
        guard WelcomeSampleContent.isSamplePostId(comment.postId) else {
            return
        }

        try insert(comment, syncStatus: "synced")
    }

    func softDeleteWelcomeSampleComment(commentId: String, deletedAt: Date) throws {
        let isKnownSampleComment = WelcomeSampleContent.isSampleCommentId(commentId)
        let existsInSamplePost = try sampleCommentExists(commentId: commentId)
        guard isKnownSampleComment || existsInSamplePost else {
            return
        }

        let statement = try prepare(
            """
            UPDATE local_comments
            SET deletedAt = ?,
                updatedAt = ?,
                syncStatus = 'synced'
            WHERE id = ?
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(deletedAt, to: 1, in: statement)
        try bind(deletedAt, to: 2, in: statement)
        try bind(commentId, to: 3, in: statement)
        try stepDone(statement)
    }

    func softDeleteWelcomeSample(deletedAt: Date) throws {
        guard try welcomeSampleExists() else {
            return
        }

        try transaction {
            try updateWelcomeSampleDeletion(deletedAt: deletedAt)
            try softDeleteWelcomeSampleChildren(deletedAt: deletedAt)
        }
    }

    @discardableResult
    func softDeleteWelcomeSampleForArchiveImport(deletedAt: Date) throws -> Bool {
        guard try welcomeSampleExists() else {
            return false
        }

        try updateWelcomeSampleDeletion(deletedAt: deletedAt)
        try softDeleteWelcomeSampleChildren(deletedAt: deletedAt)
        return true
    }

    func realLocalObjectCountIgnoringWelcomeSample() throws -> Int {
        try count(
            """
            SELECT
                (SELECT COUNT(*) FROM local_posts WHERE id <> ?) +
                (SELECT COUNT(*) FROM local_media WHERE postId <> ? AND id <> ?) +
                (SELECT COUNT(*) FROM local_comments WHERE postId <> ? AND id <> ?) +
                (SELECT COUNT(*) FROM local_ai_summaries WHERE postId <> ? AND id <> ?) +
                (SELECT COUNT(*) FROM local_post_tags WHERE postId <> ? AND tagId NOT LIKE ?) +
                (SELECT COUNT(*) FROM local_tag_aliases WHERE tagId NOT LIKE ? AND id NOT LIKE ?) +
                (SELECT COUNT(*) FROM local_tags WHERE isDefault = 0 AND id NOT LIKE ?) +
                (SELECT COUNT(*) FROM local_checkin_items) +
                (SELECT COUNT(*) FROM local_checkin_entries) +
                (SELECT COUNT(*) FROM local_checkin_media) +
                (SELECT COUNT(*) FROM local_checkin_ai_summaries) +
                (SELECT COUNT(*) FROM outbox_operations)
            """,
            bind: { statement in
                try self.bind(WelcomeSampleContent.postId, to: 1, in: statement)
                try self.bind(WelcomeSampleContent.postId, to: 2, in: statement)
                try self.bind(WelcomeSampleContent.audioMediaId, to: 3, in: statement)
                try self.bind(WelcomeSampleContent.postId, to: 4, in: statement)
                try self.bind(WelcomeSampleContent.commentId, to: 5, in: statement)
                try self.bind(WelcomeSampleContent.postId, to: 6, in: statement)
                try self.bind(WelcomeSampleContent.summaryId, to: 7, in: statement)
                try self.bind(WelcomeSampleContent.postId, to: 8, in: statement)
                try self.bind("welcome-sample-%", to: 9, in: statement)
                try self.bind("welcome-sample-%", to: 10, in: statement)
                try self.bind("welcome-sample-%", to: 11, in: statement)
                try self.bind("welcome-sample-%", to: 12, in: statement)
            }
        )
    }

    private func welcomeSampleExists() throws -> Bool {
        try count(
            "SELECT COUNT(*) FROM local_posts WHERE id = ?",
            bind: { statement in
                try self.bind(WelcomeSampleContent.postId, to: 1, in: statement)
            }
        ) > 0
    }

    private func activeWelcomeSampleExists() throws -> Bool {
        try count(
            "SELECT COUNT(*) FROM local_posts WHERE id = ? AND deletedAt IS NULL",
            bind: { statement in
                try self.bind(WelcomeSampleContent.postId, to: 1, in: statement)
            }
        ) > 0
    }

    private func refreshWelcomeSamplePostText(language: AppResolvedLanguage, now: Date) throws -> Bool {
        let nextText = WelcomeSampleContent.postText(language: language)
        let statement = try prepare(
            """
            UPDATE local_posts
            SET text = ?,
                syncStatus = 'synced',
                localUpdatedAt = ?
            WHERE id = ?
              AND deletedAt IS NULL
              AND text <> ?
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(nextText, to: 1, in: statement)
        try bind(now, to: 2, in: statement)
        try bind(WelcomeSampleContent.postId, to: 3, in: statement)
        try bind(nextText, to: 4, in: statement)
        try stepDone(statement)
        return sqlite3_changes(handle) > 0
    }

    private func refreshWelcomeSampleCommentText(language: AppResolvedLanguage, now: Date) throws -> Bool {
        let nextText = WelcomeSampleContent.comment(language: language, now: now).text
        let statement = try prepare(
            """
            UPDATE local_comments
            SET text = ?,
                updatedAt = ?
            WHERE id = ?
              AND postId = ?
              AND deletedAt IS NULL
              AND text <> ?
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(nextText, to: 1, in: statement)
        try bind(now, to: 2, in: statement)
        try bind(WelcomeSampleContent.commentId, to: 3, in: statement)
        try bind(WelcomeSampleContent.postId, to: 4, in: statement)
        try bind(nextText, to: 5, in: statement)
        try stepDone(statement)
        return sqlite3_changes(handle) > 0
    }

    private func refreshWelcomeSampleSummary(language: AppResolvedLanguage, now: Date) throws -> Bool {
        let nextSummary = WelcomeSampleContent.summary(language: language, now: now)
        let currentSummary = try fetchAISummary(id: WelcomeSampleContent.summaryId)
        guard !welcomeSampleSummaryContentMatches(currentSummary, nextSummary) else {
            return false
        }

        try upsertAISummary(nextSummary)
        return true
    }

    private func welcomeSampleSummaryContentMatches(
        _ currentSummary: TimelineAISummary?,
        _ nextSummary: TimelineAISummary
    ) -> Bool {
        guard let currentSummary else {
            return false
        }

        return currentSummary.status == nextSummary.status
            && currentSummary.format == nextSummary.format
            && currentSummary.language == nextSummary.language
            && currentSummary.overview == nextSummary.overview
            && currentSummary.keyPoints == nextSummary.keyPoints
            && currentSummary.sections == nextSummary.sections
            && currentSummary.summaryText == nextSummary.summaryText
            && currentSummary.documentTitle == nextSummary.documentTitle
            && currentSummary.oneLiner == nextSummary.oneLiner
            && currentSummary.documentBlocks == nextSummary.documentBlocks
            && currentSummary.promptVersion == nextSummary.promptVersion
            && currentSummary.provider == nextSummary.provider
            && currentSummary.model == nextSummary.model
            && currentSummary.errorCode == nextSummary.errorCode
            && currentSummary.errorMessage == nextSummary.errorMessage
            && currentSummary.deletedAt == nextSummary.deletedAt
    }

    private func isLibraryEmptyForWelcomeSample() throws -> Bool {
        try count(
            """
            SELECT
                (SELECT COUNT(*) FROM local_posts WHERE deletedAt IS NULL AND id <> ?) +
                (SELECT COUNT(*) FROM local_checkin_entries WHERE deletedAt IS NULL)
            """,
            bind: { statement in
                try self.bind(WelcomeSampleContent.postId, to: 1, in: statement)
            }
        ) == 0
    }

    private func sampleCommentExists(commentId: String) throws -> Bool {
        try count(
            "SELECT COUNT(*) FROM local_comments WHERE id = ? AND postId = ?",
            bind: { statement in
                try self.bind(commentId, to: 1, in: statement)
                try self.bind(WelcomeSampleContent.postId, to: 2, in: statement)
            }
        ) > 0
    }

    private func updateWelcomeSampleDeletion(deletedAt: Date) throws {
        let statement = try prepare(
            """
            UPDATE local_posts
            SET deletedAt = ?,
                syncStatus = 'synced',
                localUpdatedAt = ?
            WHERE id = ?
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(deletedAt, to: 1, in: statement)
        try bind(deletedAt, to: 2, in: statement)
        try bind(WelcomeSampleContent.postId, to: 3, in: statement)
        try stepDone(statement)
    }

    private func softDeleteWelcomeSampleChildren(deletedAt: Date) throws {
        try execute(
            """
            UPDATE local_media
            SET deletedAt = '\(Self.sqlDateString(deletedAt))',
                uploadStatus = 'deleted',
                updatedAt = '\(Self.sqlDateString(deletedAt))'
            WHERE postId = '\(WelcomeSampleContent.postId)';

            UPDATE local_comments
            SET deletedAt = '\(Self.sqlDateString(deletedAt))',
                updatedAt = '\(Self.sqlDateString(deletedAt))',
                syncStatus = 'synced'
            WHERE postId = '\(WelcomeSampleContent.postId)';

            UPDATE local_ai_summaries
            SET deletedAt = '\(Self.sqlDateString(deletedAt))',
                updatedAt = '\(Self.sqlDateString(deletedAt))'
            WHERE postId = '\(WelcomeSampleContent.postId)';

            UPDATE local_post_tags
            SET deletedAt = '\(Self.sqlDateString(deletedAt))',
                updatedAt = '\(Self.sqlDateString(deletedAt))'
            WHERE postId = '\(WelcomeSampleContent.postId)';
            """
        )
    }

    private static func sqlDateString(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
