import XCTest
import UIKit
@testable import PrivateMoments

@MainActor
final class CloudKitTimelineMutationTests: XCTestCase {
    private var temporaryRoot: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryRoot = FileManager.default.temporaryDirectory
            .appending(path: "CloudKitTimelineMutationTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        UserDefaults.standard.removeObject(forKey: AppSettings.KeysForTesting.iCloudSyncEnabled)
    }

    override func tearDownWithError() throws {
        UserDefaults.standard.removeObject(forKey: AppSettings.KeysForTesting.iCloudSyncEnabled)
        if let temporaryRoot {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }
        temporaryRoot = nil
        try super.tearDownWithError()
    }

    func testCreatePostDoesNotEnqueueCloudKitChangeWhenICloudSyncIsDisabled() async throws {
        AppSettings.iCloudSyncEnabled = false
        let database = try makeDatabase()
        let store = try await makeStore(database: database)

        let didCreate = await store.createPost(
            text: "Local only",
            imageData: [],
            occurredAt: Date(timeIntervalSince1970: 1_800_000_000)
        )

        XCTAssertTrue(didCreate)
        XCTAssertEqual(try database.fetchPendingCloudKitChanges(limit: 10), [])
    }

    func testCreatePostEnqueuesCloudKitMomentUpsertWhenICloudSyncIsEnabled() async throws {
        AppSettings.iCloudSyncEnabled = true
        let database = try makeDatabase()
        let store = try await makeStore(database: database)

        let didCreate = await store.createPost(
            text: "CloudKit create",
            imageData: [],
            occurredAt: Date(timeIntervalSince1970: 1_800_000_100)
        )

        XCTAssertTrue(didCreate)
        let change = try XCTUnwrap(try database.fetchPendingCloudKitChanges(limit: 10).onlyElement)
        XCTAssertEqual(change.entityType, .moment)
        XCTAssertEqual(change.changeKind, .upsert)
        XCTAssertEqual(change.reason, "moment_create")
        XCTAssertEqual(change.entityId, try XCTUnwrap(try database.fetchPosts().first).id)
    }

    func testCreateAudioPostEnqueuesCloudKitMomentMediaAndAssetUploadWhenICloudSyncIsEnabled() async throws {
        AppSettings.iCloudSyncEnabled = true
        let database = try makeDatabase()
        let store = try await makeStore(database: database)
        let audioURL = temporaryRoot.appending(path: "voice.m4a")
        try Data("voice-bytes".utf8).write(to: audioURL)

        let didCreate = await store.createPost(
            text: "",
            imageData: [],
            audio: [
                PreparedMomentMedia(
                    id: "audio-cloudkit",
                    kind: "audio",
                    fileURL: audioURL,
                    mimeType: "audio/mp4",
                    durationSeconds: 3.5
                )
            ],
            occurredAt: Date(timeIntervalSince1970: 1_800_000_150)
        )

        XCTAssertTrue(didCreate)
        let changes = try database.fetchPendingCloudKitChanges(limit: 10)
        XCTAssertEqual(changes.count, 3)
        XCTAssertTrue(changes.contains { change in
            change.entityType == .moment
                && change.changeKind == .upsert
                && change.reason == "moment_create"
        })
        XCTAssertTrue(changes.contains { change in
            change.entityType == .media
                && change.entityId == "audio-cloudkit"
                && change.changeKind == .upsert
                && change.reason == "media_create"
        })
        XCTAssertTrue(changes.contains { change in
            change.entityType == .media
                && change.entityId == "audio-cloudkit"
                && change.changeKind == .assetUpload
                && change.reason == "media_asset_upload"
        })
    }

    func testUpdatePostEnqueuesCloudKitMomentUpsertWhenICloudSyncIsEnabled() async throws {
        AppSettings.iCloudSyncEnabled = true
        let database = try makeDatabase()
        let now = Date(timeIntervalSince1970: 1_800_000_200)
        try database.insert(Self.post(id: "post-update", text: "Before", now: now))
        let store = try await makeStore(database: database)
        let item = try XCTUnwrap(store.items.first)

        let didUpdate = await store.updatePost(
            item: item,
            text: "After",
            occurredAt: now.addingTimeInterval(10),
            mediaItems: []
        )

        XCTAssertTrue(didUpdate)
        let change = try XCTUnwrap(try database.fetchPendingCloudKitChanges(limit: 10).onlyElement)
        XCTAssertEqual(change.entityType, .moment)
        XCTAssertEqual(change.entityId, "post-update")
        XCTAssertEqual(change.changeKind, .upsert)
        XCTAssertEqual(change.reason, "moment_update")
    }

    func testUpdatePostEnqueuesCloudKitDeleteForRemovedMediaWhenICloudSyncIsEnabled() async throws {
        AppSettings.iCloudSyncEnabled = true
        let database = try makeDatabase()
        let now = Date(timeIntervalSince1970: 1_800_000_220)
        let post = Self.post(id: "post-remove-media", text: "Before media edit", now: now)
        let keptMedia = Self.media(id: "media-keep", postId: post.id, now: now)
        let removedMedia = Self.media(id: "media-remove", postId: post.id, now: now)
        try database.insert(post)
        try database.insert(keptMedia)
        try database.insert(removedMedia)
        let store = try await makeStore(database: database)
        let item = try XCTUnwrap(store.items.first)

        let didUpdate = await store.updatePost(
            item: item,
            text: "After media edit",
            occurredAt: now.addingTimeInterval(10),
            mediaItems: [
                MomentEditMediaItem(id: keptMedia.id, source: .existing(keptMedia))
            ]
        )

        XCTAssertTrue(didUpdate)
        let changes = try database.fetchPendingCloudKitChanges(limit: 10)
        XCTAssertEqual(changes.count, 2)
        XCTAssertTrue(changes.contains { change in
            change.entityType == .moment
                && change.entityId == post.id
                && change.changeKind == .upsert
                && change.reason == "moment_update"
        })
        XCTAssertTrue(changes.containsDelete(.media, removedMedia.id, reason: "moment_media_remove"))
    }

    func testUpdatePostEnqueuesCloudKitMediaCreationForNewMediaWhenICloudSyncIsEnabled() async throws {
        AppSettings.iCloudSyncEnabled = true
        let database = try makeDatabase()
        let now = Date(timeIntervalSince1970: 1_800_000_230)
        let post = Self.post(id: "post-add-media", text: "Before media add", now: now)
        let newMediaId = "media-add-on-edit"
        try database.insert(post)
        let store = try await makeStore(database: database)
        let item = try XCTUnwrap(store.items.first)

        let didUpdate = await store.updatePost(
            item: item,
            text: "After media add",
            occurredAt: now.addingTimeInterval(10),
            mediaItems: [
                MomentEditMediaItem(id: newMediaId, source: .new(Self.tinyImageData()))
            ]
        )

        XCTAssertTrue(didUpdate)
        let changes = try database.fetchPendingCloudKitChanges(limit: 10)
        XCTAssertEqual(changes.count, 3)
        XCTAssertTrue(changes.contains { change in
            change.entityType == .moment
                && change.entityId == post.id
                && change.changeKind == .upsert
                && change.reason == "moment_update"
        })
        XCTAssertTrue(changes.contains { change in
            change.entityType == .media
                && change.entityId == newMediaId
                && change.changeKind == .upsert
                && change.reason == "media_create"
        })
        XCTAssertTrue(changes.contains { change in
            change.entityType == .media
                && change.entityId == newMediaId
                && change.changeKind == .assetUpload
                && change.reason == "media_asset_upload"
        })
    }

    func testToggleFavoriteEnqueuesCloudKitMomentUpsertWhenICloudSyncIsEnabled() async throws {
        AppSettings.iCloudSyncEnabled = true
        let database = try makeDatabase()
        let now = Date(timeIntervalSince1970: 1_800_000_240)
        try database.insert(Self.post(id: "post-favorite", text: "Favorite me", now: now))
        let store = try await makeStore(database: database)
        let item = try XCTUnwrap(store.items.first)

        await store.toggleFavorite(item)

        let change = try XCTUnwrap(try database.fetchPendingCloudKitChanges(limit: 10).onlyElement)
        XCTAssertEqual(change.entityType, .moment)
        XCTAssertEqual(change.entityId, "post-favorite")
        XCTAssertEqual(change.changeKind, .upsert)
        XCTAssertEqual(change.reason, "moment_favorite")
    }

    func testTogglePinnedEnqueuesCloudKitMomentUpsertWhenICloudSyncIsEnabled() async throws {
        AppSettings.iCloudSyncEnabled = true
        let database = try makeDatabase()
        let now = Date(timeIntervalSince1970: 1_800_000_260)
        try database.insert(Self.post(id: "post-pin", text: "Pin me", now: now))
        let store = try await makeStore(database: database)
        let item = try XCTUnwrap(store.items.first)

        await store.togglePinned(item)

        let change = try XCTUnwrap(try database.fetchPendingCloudKitChanges(limit: 10).onlyElement)
        XCTAssertEqual(change.entityType, .moment)
        XCTAssertEqual(change.entityId, "post-pin")
        XCTAssertEqual(change.changeKind, .upsert)
        XCTAssertEqual(change.reason, "moment_pin")
    }

    func testDeletePostEnqueuesCloudKitMomentDeleteWhenICloudSyncIsEnabled() async throws {
        AppSettings.iCloudSyncEnabled = true
        let database = try makeDatabase()
        let now = Date(timeIntervalSince1970: 1_800_000_300)
        try database.insert(Self.post(id: "post-delete", text: "Delete me", now: now))
        let store = try await makeStore(database: database)
        let item = try XCTUnwrap(store.items.first)

        await store.deletePost(item)

        let change = try XCTUnwrap(try database.fetchPendingCloudKitChanges(limit: 10).onlyElement)
        XCTAssertEqual(change.entityType, .moment)
        XCTAssertEqual(change.entityId, "post-delete")
        XCTAssertEqual(change.changeKind, .delete)
        XCTAssertEqual(change.reason, "moment_delete")
    }

    func testDeletePostEnqueuesCloudKitDeletesForChildRecordsWhenICloudSyncIsEnabled() async throws {
        AppSettings.iCloudSyncEnabled = true
        let database = try makeDatabase()
        let now = Date(timeIntervalSince1970: 1_800_000_320)
        let post = Self.post(id: "post-delete-tree", text: "Delete the tree", now: now)
        let media = Self.media(id: "media-delete-tree", postId: post.id, now: now)
        let comment = TimelineComment(
            id: "comment-delete-tree",
            postId: post.id,
            text: "This should disappear too",
            createdAt: now,
            updatedAt: now,
            serverVersion: nil,
            deletedAt: nil
        )
        let summary = Self.aiSummary(
            id: "summary-delete-tree",
            postId: post.id,
            mediaId: media.id,
            now: now
        )
        let tag = Self.topicTag(id: "topic-delete-tree", now: now)
        let assignment = TimelineAssignedTag(
            id: "assignment-delete-tree",
            postId: post.id,
            tagId: tag.id,
            role: "topic",
            source: "manual",
            confidence: nil,
            aiSummaryId: summary.id,
            createdAt: now,
            updatedAt: now,
            deletedAt: nil,
            tag: tag
        )
        try database.insert(post)
        try database.insert(media)
        try database.insert(comment)
        try database.upsertAISummary(summary)
        try database.upsertAssignedTag(assignment)
        let store = try await makeStore(database: database)
        let item = try XCTUnwrap(store.items.first)

        await store.deletePost(item)

        let changes = try database.fetchPendingCloudKitChanges(limit: 10)
        XCTAssertEqual(changes.count, 5)
        XCTAssertTrue(changes.containsDelete(.moment, post.id, reason: "moment_delete"))
        XCTAssertTrue(changes.containsDelete(.media, media.id, reason: "moment_media_delete"))
        XCTAssertTrue(changes.containsDelete(.comment, comment.id, reason: "moment_comment_delete"))
        XCTAssertTrue(changes.containsDelete(.aiSummary, summary.id, reason: "moment_ai_summary_delete"))
        XCTAssertTrue(changes.containsDelete(.postTag, assignment.id, reason: "moment_post_tag_delete"))
    }

    func testCreateTopicTagEnqueuesCloudKitTagUpsertWhenICloudSyncIsEnabled() async throws {
        AppSettings.iCloudSyncEnabled = true
        let database = try makeDatabase()
        let store = try await makeStore(database: database)

        let maybeTag = await store.createTag(
            type: "topic",
            name: "Sync Coverage",
            areaId: TopicTagArea.technology.rawValue
        )
        let tag = try XCTUnwrap(maybeTag)

        let change = try XCTUnwrap(try database.fetchPendingCloudKitChanges(limit: 10).onlyElement)
        XCTAssertEqual(change.entityType, .tag)
        XCTAssertEqual(change.entityId, tag.id)
        XCTAssertEqual(change.changeKind, .upsert)
        XCTAssertEqual(change.reason, "tag_create")
    }

    func testCreateTagAliasEnqueuesCloudKitTagAliasUpsertWhenICloudSyncIsEnabled() async throws {
        AppSettings.iCloudSyncEnabled = true
        let database = try makeDatabase()
        let now = Date(timeIntervalSince1970: 1_800_000_340)
        let tag = TimelineTag(
            id: "tag-alias-parent",
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
        let store = try await makeStore(database: database)

        let didCreate = await store.createTagAlias(tag: tag, alias: "iCloud")

        XCTAssertTrue(didCreate)
        let change = try XCTUnwrap(try database.fetchPendingCloudKitChanges(limit: 10).onlyElement)
        XCTAssertEqual(change.entityType, .tagAlias)
        XCTAssertEqual(change.changeKind, .upsert)
        XCTAssertEqual(change.reason, "tag_alias_create")
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

    private static func media(id: String, postId: String, now: Date) -> TimelineMedia {
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
            durationSeconds: 4,
            transcriptionText: nil,
            transcriptionStatus: "not_started",
            transcriptionError: nil,
            transcriptionUpdatedAt: nil,
            sortOrder: 0,
            checksum: nil,
            createdAt: now,
            updatedAt: now
        )
    }

    private static func aiSummary(
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
            format: "document",
            language: "en",
            overview: "Summary",
            keyPoints: ["One"],
            sections: [],
            summaryText: "Summary",
            documentTitle: "Title",
            oneLiner: "One line",
            documentBlocks: [],
            inputTranscriptLength: 20,
            inputDurationSeconds: 4,
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

    private static func topicTag(id: String, now: Date) -> TimelineTag {
        TimelineTag(
            id: id,
            type: "topic",
            name: "Delete Tree",
            normalizedName: LocalDatabase.normalizedTagName("Delete Tree"),
            colorHex: nil,
            isDefault: false,
            isArchived: false,
            aiUsableAsPrimary: false,
            createdAt: now,
            updatedAt: now,
            archivedAt: nil,
            areaId: TopicTagArea.life.rawValue
        )
    }

    private static func tinyImageData() -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2))
        return renderer.pngData { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
    }
}

private extension Array {
    var onlyElement: Element? {
        count == 1 ? first : nil
    }
}

private extension Array where Element == CloudKitPendingChange {
    func containsDelete(
        _ entityType: CloudKitSyncEntityType,
        _ entityId: String,
        reason: String
    ) -> Bool {
        contains { change in
            change.entityType == entityType
                && change.entityId == entityId
                && change.changeKind == .delete
                && change.reason == reason
        }
    }
}
