import XCTest
@testable import PrivateMoments

final class CloudKitLocalPayloadResolverTests: XCTestCase {
    private var temporaryRoot: URL!
    private var savedLocalWeeklyReviews: [ReviewPayload] = []
    private var savedPreferenceState: AppSettingsPreferenceTestState!

    override func setUpWithError() throws {
        try super.setUpWithError()
        savedLocalWeeklyReviews = AppSettings.localWeeklyReviews
        savedPreferenceState = AppSettingsPreferenceTestState.capture()
        AppSettings.localWeeklyReviews = []
        ComposerDraftStore.clear()
        EditDraftStore.clear(postId: "post-1")
        temporaryRoot = FileManager.default.temporaryDirectory
            .appending(path: "CloudKitLocalPayloadResolverTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        ComposerDraftStore.clear()
        EditDraftStore.clear(postId: "post-1")
        AppSettings.localWeeklyReviews = savedLocalWeeklyReviews
        savedPreferenceState.restore()
        if let temporaryRoot {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }
        try super.tearDownWithError()
    }

    func testResolvesMomentPayloadFromLocalDatabase() throws {
        let database = try LocalDatabase.openForTesting(url: temporaryRoot.appending(path: "moment.sqlite"))
        let now = Date(timeIntervalSince1970: 6_000)
        try database.insert(TimelinePost(
            id: "post-1",
            text: "Stored locally",
            isFavorite: true,
            isPinned: false,
            pinnedAt: nil,
            aiTagProcessedAt: nil,
            tagsUserEditedAt: nil,
            occurredAt: now,
            localCreatedAt: now,
            localUpdatedAt: now.addingTimeInterval(1),
            localEditedAt: nil,
            serverVersion: 9,
            syncStatus: "pending",
            deletedAt: nil
        ))
        let change = CloudKitPendingChange(
            id: "change-1",
            entityType: .moment,
            entityId: "post-1",
            recordStateId: nil,
            changeKind: .upsert,
            reason: "test",
            status: .pending,
            attemptCount: 0,
            lastErrorCode: nil,
            lastErrorMessage: nil,
            createdAt: now,
            updatedAt: now,
            nextAttemptAt: nil,
            finishedAt: nil
        )
        let resolver = CloudKitLocalPayloadResolver(database: database)

        let payload = try XCTUnwrap(resolver.payload(for: change))

        XCTAssertEqual(payload.entityType, .moment)
        XCTAssertEqual(payload.entityId, "post-1")
        XCTAssertEqual(payload.fields["text"], .string("Stored locally"))
        XCTAssertEqual(payload.fields["isFavorite"], .bool(true))
        XCTAssertNil(payload.fields["serverVersion"])
        XCTAssertNil(payload.fields["syncStatus"])
    }

    func testResolvesTagAliasAndPostTagRelationshipPayloads() throws {
        let database = try LocalDatabase.openForTesting(url: temporaryRoot.appending(path: "tags.sqlite"))
        let now = Date(timeIntervalSince1970: 6_200)
        try database.insert(TimelinePost(
            id: "post-1",
            text: "Tag target",
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
        ))
        let tag = TimelineTag(
            id: "topic-ai",
            type: "topic",
            name: "AI",
            normalizedName: "ai",
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
            tagId: "topic-ai",
            alias: "LLM",
            normalizedAlias: "llm",
            createdAt: now.addingTimeInterval(1),
            deletedAt: nil
        ))
        try database.upsertAssignedTag(TimelineAssignedTag(
            id: "assignment-1",
            postId: "post-1",
            tagId: "topic-ai",
            role: "topic",
            source: "ai",
            confidence: 0.9,
            aiSummaryId: "summary-1",
            createdAt: now.addingTimeInterval(2),
            updatedAt: now.addingTimeInterval(3),
            deletedAt: nil,
            tag: tag
        ))
        let resolver = CloudKitLocalPayloadResolver(database: database)

        let aliasPayload = try XCTUnwrap(resolver.payload(for: pendingChange(.tagAlias, "alias-1", now: now)))
        let assignmentPayload = try XCTUnwrap(resolver.payload(for: pendingChange(.postTag, "assignment-1", now: now)))

        XCTAssertEqual(aliasPayload.entityType, .tagAlias)
        XCTAssertEqual(aliasPayload.fields["tagId"], .string("topic-ai"))
        XCTAssertEqual(aliasPayload.fields["alias"], .string("LLM"))
        XCTAssertEqual(assignmentPayload.entityType, .postTag)
        XCTAssertEqual(assignmentPayload.fields["postId"], .string("post-1"))
        XCTAssertEqual(assignmentPayload.fields["tagId"], .string("topic-ai"))
        XCTAssertEqual(assignmentPayload.fields["confidence"], .double(0.9))
        XCTAssertNil(assignmentPayload.fields["tag"])
    }

    func testResolvesWeeklyReviewPayloadFromLocalSettings() throws {
        let database = try LocalDatabase.openForTesting(url: temporaryRoot.appending(path: "weekly-review.sqlite"))
        AppSettings.localWeeklyReviews = [
            Self.weeklyReview(id: "review-1", updatedAt: "2026-06-03T10:20:30Z", deletedAt: nil)
        ]
        let resolver = CloudKitLocalPayloadResolver(database: database)

        let payload = try XCTUnwrap(resolver.payload(for: pendingChange(
            .weeklyReview,
            "review-1",
            now: Date(timeIntervalSince1970: 6_300)
        )))

        XCTAssertEqual(payload.entityType, .weeklyReview)
        XCTAssertEqual(payload.entityId, "review-1")
        XCTAssertEqual(payload.fields["kind"], .string("weekly"))
        XCTAssertEqual(payload.fields["status"], .string("ready"))
        XCTAssertNil(payload.fields["provider"])
        XCTAssertNil(payload.fields["model"])
        XCTAssertNil(payload.fields["errorMessage"])
    }

    func testResolvesPreferencePayloadFromCurrentAppSettings() throws {
        let database = try LocalDatabase.openForTesting(url: temporaryRoot.appending(path: "preference.sqlite"))
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
        AppSettings.preferredSpeechTranscriptionLocaleIdentifier = "zh-CN"
        AppSettings.autoWeeklyReviewEnabled = true
        AppSettings.publishWeeklyReviewToMoments = false
        AppSettings.markdownMathRenderingEnabled = true
        AppSettings.markdownRemoteImagesEnabled = false
        AppSettings.markdownRawHTMLRenderingEnabled = true
        AppSettings.serverURLString = "https://private.example"
        AppSettings.automaticSyncEnabled = true
        AppSettings.localTranscriptionGatewaySettings = LocalTranscriptionGatewaySettings(
            urlString: "https://gateway.example",
            model: "whisper"
        )
        AppSettings.aiProviderProfiles = [
            AIProviderProfile(
                id: "profile-1",
                kind: .customOpenAICompatible,
                displayName: "Private Endpoint",
                baseURLString: "https://ai.example/v1",
                model: "private-model",
                isEnabled: true,
                sortOrder: 0
            )
        ]
        let resolver = CloudKitLocalPayloadResolver(database: database)

        let payload = try XCTUnwrap(resolver.payload(for: pendingChange(
            .preference,
            "app",
            now: Date(timeIntervalSince1970: 6_350)
        )))

        XCTAssertEqual(payload.entityType, .preference)
        XCTAssertEqual(payload.entityId, "app")
        XCTAssertEqual(payload.fields["showTagsInTimeline"], .bool(false))
        XCTAssertEqual(payload.fields["appLanguageMode"], .string("simplifiedChinese"))
        XCTAssertEqual(payload.fields["aiLanguageMode"], .string("chinese"))
        XCTAssertEqual(payload.fields["transcriptionProviderMode"], .string("custom_openai_compatible"))
        XCTAssertEqual(payload.fields["preferredSpeechTranscriptionLocaleIdentifier"], .string("zh-CN"))
        XCTAssertNil(payload.fields["serverURLString"])
        XCTAssertNil(payload.fields["automaticSyncEnabled"])
        XCTAssertNil(payload.fields["aiProviderProfiles"])
        XCTAssertNil(payload.fields["localTranscriptionGatewaySettings"])
    }

    func testResolvesDraftPayloadsFromLocalDraftStores() throws {
        let database = try LocalDatabase.openForTesting(url: temporaryRoot.appending(path: "drafts.sqlite"))
        let occurredAt = Date(timeIntervalSince1970: 6_500)
        let updatedAt = occurredAt.addingTimeInterval(90)
        ComposerDraftStore.save(
            text: "Composer draft from this device",
            occurredAt: occurredAt,
            updatedAt: updatedAt
        )
        let existingMedia = TimelineMedia(
            id: "media-1",
            postId: "post-1",
            kind: "image",
            localCompressedPath: "/tmp/media-1.jpg",
            localOriginalStagingPath: nil,
            localThumbnailPath: nil,
            remoteCompressedPath: nil,
            remoteOriginalPath: nil,
            remoteThumbnailPath: nil,
            originalPreserved: false,
            uploadStatus: "synced",
            mimeType: "image/jpeg",
            durationSeconds: nil,
            transcriptionText: nil,
            transcriptionStatus: "not_applicable",
            transcriptionError: nil,
            transcriptionUpdatedAt: nil,
            sortOrder: 0,
            checksum: "checksum-1",
            createdAt: occurredAt,
            updatedAt: updatedAt
        )
        try EditDraftStore.save(
            postId: "post-1",
            text: "Unsaved edit text",
            occurredAt: occurredAt.addingTimeInterval(-300),
            updatedAt: updatedAt.addingTimeInterval(10),
            mediaItems: [
                MomentEditMediaItem(id: "media-1", source: .existing(existingMedia)),
                MomentEditMediaItem(id: "new-image-1", source: .new(Data([0x01, 0x02])))
            ]
        )
        let resolver = CloudKitLocalPayloadResolver(database: database)

        let composerPayload = try XCTUnwrap(resolver.payload(for: pendingChange(
            .draft,
            "composer",
            now: updatedAt
        )))
        let editPayload = try XCTUnwrap(resolver.payload(for: pendingChange(
            .draft,
            "edit:post-1",
            now: updatedAt
        )))

        XCTAssertEqual(composerPayload.entityType, .draft)
        XCTAssertEqual(composerPayload.fields["draftKind"], .string("composer"))
        XCTAssertEqual(composerPayload.fields["text"], .string("Composer draft from this device"))
        XCTAssertEqual(composerPayload.fields["occurredAt"], .date(occurredAt))
        XCTAssertEqual(composerPayload.fields["updatedAt"], .date(updatedAt))
        XCTAssertEqual(composerPayload.fields["existingMediaIds"], .stringList([]))
        XCTAssertEqual(composerPayload.fields["hasUnsupportedMediaDrafts"], .bool(false))
        XCTAssertNil(composerPayload.fields["mediaBytes"])

        XCTAssertEqual(editPayload.entityType, .draft)
        XCTAssertEqual(editPayload.entityId, "edit:post-1")
        XCTAssertEqual(editPayload.fields["draftKind"], .string("edit_moment"))
        XCTAssertEqual(editPayload.fields["postId"], .string("post-1"))
        XCTAssertEqual(editPayload.fields["text"], .string("Unsaved edit text"))
        XCTAssertEqual(editPayload.fields["existingMediaIds"], .stringList(["media-1"]))
        XCTAssertEqual(editPayload.fields["hasUnsupportedMediaDrafts"], .bool(true))
        XCTAssertNil(editPayload.fields["newMediaBytes"])
    }

    func testResolvesMediaAssetPayloadFromExistingLocalFiles() throws {
        let database = try LocalDatabase.openForTesting(url: temporaryRoot.appending(path: "media-assets.sqlite"))
        let now = Date(timeIntervalSince1970: 6_700)
        try database.insert(TimelinePost(
            id: "post-asset",
            text: "Media asset owner",
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
        ))
        let mediaDirectory = try AppDirectories.mediaDirectory()
        let filePrefix = UUID().uuidString
        let compressedURL = mediaDirectory.appending(path: "\(filePrefix)-compressed.jpg")
        let thumbnailURL = mediaDirectory.appending(path: "\(filePrefix)-thumbnail.jpg")
        let originalURL = mediaDirectory.appending(path: "\(filePrefix)-original.heic")
        try Data([0x01, 0x02, 0x03]).write(to: compressedURL)
        try Data([0x04]).write(to: thumbnailURL)
        try Data([0x05, 0x06]).write(to: originalURL)
        defer {
            try? FileManager.default.removeItem(at: compressedURL)
            try? FileManager.default.removeItem(at: thumbnailURL)
            try? FileManager.default.removeItem(at: originalURL)
        }
        try database.insert(TimelineMedia(
            id: "media-asset",
            postId: "post-asset",
            kind: "image",
            localCompressedPath: compressedURL.path,
            localOriginalStagingPath: originalURL.path,
            localThumbnailPath: thumbnailURL.path,
            remoteCompressedPath: nil,
            remoteOriginalPath: nil,
            remoteThumbnailPath: nil,
            originalPreserved: true,
            uploadStatus: "pending",
            mimeType: "image/jpeg",
            durationSeconds: nil,
            transcriptionText: nil,
            transcriptionStatus: "not_applicable",
            transcriptionError: nil,
            transcriptionUpdatedAt: nil,
            sortOrder: 0,
            checksum: "asset-checksum",
            createdAt: now,
            updatedAt: now
        ))
        let resolver = CloudKitLocalPayloadResolver(database: database)

        let assetPayload = try XCTUnwrap(resolver.assetPayload(for: pendingChange(
            .media,
            "media-asset",
            kind: .assetUpload,
            now: now
        )))

        XCTAssertEqual(assetPayload.metadataPayload.entityType, .media)
        XCTAssertEqual(assetPayload.metadataPayload.entityId, "media-asset")
        XCTAssertEqual(assetPayload.assetFields, [
            .init(fieldName: "compressedAsset", fileURL: compressedURL),
            .init(fieldName: "thumbnailAsset", fileURL: thumbnailURL),
            .init(fieldName: "originalAsset", fileURL: originalURL)
        ])
        XCTAssertNil(assetPayload.metadataPayload.fields["localCompressedPath"])
        XCTAssertNil(assetPayload.metadataPayload.fields["localThumbnailPath"])
        XCTAssertNil(assetPayload.metadataPayload.fields["localOriginalStagingPath"])
    }

    func testMissingEntityReturnsNilInsteadOfCreatingPlaceholderPayload() throws {
        let database = try LocalDatabase.openForTesting(url: temporaryRoot.appending(path: "missing.sqlite"))
        let resolver = CloudKitLocalPayloadResolver(database: database)

        let payload = try resolver.payload(for: pendingChange(.comment, "missing-comment", now: Date(timeIntervalSince1970: 6_400)))
        let reviewPayload = try resolver.payload(for: pendingChange(.weeklyReview, "missing-review", now: Date(timeIntervalSince1970: 6_401)))
        let preferencePayload = try resolver.payload(for: pendingChange(.preference, "not-app", now: Date(timeIntervalSince1970: 6_402)))
        let draftPayload = try resolver.payload(for: pendingChange(.draft, "missing-draft", now: Date(timeIntervalSince1970: 6_403)))

        XCTAssertNil(payload)
        XCTAssertNil(reviewPayload)
        XCTAssertNil(preferencePayload)
        XCTAssertNil(draftPayload)
    }

    private func pendingChange(
        _ entityType: CloudKitSyncEntityType,
        _ entityId: String,
        kind: CloudKitPendingChangeKind = .upsert,
        now: Date
    ) -> CloudKitPendingChange {
        CloudKitPendingChange(
            id: "change-\(entityId)",
            entityType: entityType,
            entityId: entityId,
            recordStateId: nil,
            changeKind: kind,
            reason: "test",
            status: .pending,
            attemptCount: 0,
            lastErrorCode: nil,
            lastErrorMessage: nil,
            createdAt: now,
            updatedAt: now,
            nextAttemptAt: nil,
            finishedAt: nil
        )
    }
}

private extension CloudKitLocalPayloadResolverTests {
    static func weeklyReview(id: String, updatedAt: String, deletedAt: String?) -> ReviewPayload {
        ReviewPayload(
            id: id,
            kind: "weekly",
            rangeMode: "weekly",
            rangeStart: "2026-05-27T10:20:30Z",
            rangeEnd: "2026-06-03T10:20:30Z",
            status: deletedAt == nil ? "ready" : "deleted",
            trigger: "manual",
            content: ReviewContentPayload(
                title: "A useful week",
                subtitle: nil,
                bodyMarkdown: "## A useful week\n\nSeveral ideas became concrete.",
                oneLiner: "Several ideas became concrete.",
                keywords: nil,
                themes: nil,
                emotionalReflection: nil,
                progressAndOpenLoops: nil,
                rhythm: nil,
                notableMoments: nil,
                gentleSuggestions: ["Keep one next step visible."],
                uncertainty: nil
            ),
            promptVersion: "weekly-review-v1",
            provider: "Private Provider",
            model: "private-model",
            language: "zh-Hans",
            errorCode: "provider_timeout",
            errorMessage: "private diagnostic",
            generatedAt: "2026-06-03T10:20:30Z",
            regeneratedFromReviewId: nil,
            publishedPostId: "review-post-1",
            createdAt: "2026-06-03T10:20:00Z",
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            feedback: ReviewFeedbackStatePayload(
                selectedTypes: ["more_concrete"],
                customNote: "Keep it practical.",
                customNoteUpdatedAt: "2026-06-03T10:21:00Z"
            )
        )
    }
}

private struct AppSettingsPreferenceTestState {
    var showTagsInTimeline: Bool
    var showCheckInSummaries: Bool
    var memoryLinksEnabled: Bool
    var aiTitleAutoInsertEnabled: Bool
    var appAppearanceMode: AppAppearanceMode
    var appLanguageMode: AppLanguageMode
    var aiLanguageMode: AILanguageMode
    var aiAnalysisEnabled: Bool
    var aiExternalProcessingConsentAccepted: Bool
    var aiProviderProfiles: [AIProviderProfile]
    var aiProviderFallbackState: AIProviderFallbackState
    var useTextProviderForTranscription: Bool
    var preferredSpeechTranscriptionLocaleIdentifier: String?
    var transcriptionProviderMode: TranscriptionProviderMode
    var localTranscriptionGatewaySettings: LocalTranscriptionGatewaySettings
    var automaticSyncEnabled: Bool
    var autoWeeklyReviewEnabled: Bool
    var publishWeeklyReviewToMoments: Bool
    var markdownMathRenderingEnabled: Bool
    var markdownRemoteImagesEnabled: Bool
    var markdownRawHTMLRenderingEnabled: Bool
    var serverURLString: String

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
            aiProviderProfiles: AppSettings.aiProviderProfiles,
            aiProviderFallbackState: AppSettings.aiProviderFallbackState,
            useTextProviderForTranscription: AppSettings.useTextProviderForTranscription,
            preferredSpeechTranscriptionLocaleIdentifier: AppSettings.preferredSpeechTranscriptionLocaleIdentifier,
            transcriptionProviderMode: AppSettings.transcriptionProviderMode,
            localTranscriptionGatewaySettings: AppSettings.localTranscriptionGatewaySettings,
            automaticSyncEnabled: AppSettings.automaticSyncEnabled,
            autoWeeklyReviewEnabled: AppSettings.autoWeeklyReviewEnabled,
            publishWeeklyReviewToMoments: AppSettings.publishWeeklyReviewToMoments,
            markdownMathRenderingEnabled: AppSettings.markdownMathRenderingEnabled,
            markdownRemoteImagesEnabled: AppSettings.markdownRemoteImagesEnabled,
            markdownRawHTMLRenderingEnabled: AppSettings.markdownRawHTMLRenderingEnabled,
            serverURLString: AppSettings.serverURLString
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
        AppSettings.aiProviderProfiles = aiProviderProfiles
        AppSettings.aiProviderFallbackState = aiProviderFallbackState
        AppSettings.useTextProviderForTranscription = useTextProviderForTranscription
        AppSettings.preferredSpeechTranscriptionLocaleIdentifier = preferredSpeechTranscriptionLocaleIdentifier
        AppSettings.transcriptionProviderMode = transcriptionProviderMode
        AppSettings.localTranscriptionGatewaySettings = localTranscriptionGatewaySettings
        AppSettings.automaticSyncEnabled = automaticSyncEnabled
        AppSettings.autoWeeklyReviewEnabled = autoWeeklyReviewEnabled
        AppSettings.publishWeeklyReviewToMoments = publishWeeklyReviewToMoments
        AppSettings.markdownMathRenderingEnabled = markdownMathRenderingEnabled
        AppSettings.markdownRemoteImagesEnabled = markdownRemoteImagesEnabled
        AppSettings.markdownRawHTMLRenderingEnabled = markdownRawHTMLRenderingEnabled
        AppSettings.serverURLString = serverURLString
    }
}
