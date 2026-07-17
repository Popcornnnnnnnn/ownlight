import XCTest
@testable import PrivateMoments

@MainActor
final class LocalAIArtifactTests: XCTestCase {
    private var temporaryRoot: URL!
    private let profile = AIProviderProfile(
        id: "test-provider",
        kind: .customOpenAICompatible,
        displayName: "Test Provider",
        baseURLString: "https://example.test/v1",
        model: "test-model",
        isEnabled: true,
        sortOrder: 0
    )
    private let fallbackProfile = AIProviderProfile(
        id: "fallback-provider",
        kind: .customOpenAICompatible,
        displayName: "Fallback Provider",
        baseURLString: "https://fallback.example.test/v1",
        model: "fallback-model",
        isEnabled: true,
        sortOrder: 1
    )

    override func setUpWithError() throws {
        temporaryRoot = FileManager.default.temporaryDirectory
            .appending(path: "private-moments-local-ai-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        AppSettings.aiAnalysisEnabled = true
        AppSettings.aiProviderProfiles = [profile]
        AppSettings.aiProviderFallbackState = AIProviderFallbackState()
        AppSettings.localWeeklyReviews = []
        AppSettings.transcriptionProviderMode = .iPhoneOnDevice
        AppSettings.localTranscriptionGatewaySettings = .default
        AppSettings.aiExternalProcessingConsentAccepted = true
        AppSettings.iCloudSyncEnabled = false
        try KeychainStore.saveAIProviderAPIKey("test-key", profileId: profile.id)
        try KeychainStore.saveAIProviderAPIKey("fallback-key", profileId: fallbackProfile.id)
        try KeychainStore.clearLocalTranscriptionGatewayToken()
    }

    override func tearDownWithError() throws {
        try? KeychainStore.clearAIProviderAPIKey(profileId: profile.id)
        try? KeychainStore.clearAIProviderAPIKey(profileId: fallbackProfile.id)
        try? KeychainStore.clearLocalTranscriptionGatewayToken()
        AppSettings.aiAnalysisEnabled = false
        AppSettings.aiProviderProfiles = []
        AppSettings.aiProviderFallbackState = AIProviderFallbackState()
        AppSettings.localWeeklyReviews = []
        AppSettings.transcriptionProviderMode = .iPhoneOnDevice
        AppSettings.localTranscriptionGatewaySettings = .default
        AppSettings.aiExternalProcessingConsentAccepted = false
        AppSettings.iCloudSyncEnabled = false
        PromptCaptureURLProtocol.requestBody = nil
        PromptCaptureURLProtocol.usageJSON = nil
        if let temporaryRoot {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }
    }

    func testSavingProviderProfileClearsPreviousNeedsAttentionState() {
        var state = AIProviderFallbackState()
        state.recordFailure(
            profileId: profile.id,
            category: .needsAttention,
            message: "previous response format error"
        )
        AppSettings.aiProviderFallbackState = state

        let store = TimelineStore()
        XCTAssertNil(AIProviderRouter.selectProfile(
            profiles: store.aiProviderProfiles,
            fallbackState: store.aiProviderFallbackState
        ))

        store.saveAIProviderProfile(profile)

        XCTAssertFalse(store.aiProviderFallbackState.needsAttention(profileId: profile.id))
        XCTAssertFalse(AppSettings.aiProviderFallbackState.needsAttention(profileId: profile.id))
        XCTAssertEqual(AIProviderRouter.selectProfile(
            profiles: store.aiProviderProfiles,
            fallbackState: store.aiProviderFallbackState
        )?.id, profile.id)
    }

    func testTimelineAudioSummaryIsGeneratedLocallyWithoutAuthentication() async throws {
        let database = try LocalDatabase.openForTesting(url: temporaryRoot.appending(path: "test.sqlite"))
        let mediaURL = temporaryRoot.appending(path: "audio.m4a")
        try Data("audio".utf8).write(to: mediaURL)
        let now = Date()
        let post = TimelinePost(
            id: "post-1",
            text: "",
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
        let media = TimelineMedia(
            id: "media-1",
            postId: post.id,
            kind: "audio",
            localCompressedPath: mediaURL.path,
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
            transcriptionStatus: "pending",
            transcriptionError: nil,
            transcriptionUpdatedAt: nil,
            sortOrder: 0,
            checksum: nil,
            createdAt: now,
            updatedAt: now
        )
        try database.insert(post)
        try database.insert(media)

        let store = TimelineStore()
        store.database = database
        store.speechTranscriptionOverride = { _, _ in "hello private audio" }
        store.aiTextAnalysisOverride = { request, _, _ in
            XCTAssertEqual(request.feature, .mediaSummary)
            return Self.result(title: "Audio Note", tag: "Ideas")
        }
        try await store.reload()

        await store.requestAISummary(for: media)

        let summary = try XCTUnwrap(database.fetchAISummary(mediaId: media.id))
        XCTAssertEqual(summary.status, "ready")
        XCTAssertEqual(summary.documentTitle, "Audio Note")
        XCTAssertEqual(summary.provider, "Test Provider")
        XCTAssertEqual(summary.inputTokenCount, 50)
        XCTAssertEqual(summary.outputTokenCount, 12)
        XCTAssertEqual(summary.totalTokenCount, 62)
        XCTAssertEqual(try database.fetchMedia(id: media.id)?.transcriptionText, "hello private audio")
        XCTAssertTrue(try database.fetchAssignedTags(postId: post.id).contains { $0.source == "ai" && $0.tag.name == "Ideas" })
    }

    func testTimelineAudioSummaryEnqueuesCloudKitSummaryAndSuggestedTagsWhenEnabled() async throws {
        AppSettings.iCloudSyncEnabled = true
        let database = try LocalDatabase.openForTesting(url: temporaryRoot.appending(path: "cloudkit-summary.sqlite"))
        let mediaURL = temporaryRoot.appending(path: "cloudkit-audio.m4a")
        try Data("audio".utf8).write(to: mediaURL)
        let now = Date(timeIntervalSince1970: 1_800_303_000)
        let post = TimelinePost(
            id: "cloudkit-post-1",
            text: "",
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
        let media = TimelineMedia(
            id: "cloudkit-media-1",
            postId: post.id,
            kind: "audio",
            localCompressedPath: mediaURL.path,
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
            transcriptionStatus: "pending",
            transcriptionError: nil,
            transcriptionUpdatedAt: nil,
            sortOrder: 0,
            checksum: nil,
            createdAt: now,
            updatedAt: now
        )
        try database.insert(post)
        try database.insert(media)

        let store = TimelineStore()
        store.database = database
        store.speechTranscriptionOverride = { _, _ in "hello private audio" }
        store.aiTextAnalysisOverride = { _, _, _ in
            Self.result(title: "Audio Note", tag: "Ideas")
        }
        try await store.reload()

        await store.requestAISummary(for: media)

        let summary = try XCTUnwrap(database.fetchAISummary(mediaId: media.id))
        let assignedTags = try database.fetchAssignedTags(postId: post.id)
        let assignment = try XCTUnwrap(assignedTags.first { $0.aiSummaryId == summary.id })
        let changes = try database.fetchPendingCloudKitChanges(limit: 20)
        XCTAssertTrue(changes.contains { $0.entityType == .aiSummary && $0.entityId == summary.id && $0.changeKind == .upsert && $0.reason == "ai_summary_ready" })
        XCTAssertTrue(changes.contains { $0.entityType == .tag && $0.entityId == assignment.tagId && $0.changeKind == .upsert && $0.reason == "ai_topic_tag" })
        XCTAssertTrue(changes.contains { $0.entityType == .postTag && $0.entityId == assignment.id && $0.changeKind == .upsert && $0.reason == "ai_topic_assignment" })
    }

    func testTimelineAudioSummaryUsesOpenAICompatibleTranscriptionWhenConfigured() async throws {
        AppSettings.transcriptionProviderMode = .customOpenAICompatible
        AppSettings.localTranscriptionGatewaySettings = LocalTranscriptionGatewaySettings(
            urlString: "https://gateway.example",
            model: "mlx-community/whisper-large-v3-turbo"
        )
        try KeychainStore.saveLocalTranscriptionGatewayToken("gateway-token")
        let database = try LocalDatabase.openForTesting(url: temporaryRoot.appending(path: "gateway.sqlite"))
        let mediaURL = temporaryRoot.appending(path: "gateway-audio.m4a")
        try Data("audio".utf8).write(to: mediaURL)
        let now = Date()
        let post = TimelinePost(
            id: "post-gateway",
            text: "",
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
        let media = TimelineMedia(
            id: "media-gateway",
            postId: post.id,
            kind: "audio",
            localCompressedPath: mediaURL.path,
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
            transcriptionStatus: "pending",
            transcriptionError: nil,
            transcriptionUpdatedAt: nil,
            sortOrder: 0,
            checksum: nil,
            createdAt: now,
            updatedAt: now
        )
        try database.insert(post)
        try database.insert(media)

        let store = TimelineStore()
        store.database = database
        store.transcriptionProviderMode = .customOpenAICompatible
        store.localTranscriptionGatewaySettings = AppSettings.localTranscriptionGatewaySettings
        store.localTranscriptionGatewayOverride = { request in
            XCTAssertEqual(request.gatewayURLString, "https://gateway.example")
            XCTAssertEqual(request.model, "mlx-community/whisper-large-v3-turbo")
            XCTAssertEqual(request.token, "gateway-token")
            XCTAssertEqual(request.media.id, media.id)
            return "gateway transcript"
        }
        store.speechTranscriptionOverride = { _, _ in
            XCTFail("iPhone on-device transcription should not run when an OpenAI-compatible transcription endpoint is configured.")
            return "iphone transcript"
        }
        store.aiTextAnalysisOverride = { request, _, _ in
            XCTAssertEqual(request.sourceText, "gateway transcript")
            return Self.result(title: "Gateway Summary", tag: "AI")
        }
        try await store.reload()

        await store.requestAISummary(for: media)

        let summary = try XCTUnwrap(database.fetchAISummary(mediaId: media.id))
        XCTAssertEqual(summary.status, "ready")
        XCTAssertEqual(summary.documentTitle, "Gateway Summary")
        XCTAssertEqual(try database.fetchMedia(id: media.id)?.transcriptionText, "gateway transcript")
    }

    func testCheckInAudioSummaryStoresTranscriptForDiagnostics() async throws {
        let database = try LocalDatabase.openForTesting(url: temporaryRoot.appending(path: "checkin.sqlite"))
        let mediaURL = temporaryRoot.appending(path: "checkin-audio.m4a")
        try Data("audio".utf8).write(to: mediaURL)
        let now = Date()
        let item = CheckInItem(
            id: "item-1",
            name: "Mood",
            symbolName: "heart",
            colorHex: "#61B88D",
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
        )
        let entry = CheckInEntry(
            id: "entry-1",
            itemId: item.id,
            occurredAt: now,
            note: "voice check-in",
            showInTimeline: true,
            createdAt: now,
            updatedAt: now,
            deletedAt: nil,
            syncStatus: "synced"
        )
        let media = CheckInMedia(
            id: "checkin-media-1",
            entryId: entry.id,
            kind: "audio",
            localCompressedPath: mediaURL.path,
            remoteCompressedPath: nil,
            uploadStatus: "uploaded",
            uploadError: nil,
            mimeType: "audio/mp4",
            durationSeconds: 5,
            sortOrder: 0,
            checksum: nil,
            createdAt: now,
            updatedAt: now,
            deletedAt: nil
        )
        try database.upsertCheckInItemOnly(item)
        try database.upsertCheckInEntryOnly(entry)
        try database.insertCheckInMedia(media)

        let store = TimelineStore()
        store.database = database
        store.speechTranscriptionOverride = { _, _ in "check-in transcript for debugging" }
        store.aiTextAnalysisOverride = { request, _, _ in
            XCTAssertEqual(request.feature, .checkInSummary)
            return Self.result(title: "Check-in Audio", tag: "Mood")
        }
        try await store.reload()

        await store.requestCheckInAISummary(for: media)

        let summary = try XCTUnwrap(database.fetchCheckInAISummary(mediaId: media.id))
        XCTAssertEqual(summary.status, "ready")
        XCTAssertEqual(summary.documentTitle, "Check-in Audio")
        XCTAssertEqual(summary.totalTokenCount, 62)
        let storedMedia = try XCTUnwrap(database.fetchCheckInMedia(id: media.id))
        XCTAssertEqual(storedMedia.transcriptionText, "check-in transcript for debugging")
        XCTAssertEqual(storedMedia.transcriptionStatus, "transcribed")
    }

    func testWeeklyReviewGeneratesLocalArtifactWithoutAuthentication() async throws {
        let database = try LocalDatabase.openForTesting(url: temporaryRoot.appending(path: "review.sqlite"))
        let now = Date()
        try database.insert(TimelinePost(
            id: "post-1",
            text: "Finished the local AI migration plan.",
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

        let store = TimelineStore()
        store.database = database
        store.aiTextAnalysisOverride = { request, _, _ in
            XCTAssertEqual(request.feature, .weeklyReview)
            return Self.result(title: "Local AI Week", tag: "Review")
        }
        try await store.reload()

        await store.generateWeeklyReview()

        XCTAssertEqual(store.weeklyReviews.count, 1)
        XCTAssertEqual(store.weeklyReviews.first?.content.title, "Local AI Week")
        XCTAssertEqual(AppSettings.localWeeklyReviews.first?.provider, "Test Provider")
    }

    func testSyncedServerReviewMomentAppearsInLocalReviews() async throws {
        let now = Date()
        let post = TimelinePost(
            id: "review-server-review-1",
            text: """
            # A week of clearer boundaries

            Full historical review body.
            """,
            isFavorite: false,
            isPinned: false,
            pinnedAt: nil,
            aiTagProcessedAt: nil,
            tagsUserEditedAt: nil,
            occurredAt: now,
            localCreatedAt: now,
            localUpdatedAt: now,
            localEditedAt: nil,
            serverVersion: 1282,
            syncStatus: "synced",
            deletedAt: nil
        )
        let store = TimelineStore()
        store.items = [TimelineItem(post: post, media: [], comments: [], aiSummaries: [], tags: [])]

        await store.refreshReviews()

        XCTAssertEqual(store.weeklyReviews.count, 1)
        XCTAssertEqual(store.weeklyReviews.first?.id, "server-review-1")
        XCTAssertEqual(store.weeklyReviews.first?.publishedPostId, "review-server-review-1")
        XCTAssertEqual(store.weeklyReviews.first?.content.title, "A week of clearer boundaries")
        XCTAssertEqual(store.weeklyReviews.first?.content.bodyMarkdown, post.text)
        XCTAssertEqual(store.weeklyReviews.first?.provider, "Mac Server (historical)")
        XCTAssertEqual(AppSettings.localWeeklyReviews.map(\.id), ["server-review-1"])
    }

    func testTextAnalysisFallsBackAfterTransientProviderFailure() async throws {
        AppSettings.aiExternalProcessingConsentAccepted = true
        AppSettings.aiProviderProfiles = [profile, fallbackProfile]
        let database = try LocalDatabase.openForTesting(url: temporaryRoot.appending(path: "fallback.sqlite"))
        let store = TimelineStore()
        store.database = database
        store.aiProviderProfiles = [profile, fallbackProfile]
        store.aiTextAnalysisOverride = { _, candidate, apiKey in
            if candidate.id == self.profile.id {
                XCTAssertEqual(apiKey, "test-key")
                throw AITextAnalysisError.provider(statusCode: 429, message: "rate limited")
            }
            XCTAssertEqual(candidate.id, self.fallbackProfile.id)
            XCTAssertEqual(apiKey, "fallback-key")
            return Self.result(title: "Fallback Result", tag: "AI")
        }

        let result = try await store.generateTextArtifact(AIArtifactGenerationRequest(
            feature: .mediaSummary,
            title: nil,
            sourceText: "transcript",
            languageMode: .auto,
            topicVocabulary: []
        ))

        XCTAssertEqual(result.documentTitle, "Fallback Result")
        XCTAssertTrue(store.aiProviderFallbackState.isCoolingDown(profileId: profile.id))
        XCTAssertFalse(store.aiProviderFallbackState.isCoolingDown(profileId: fallbackProfile.id))
    }

    func testTextArtifactDecodeFailureDoesNotMarkProviderAsNeedsSetup() async throws {
        AppSettings.aiExternalProcessingConsentAccepted = true
        AppSettings.aiProviderProfiles = [profile]
        let database = try LocalDatabase.openForTesting(url: temporaryRoot.appending(path: "artifact-failure.sqlite"))
        let store = TimelineStore()
        store.database = database
        store.aiProviderProfiles = [profile]
        store.aiTextAnalysisOverride = { _, candidate, apiKey in
            XCTAssertEqual(candidate.id, self.profile.id)
            XCTAssertEqual(apiKey, "test-key")
            throw AITextAnalysisError.unsupportedResponse
        }

        do {
            _ = try await store.generateTextArtifact(AIArtifactGenerationRequest(
                feature: .mediaSummary,
                title: nil,
                sourceText: "transcript",
                languageMode: .auto,
                topicVocabulary: []
            ))
            XCTFail("Expected artifact decode failure.")
        } catch let error as AITextAnalysisError {
            XCTAssertEqual(error.localizedDescription, AITextAnalysisError.unsupportedResponse.localizedDescription)
        }

        XCTAssertFalse(store.aiProviderFallbackState.needsAttention(profileId: profile.id))
        XCTAssertFalse(store.aiProviderFallbackState.isCoolingDown(profileId: profile.id))
        XCTAssertEqual(
            AIProviderRouter.selectProfile(
                profiles: store.aiProviderProfiles,
                fallbackState: store.aiProviderFallbackState
            )?.id,
            profile.id
        )
    }

    func testTextAnalysisDoesNotCallProviderBeforeExternalProcessingConsent() async throws {
        AppSettings.aiExternalProcessingConsentAccepted = false
        let database = try LocalDatabase.openForTesting(url: temporaryRoot.appending(path: "consent.sqlite"))
        let store = TimelineStore()
        store.database = database
        store.aiProviderProfiles = [profile]
        var didCallProvider = false
        store.aiTextAnalysisOverride = { _, _, _ in
            didCallProvider = true
            return Self.result(title: "Should Not Run", tag: "AI")
        }

        do {
            _ = try await store.generateTextArtifact(AIArtifactGenerationRequest(
                feature: .mediaSummary,
                title: nil,
                sourceText: "private transcript",
                languageMode: .auto,
                topicVocabulary: []
            ))
            XCTFail("Expected text analysis to require explicit external processing consent.")
        } catch {
            XCTAssertFalse(didCallProvider)
        }
    }

    func testAutoLanguagePromptDoesNotDefaultChineseSourceToEnglishTitle() async throws {
        PromptCaptureURLProtocol.requestBody = nil
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PromptCaptureURLProtocol.self]
        let client = AITextAnalysisClient(urlSession: URLSession(configuration: configuration))

        _ = try await client.generate(
            request: AIArtifactGenerationRequest(
                feature: .mediaSummary,
                title: nil,
                sourceText: "今天主要记录了本地 AI 总结和标题语言的问题。",
                languageMode: .auto,
                topicVocabulary: []
            ),
            profile: profile,
            apiKey: "test-key"
        )

        let body = try XCTUnwrap(PromptCaptureURLProtocol.requestBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        let userMessage = try XCTUnwrap(messages.first { $0["role"] as? String == "user" })
        let prompt = try XCTUnwrap(userMessage["content"] as? String)
        XCTAssertTrue(prompt.contains("If the source is mostly Chinese"))
        XCTAssertTrue(prompt.contains("documentTitle/title"))
        XCTAssertTrue(prompt.contains("Do not choose English just because"))
    }

    func testMediaSummaryPromptRequestsDetailedGroundedCoverage() async throws {
        PromptCaptureURLProtocol.requestBody = nil
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PromptCaptureURLProtocol.self]
        let client = AITextAnalysisClient(urlSession: URLSession(configuration: configuration))

        _ = try await client.generate(
            request: AIArtifactGenerationRequest(
                feature: .mediaSummary,
                title: nil,
                sourceText: "今天录音提到了 DeepSeek 测试成功但 summary 显示 no speech detected，还提到了需要查看转录文本排查。",
                languageMode: .auto,
                topicVocabulary: []
            ),
            profile: profile,
            apiKey: "test-key"
        )

        let body = try XCTUnwrap(PromptCaptureURLProtocol.requestBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        let userMessage = try XCTUnwrap(messages.first { $0["role"] as? String == "user" })
        let prompt = try XCTUnwrap(userMessage["content"] as? String)
        XCTAssertTrue(prompt.contains("Prefer complete coverage over brevity"))
        XCTAssertTrue(prompt.contains("Do not omit concrete points"))
        XCTAssertTrue(prompt.contains("Do not invent details"))
        XCTAssertTrue(prompt.contains("If the transcript seems unreliable"))
        XCTAssertTrue(prompt.contains("Use as many documentBlocks as needed"))
    }

    func testProviderDocumentBlocksDecodeWhenOptionalFieldsAreOmitted() throws {
        let content = """
        {
          "documentTitle": "中文总结",
          "oneLiner": "一句话总结",
          "summaryText": "完整摘要",
          "keyPoints": [],
          "documentBlocks": [
            { "kind": "heading", "text": "原文重点" },
            { "kind": "paragraph", "text": "用户说 summary update failed。" },
            { "kind": "bullets", "items": ["需要查看原文", "需要 token metadata"] }
          ],
          "suggestedTags": []
        }
        """

        let result = try AITextAnalysisClient.decodeResult(from: content, feature: .mediaSummary)

        XCTAssertEqual(result.documentBlocks.count, 3)
        XCTAssertEqual(result.documentBlocks[0].level, 2)
        XCTAssertEqual(result.documentBlocks[1].items, [])
        XCTAssertEqual(result.documentBlocks[2].text, "")
    }

    func testProviderArtifactDecodeToleratesObjectStyleListItems() throws {
        let content = """
        {
          "documentTitle": "语音总结",
          "oneLiner": "记录了一次很短的语音。",
          "summaryText": "这是一条短语音的总结。",
          "keyPoints": [
            { "text": "提到 DeepSeek 测试成功" },
            { "label": "仍然需要重新生成 summary" }
          ],
          "documentBlocks": [
            {
              "kind": "bullets",
              "items": [
                { "text": "检查 provider 返回格式" },
                { "name": "让 decoder 更宽容" }
              ]
            }
          ],
          "suggestedTags": {
            "area": "技术",
            "topics": [
              { "name": "AI Summary" },
              { "label": "DeepSeek" }
            ]
          }
        }
        """

        let result = try AITextAnalysisClient.decodeResult(from: content, feature: .mediaSummary)

        XCTAssertEqual(result.keyPoints, ["提到 DeepSeek 测试成功", "仍然需要重新生成 summary"])
        XCTAssertEqual(result.documentBlocks.first?.items, ["检查 provider 返回格式", "让 decoder 更宽容"])
        XCTAssertEqual(result.suggestedTags, ["AI Summary", "DeepSeek"])
    }

    func testDecodesAreaBackedSuggestedTags() throws {
        let content = """
        {
          "documentTitle": "标签整理",
          "oneLiner": "整理 topic 的层级和筛选体验",
          "summaryText": "讨论把 topic 归入固定 area。",
          "keyPoints": [],
          "documentBlocks": [],
          "suggestedTags": {
            "area": "产品与设计",
            "topics": ["Topic Cleanup", "标签筛选"]
          }
        }
        """

        let result = try AITextAnalysisClient.decodeResult(from: content, feature: .mediaSummary)

        XCTAssertEqual(result.suggestedAreaId, TopicTagArea.productDesign.rawValue)
        XCTAssertEqual(result.suggestedTags, ["Topic Cleanup", "标签筛选"])
    }

    func testOpenAICompatibleUsageIsCapturedInGeneratedResult() async throws {
        PromptCaptureURLProtocol.requestBody = nil
        PromptCaptureURLProtocol.usageJSON = """
        {"prompt_tokens":1234,"completion_tokens":321,"total_tokens":1555}
        """
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PromptCaptureURLProtocol.self]
        let client = AITextAnalysisClient(urlSession: URLSession(configuration: configuration))

        let result = try await client.generate(
            request: AIArtifactGenerationRequest(
                feature: .mediaSummary,
                title: nil,
                sourceText: "需要统计 token usage",
                languageMode: .auto,
                topicVocabulary: []
            ),
            profile: profile,
            apiKey: "test-key"
        )

        XCTAssertEqual(result.tokenUsage?.inputTokens, 1_234)
        XCTAssertEqual(result.tokenUsage?.outputTokens, 321)
        XCTAssertEqual(result.tokenUsage?.totalTokens, 1_555)
    }

    func testOpenAICompatibleDecodeFailureIsReportedAsUnsupportedResponse() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [InvalidAIProviderURLProtocol.self]
        let client = AITextAnalysisClient(urlSession: URLSession(configuration: configuration))

        do {
            _ = try await client.generate(
                request: AIArtifactGenerationRequest(
                    feature: .mediaSummary,
                    title: nil,
                    sourceText: "需要让格式错误显示成可读错误",
                    languageMode: .auto,
                    topicVocabulary: []
                ),
                profile: profile,
                apiKey: "test-key"
            )
            XCTFail("Expected unsupported response for malformed provider response.")
        } catch let error as AITextAnalysisError {
            XCTAssertEqual(error.localizedDescription, AITextAnalysisError.unsupportedResponse.localizedDescription)
        }
    }

    func testArtifactContentDecodeFailureIsReportedAsUnsupportedResponse() throws {
        let content = """
        {
          "documentTitle": "坏格式",
          "oneLiner": "这条 JSON 的 blocks 不是数组",
          "documentBlocks": "not-an-array"
        }
        """

        do {
            _ = try AITextAnalysisClient.decodeResult(from: content, feature: .mediaSummary)
            XCTFail("Expected unsupported response for malformed artifact JSON.")
        } catch let error as AITextAnalysisError {
            XCTAssertEqual(error.localizedDescription, AITextAnalysisError.unsupportedResponse.localizedDescription)
        }
    }

    private static func result(title: String, tag: String) -> AIArtifactGenerationResult {
        AIArtifactGenerationResult(
            documentTitle: title,
            oneLiner: "One line",
            summaryText: "Summary body",
            keyPoints: ["Point"],
            documentBlocks: [
                TimelineAISummaryBlock(kind: "heading", level: 2, text: title, items: []),
                TimelineAISummaryBlock(kind: "paragraph", level: 0, text: "Summary body", items: [])
            ],
            suggestedTags: [tag],
            reviewContent: ReviewContentPayload(
                title: title,
                subtitle: nil,
                bodyMarkdown: "## \(title)\n\nSummary body",
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
            tokenUsage: AITokenUsage(inputTokens: 50, outputTokens: 12, totalTokens: 62)
        )
    }
}

private final class InvalidAIProviderURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"unexpected":"shape"}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class PromptCaptureURLProtocol: URLProtocol {
    static var requestBody: Data?
    static var usageJSON: String?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.requestBody = request.httpBody ?? Self.readBodyStream(from: request)
        let content = """
        {"documentTitle":"中文标题","oneLiner":"一句话","summaryText":"摘要","keyPoints":[],"documentBlocks":[],"suggestedTags":[]}
        """
        let escapedContent = content
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        let usageSuffix = Self.usageJSON.map { ",\"usage\":\($0)" } ?? ""
        let body = """
        {"choices":[{"message":{"content":"\(escapedContent)"}}]\(usageSuffix)}
        """
        let data = Data(body.utf8)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func readBodyStream(from request: URLRequest) -> Data? {
        guard let stream = request.httpBodyStream else {
            return nil
        }

        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 {
                break
            }
            data.append(buffer, count: count)
        }
        return data.isEmpty ? nil : data
    }
}
