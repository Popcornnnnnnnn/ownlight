import Foundation
import SQLite3

extension LocalDatabase {
    func upsertCloudKitRemotePost(_ post: TimelinePost) throws {
        let statement = try prepare(
            """
            INSERT INTO local_posts
                (id, text, isFavorite, isPinned, pinnedAt, aiTagProcessedAt, tagsUserEditedAt, occurredAt,
                 localCreatedAt, localUpdatedAt, localEditedAt, serverVersion, syncStatus, deletedAt)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'synced', ?)
            ON CONFLICT(id) DO UPDATE SET
                text = excluded.text,
                isFavorite = excluded.isFavorite,
                isPinned = excluded.isPinned,
                pinnedAt = excluded.pinnedAt,
                aiTagProcessedAt = excluded.aiTagProcessedAt,
                tagsUserEditedAt = excluded.tagsUserEditedAt,
                occurredAt = excluded.occurredAt,
                localCreatedAt = excluded.localCreatedAt,
                localUpdatedAt = excluded.localUpdatedAt,
                localEditedAt = excluded.localEditedAt,
                serverVersion = excluded.serverVersion,
                syncStatus = 'synced',
                deletedAt = excluded.deletedAt
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(post.id, to: 1, in: statement)
        try bind(post.text, to: 2, in: statement)
        try bind(post.isFavorite ? 1 : 0, to: 3, in: statement)
        try bind(post.isPinned ? 1 : 0, to: 4, in: statement)
        try bind(post.pinnedAt, to: 5, in: statement)
        try bind(post.aiTagProcessedAt, to: 6, in: statement)
        try bind(post.tagsUserEditedAt, to: 7, in: statement)
        try bind(post.occurredAt, to: 8, in: statement)
        try bind(post.localCreatedAt, to: 9, in: statement)
        try bind(post.localUpdatedAt, to: 10, in: statement)
        try bind(post.localEditedAt, to: 11, in: statement)
        try bind(post.serverVersion, to: 12, in: statement)
        try bind(post.deletedAt, to: 13, in: statement)
        try stepDone(statement)
    }

    func upsertCloudKitRemoteComment(_ comment: TimelineComment) throws {
        let statement = try prepare(
            """
            INSERT INTO local_comments
                (id, postId, text, createdAt, updatedAt, serverVersion, syncStatus, deletedAt)
            VALUES (?, ?, ?, ?, ?, ?, 'synced', ?)
            ON CONFLICT(id) DO UPDATE SET
                postId = excluded.postId,
                text = excluded.text,
                createdAt = excluded.createdAt,
                updatedAt = excluded.updatedAt,
                serverVersion = excluded.serverVersion,
                syncStatus = 'synced',
                deletedAt = excluded.deletedAt
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(comment.id, to: 1, in: statement)
        try bind(comment.postId, to: 2, in: statement)
        try bind(comment.text, to: 3, in: statement)
        try bind(comment.createdAt, to: 4, in: statement)
        try bind(comment.updatedAt, to: 5, in: statement)
        try bind(comment.serverVersion, to: 6, in: statement)
        try bind(comment.deletedAt, to: 7, in: statement)
        try stepDone(statement)
    }

    func upsertCloudKitRemoteMedia(_ media: TimelineMedia) throws {
        let statement = try prepare(
            """
            INSERT INTO local_media
                (id, postId, kind, localCompressedPath, localOriginalStagingPath, localThumbnailPath,
                 remoteCompressedPath, remoteOriginalPath, remoteThumbnailPath, originalPreserved,
                 uploadStatus, uploadError, mimeType, durationSeconds, transcriptionText, transcriptionStatus,
                 transcriptionError, transcriptionUpdatedAt, sortOrder, checksum, createdAt, updatedAt, deletedAt)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL)
            ON CONFLICT(id) DO UPDATE SET
                postId = excluded.postId,
                kind = excluded.kind,
                originalPreserved = excluded.originalPreserved,
                uploadStatus = 'uploaded',
                uploadError = NULL,
                mimeType = excluded.mimeType,
                durationSeconds = excluded.durationSeconds,
                sortOrder = excluded.sortOrder,
                checksum = excluded.checksum,
                createdAt = excluded.createdAt,
                updatedAt = excluded.updatedAt,
                deletedAt = NULL
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(media.id, to: 1, in: statement)
        try bind(media.postId, to: 2, in: statement)
        try bind(media.kind, to: 3, in: statement)
        try bind(AppDirectories.storedPath(forLocalPath: media.localCompressedPath), to: 4, in: statement)
        try bind(storedLocalPath(media.localOriginalStagingPath), to: 5, in: statement)
        try bind(storedLocalPath(media.localThumbnailPath), to: 6, in: statement)
        try bind(media.remoteCompressedPath, to: 7, in: statement)
        try bind(media.remoteOriginalPath, to: 8, in: statement)
        try bind(media.remoteThumbnailPath, to: 9, in: statement)
        try bind(media.originalPreserved ? 1 : 0, to: 10, in: statement)
        try bind(media.uploadStatus, to: 11, in: statement)
        try bind(media.mimeType, to: 12, in: statement)
        try bind(media.durationSeconds, to: 13, in: statement)
        try bind(media.transcriptionText, to: 14, in: statement)
        try bind(media.transcriptionStatus, to: 15, in: statement)
        try bind(media.transcriptionError, to: 16, in: statement)
        try bind(media.transcriptionUpdatedAt, to: 17, in: statement)
        try bind(media.sortOrder, to: 18, in: statement)
        try bind(media.checksum, to: 19, in: statement)
        try bind(media.createdAt, to: 20, in: statement)
        try bind(media.updatedAt, to: 21, in: statement)
        try stepDone(statement)
    }

    func updateCloudKitRemoteMediaAssetPaths(
        mediaId: String,
        compressedPath: String?,
        thumbnailPath: String?,
        originalPath: String?,
        downloadedAt: Date
    ) throws {
        let existing = try fetchMedia(id: mediaId)
        let statement = try prepare(
            """
            UPDATE local_media
            SET localCompressedPath = ?,
                localThumbnailPath = ?,
                localOriginalStagingPath = ?,
                updatedAt = ?
            WHERE id = ?
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(AppDirectories.storedPath(forLocalPath: compressedPath ?? existing?.localCompressedPath ?? ""), to: 1, in: statement)
        try bind(storedLocalPath(thumbnailPath ?? existing?.localThumbnailPath), to: 2, in: statement)
        try bind(storedLocalPath(originalPath ?? existing?.localOriginalStagingPath), to: 3, in: statement)
        try bind(downloadedAt, to: 4, in: statement)
        try bind(mediaId, to: 5, in: statement)
        try stepDone(statement)
    }

    func markCloudKitRemotePostDeleted(postId: String, deletedAt: Date) throws {
        let statement = try prepare(
            """
            UPDATE local_posts
            SET deletedAt = ?,
                localUpdatedAt = ?,
                syncStatus = 'synced'
            WHERE id = ?
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(deletedAt, to: 1, in: statement)
        try bind(deletedAt, to: 2, in: statement)
        try bind(postId, to: 3, in: statement)
        try stepDone(statement)
    }

    func markCloudKitRemoteCommentDeleted(commentId: String, deletedAt: Date) throws {
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

    func markCloudKitRemoteMediaDeleted(mediaId: String, deletedAt: Date) throws {
        let statement = try prepare(
            """
            UPDATE local_media
            SET deletedAt = ?,
                updatedAt = ?,
                uploadStatus = 'deleted',
                uploadError = NULL
            WHERE id = ?
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(deletedAt, to: 1, in: statement)
        try bind(deletedAt, to: 2, in: statement)
        try bind(mediaId, to: 3, in: statement)
        try stepDone(statement)
    }

    func upsertCloudKitRemoteCheckInItem(_ item: CheckInItem) throws {
        var synced = item
        synced.syncStatus = "synced"
        if let tagId = synced.tagId, try fetchTag(id: tagId) == nil {
            synced.tagId = nil
        }
        try upsertCheckInItemOnly(synced)
    }

    func upsertCloudKitRemoteCheckInEntry(_ entry: CheckInEntry) throws {
        var synced = entry
        synced.syncStatus = "synced"
        try upsertCheckInEntryOnly(synced)
    }

    func upsertCloudKitRemoteCheckInMedia(_ media: CheckInMedia) throws {
        let statement = try prepare(
            """
            INSERT INTO local_checkin_media
                (id, entryId, kind, localCompressedPath, remoteCompressedPath, uploadStatus,
                 uploadError, mimeType, durationSeconds, transcriptionText, transcriptionStatus,
                 transcriptionError, transcriptionUpdatedAt, sortOrder, checksum, createdAt, updatedAt, deletedAt)
            VALUES (?, ?, ?, ?, ?, 'uploaded', NULL, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                entryId = excluded.entryId,
                kind = excluded.kind,
                uploadStatus = 'uploaded',
                uploadError = NULL,
                mimeType = excluded.mimeType,
                durationSeconds = excluded.durationSeconds,
                sortOrder = excluded.sortOrder,
                checksum = excluded.checksum,
                createdAt = excluded.createdAt,
                updatedAt = excluded.updatedAt,
                deletedAt = excluded.deletedAt
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(media.id, to: 1, in: statement)
        try bind(media.entryId, to: 2, in: statement)
        try bind(media.kind, to: 3, in: statement)
        try bind(AppDirectories.storedPath(forLocalPath: media.localCompressedPath), to: 4, in: statement)
        try bind(media.remoteCompressedPath, to: 5, in: statement)
        try bind(media.mimeType, to: 6, in: statement)
        try bind(media.durationSeconds, to: 7, in: statement)
        try bind(media.transcriptionText, to: 8, in: statement)
        try bind(media.transcriptionStatus, to: 9, in: statement)
        try bind(media.transcriptionError, to: 10, in: statement)
        try bind(media.transcriptionUpdatedAt, to: 11, in: statement)
        try bind(media.sortOrder, to: 12, in: statement)
        try bind(media.checksum, to: 13, in: statement)
        try bind(media.createdAt, to: 14, in: statement)
        try bind(media.updatedAt, to: 15, in: statement)
        try bind(media.deletedAt, to: 16, in: statement)
        try stepDone(statement)
    }

    func updateCloudKitRemoteCheckInMediaAssetPath(
        mediaId: String,
        localPath: String,
        downloadedAt: Date
    ) throws {
        let statement = try prepare(
            """
            UPDATE local_checkin_media
            SET localCompressedPath = ?,
                updatedAt = ?
            WHERE id = ?
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(AppDirectories.storedPath(forLocalPath: localPath), to: 1, in: statement)
        try bind(downloadedAt, to: 2, in: statement)
        try bind(mediaId, to: 3, in: statement)
        try stepDone(statement)
    }

    func markCloudKitRemoteCheckInItemDeleted(itemId: String, deletedAt: Date) throws {
        let statement = try prepare(
            """
            UPDATE local_checkin_items
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
        try bind(itemId, to: 3, in: statement)
        try stepDone(statement)
    }

    func markCloudKitRemoteCheckInEntryDeleted(entryId: String, deletedAt: Date) throws {
        let statement = try prepare(
            """
            UPDATE local_checkin_entries
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
        try bind(entryId, to: 3, in: statement)
        try stepDone(statement)
    }

    func markCloudKitRemoteCheckInMediaDeleted(mediaId: String, deletedAt: Date) throws {
        let statement = try prepare(
            """
            UPDATE local_checkin_media
            SET deletedAt = ?,
                updatedAt = ?,
                uploadStatus = 'deleted',
                uploadError = NULL
            WHERE id = ?
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(deletedAt, to: 1, in: statement)
        try bind(deletedAt, to: 2, in: statement)
        try bind(mediaId, to: 3, in: statement)
        try stepDone(statement)
    }

    func upsertCloudKitRemoteAISummary(_ summary: TimelineAISummary) throws {
        try upsertAISummary(summary)
    }

    func upsertCloudKitRemoteCheckInAISummary(_ summary: CheckInAISummary) throws {
        try upsertCheckInAISummary(summary)
    }

    func markCloudKitRemoteAISummaryDeleted(summaryId: String, deletedAt: Date) throws {
        let statement = try prepare(
            """
            UPDATE local_ai_summaries
            SET status = 'deleted',
                updatedAt = ?,
                deletedAt = ?
            WHERE id = ?
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(deletedAt, to: 1, in: statement)
        try bind(deletedAt, to: 2, in: statement)
        try bind(summaryId, to: 3, in: statement)
        try stepDone(statement)
    }

    func markCloudKitRemoteCheckInAISummaryDeleted(summaryId: String, deletedAt: Date) throws {
        let statement = try prepare(
            """
            UPDATE local_checkin_ai_summaries
            SET status = 'deleted',
                updatedAt = ?,
                deletedAt = ?
            WHERE id = ?
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(deletedAt, to: 1, in: statement)
        try bind(deletedAt, to: 2, in: statement)
        try bind(summaryId, to: 3, in: statement)
        try stepDone(statement)
    }

    func markCloudKitRemoteTagAliasDeleted(aliasId: String, deletedAt: Date) throws {
        let statement = try prepare(
            """
            UPDATE local_tag_aliases
            SET deletedAt = ?
            WHERE id = ?
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(deletedAt, to: 1, in: statement)
        try bind(aliasId, to: 2, in: statement)
        try stepDone(statement)
    }

    func markCloudKitRemoteAssignedTagDeleted(assignedTagId: String, deletedAt: Date) throws {
        let statement = try prepare(
            """
            UPDATE local_post_tags
            SET updatedAt = ?,
                deletedAt = ?
            WHERE id = ?
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(deletedAt, to: 1, in: statement)
        try bind(deletedAt, to: 2, in: statement)
        try bind(assignedTagId, to: 3, in: statement)
        try stepDone(statement)
    }
}
