import XCTest
@testable import PrivateMoments

final class CloudKitRecordMapperTests: XCTestCase {
    func testMapsTimelinePostToRecordPayloadWithoutServerSyncRuntimeFields() {
        let now = Date(timeIntervalSince1970: 3_000)
        let post = TimelinePost(
            id: "post-1",
            text: "A private note",
            isFavorite: true,
            isPinned: true,
            pinnedAt: now.addingTimeInterval(1),
            aiTagProcessedAt: now.addingTimeInterval(2),
            tagsUserEditedAt: now.addingTimeInterval(3),
            occurredAt: now.addingTimeInterval(4),
            localCreatedAt: now.addingTimeInterval(5),
            localUpdatedAt: now.addingTimeInterval(6),
            localEditedAt: now.addingTimeInterval(7),
            serverVersion: 99,
            syncStatus: "failed",
            deletedAt: nil
        )

        let payload = CloudKitRecordMapper.payload(for: post)

        XCTAssertEqual(payload.entityType, .moment)
        XCTAssertEqual(payload.entityId, "post-1")
        XCTAssertEqual(payload.recordType, "PMMoment")
        XCTAssertEqual(payload.recordName, "pm.moment.post-1")
        XCTAssertEqual(payload.fields["text"], .string("A private note"))
        XCTAssertEqual(payload.fields["isFavorite"], .bool(true))
        XCTAssertEqual(payload.fields["isPinned"], .bool(true))
        XCTAssertEqual(payload.fields["occurredAt"], .date(now.addingTimeInterval(4)))
        XCTAssertNil(payload.fields["serverVersion"])
        XCTAssertNil(payload.fields["syncStatus"])
    }

    func testMapsTimelineTagIncludingArchiveAndArea() {
        let now = Date(timeIntervalSince1970: 3_200)
        var tag = TimelineTag(
            id: "topic-product",
            type: "topic",
            name: "筛选设计",
            normalizedName: "筛选设计",
            colorHex: "#DDEEFF",
            isDefault: false,
            isArchived: true,
            aiUsableAsPrimary: false,
            createdAt: now,
            updatedAt: now.addingTimeInterval(10),
            archivedAt: now.addingTimeInterval(20)
        )
        tag.areaId = TopicTagArea.productDesign.rawValue

        let payload = CloudKitRecordMapper.payload(for: tag)

        XCTAssertEqual(payload.entityType, .tag)
        XCTAssertEqual(payload.recordType, "PMTag")
        XCTAssertEqual(payload.fields["type"], .string("topic"))
        XCTAssertEqual(payload.fields["name"], .string("筛选设计"))
        XCTAssertEqual(payload.fields["colorHex"], .string("#DDEEFF"))
        XCTAssertEqual(payload.fields["isArchived"], .bool(true))
        XCTAssertEqual(payload.fields["areaId"], .string(TopicTagArea.productDesign.rawValue))
        XCTAssertEqual(payload.fields["archivedAt"], .date(now.addingTimeInterval(20)))
    }

    func testMapsTimelineAssignedTagAsRelationshipPayload() {
        let now = Date(timeIntervalSince1970: 3_400)
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
            archivedAt: nil
        )
        let assignment = TimelineAssignedTag(
            id: "assignment-1",
            postId: "post-1",
            tagId: "topic-ai",
            role: "topic",
            source: "ai",
            confidence: 0.88,
            aiSummaryId: "summary-1",
            createdAt: now.addingTimeInterval(1),
            updatedAt: now.addingTimeInterval(2),
            deletedAt: nil,
            tag: tag
        )

        let payload = CloudKitRecordMapper.payload(for: assignment)

        XCTAssertEqual(payload.entityType, .postTag)
        XCTAssertEqual(payload.recordType, "PMPostTag")
        XCTAssertEqual(payload.fields["postId"], .string("post-1"))
        XCTAssertEqual(payload.fields["tagId"], .string("topic-ai"))
        XCTAssertEqual(payload.fields["confidence"], .double(0.88))
        XCTAssertEqual(payload.fields["aiSummaryId"], .string("summary-1"))
        XCTAssertNil(payload.fields["tag"])
        XCTAssertNil(payload.fields["tagName"])
        XCTAssertNil(payload.fields["serverVersion"])
        XCTAssertNil(payload.fields["syncStatus"])
    }

    func testMapsTimelineMediaMetadataWithoutLocalServerOrTranscriptFields() {
        let now = Date(timeIntervalSince1970: 3_600)
        let media = TimelineMedia(
            id: "media-1",
            postId: "post-1",
            kind: "audio",
            localCompressedPath: "/private/local/audio.m4a",
            localOriginalStagingPath: "/private/local/original.m4a",
            localThumbnailPath: "/private/local/thumb.jpg",
            remoteCompressedPath: "/server/audio.m4a",
            remoteOriginalPath: "/server/original.m4a",
            remoteThumbnailPath: "/server/thumb.jpg",
            originalPreserved: true,
            uploadStatus: "failed",
            mimeType: "audio/mp4",
            durationSeconds: 42.5,
            transcriptionText: "private transcript",
            transcriptionStatus: "ready",
            transcriptionError: "do not sync",
            transcriptionUpdatedAt: now.addingTimeInterval(1),
            sortOrder: 2,
            checksum: "sha256:abc",
            createdAt: now.addingTimeInterval(2),
            updatedAt: now.addingTimeInterval(3)
        )

        let payload = CloudKitRecordMapper.payload(for: media)

        XCTAssertEqual(payload.entityType, .media)
        XCTAssertEqual(payload.recordType, "PMMedia")
        XCTAssertEqual(payload.fields["postId"], .string("post-1"))
        XCTAssertEqual(payload.fields["kind"], .string("audio"))
        XCTAssertEqual(payload.fields["originalPreserved"], .bool(true))
        XCTAssertEqual(payload.fields["mimeType"], .string("audio/mp4"))
        XCTAssertEqual(payload.fields["durationSeconds"], .double(42.5))
        XCTAssertEqual(payload.fields["sortOrder"], .int(2))
        XCTAssertEqual(payload.fields["checksum"], .string("sha256:abc"))
        XCTAssertNil(payload.fields["localCompressedPath"])
        XCTAssertNil(payload.fields["localOriginalStagingPath"])
        XCTAssertNil(payload.fields["localThumbnailPath"])
        XCTAssertNil(payload.fields["remoteCompressedPath"])
        XCTAssertNil(payload.fields["remoteOriginalPath"])
        XCTAssertNil(payload.fields["remoteThumbnailPath"])
        XCTAssertNil(payload.fields["uploadStatus"])
        XCTAssertNil(payload.fields["transcriptionText"])
        XCTAssertNil(payload.fields["transcriptionStatus"])
        XCTAssertNil(payload.fields["transcriptionError"])
    }

    func testMapsTimelineAISummaryDisplayContentWithoutProviderDiagnostics() throws {
        let now = Date(timeIntervalSince1970: 3_800)
        let sections = [
            TimelineAISummarySection(heading: "Highlights", bullets: ["One", "Two"])
        ]
        let blocks = [
            TimelineAISummaryBlock(kind: "heading", level: 2, text: "Plan", items: []),
            TimelineAISummaryBlock(kind: "list", level: 0, text: "", items: ["A", "B"])
        ]
        let summary = TimelineAISummary(
            id: "summary-1",
            postId: "post-1",
            mediaId: "media-1",
            status: "ready",
            format: "document",
            language: "zh-Hans",
            overview: "Overview",
            keyPoints: ["One", "Two"],
            sections: sections,
            summaryText: "Summary body",
            documentTitle: "Document title",
            oneLiner: "One line",
            documentBlocks: blocks,
            inputTranscriptLength: 1_000,
            inputDurationSeconds: 120,
            inputTokenCount: 300,
            outputTokenCount: 80,
            totalTokenCount: 380,
            promptVersion: "media-summary-v4",
            provider: "deepseek",
            model: "model-name",
            errorCode: "provider_error",
            errorMessage: "private diagnostic",
            createdAt: now,
            updatedAt: now.addingTimeInterval(1),
            deletedAt: nil
        )

        let payload = CloudKitRecordMapper.payload(for: summary)

        XCTAssertEqual(payload.entityType, .aiSummary)
        XCTAssertEqual(payload.recordType, "PMAISummary")
        XCTAssertEqual(payload.fields["postId"], .string("post-1"))
        XCTAssertEqual(payload.fields["mediaId"], .string("media-1"))
        XCTAssertEqual(payload.fields["status"], .string("ready"))
        XCTAssertEqual(payload.fields["keyPoints"], .stringList(["One", "Two"]))
        XCTAssertEqual(payload.fields["promptVersion"], .string("media-summary-v4"))
        XCTAssertEqual(try decodedField([TimelineAISummarySection].self, "sections", payload), sections)
        XCTAssertEqual(try decodedField([TimelineAISummaryBlock].self, "documentBlocks", payload), blocks)
        XCTAssertNil(payload.fields["inputTranscriptLength"])
        XCTAssertNil(payload.fields["inputDurationSeconds"])
        XCTAssertNil(payload.fields["inputTokenCount"])
        XCTAssertNil(payload.fields["outputTokenCount"])
        XCTAssertNil(payload.fields["totalTokenCount"])
        XCTAssertNil(payload.fields["provider"])
        XCTAssertNil(payload.fields["model"])
        XCTAssertNil(payload.fields["errorCode"])
        XCTAssertNil(payload.fields["errorMessage"])
    }

    func testMapsCheckInItemAndEntryBusinessFieldsWithoutSyncStatus() {
        let now = Date(timeIntervalSince1970: 4_000)
        let item = CheckInItem(
            id: "item-1",
            name: "Workout",
            symbolName: "figure.run",
            colorHex: "#22AA66",
            recordMode: .multiplePerDay,
            timeVisualization: .timeHeatmap,
            dayStartHour: 5,
            activeWeekdays: [2, 4, 6],
            sortOrder: 3,
            defaultShowInTimeline: true,
            tagId: "tag-health",
            createdAt: now,
            updatedAt: now.addingTimeInterval(1),
            archivedAt: now.addingTimeInterval(2),
            deletedAt: nil,
            syncStatus: "failed"
        )
        let entry = CheckInEntry(
            id: "entry-1",
            itemId: "item-1",
            occurredAt: now.addingTimeInterval(3),
            note: "Felt good",
            showInTimeline: true,
            createdAt: now.addingTimeInterval(4),
            updatedAt: now.addingTimeInterval(5),
            deletedAt: nil,
            syncStatus: "pending"
        )

        let itemPayload = CloudKitRecordMapper.payload(for: item)
        let entryPayload = CloudKitRecordMapper.payload(for: entry)

        XCTAssertEqual(itemPayload.entityType, .checkInItem)
        XCTAssertEqual(itemPayload.fields["name"], .string("Workout"))
        XCTAssertEqual(itemPayload.fields["recordMode"], .string("multiplePerDay"))
        XCTAssertEqual(itemPayload.fields["timeVisualization"], .string("timeHeatmap"))
        XCTAssertEqual(itemPayload.fields["dayStartHour"], .int(5))
        XCTAssertEqual(itemPayload.fields["activeWeekdays"], .stringList(["2", "4", "6"]))
        XCTAssertEqual(itemPayload.fields["defaultShowInTimeline"], .bool(true))
        XCTAssertEqual(itemPayload.fields["tagId"], .string("tag-health"))
        XCTAssertNil(itemPayload.fields["syncStatus"])

        XCTAssertEqual(entryPayload.entityType, .checkInEntry)
        XCTAssertEqual(entryPayload.fields["itemId"], .string("item-1"))
        XCTAssertEqual(entryPayload.fields["note"], .string("Felt good"))
        XCTAssertEqual(entryPayload.fields["showInTimeline"], .bool(true))
        XCTAssertNil(entryPayload.fields["syncStatus"])
    }

    func testMapsCheckInMediaAndAISummaryWithoutLocalRuntimeOrProviderFields() throws {
        let now = Date(timeIntervalSince1970: 4_200)
        let media = CheckInMedia(
            id: "checkin-media-1",
            entryId: "entry-1",
            kind: "video",
            localCompressedPath: "/local/video.mp4",
            remoteCompressedPath: "/server/video.mp4",
            uploadStatus: "failed",
            uploadError: "offline",
            mimeType: "video/mp4",
            durationSeconds: 8,
            transcriptionText: "private transcript",
            transcriptionStatus: "ready",
            transcriptionError: "diagnostic",
            transcriptionUpdatedAt: now,
            sortOrder: 1,
            checksum: "sha256:def",
            createdAt: now.addingTimeInterval(1),
            updatedAt: now.addingTimeInterval(2),
            deletedAt: nil
        )
        let blocks = [
            TimelineAISummaryBlock(kind: "paragraph", level: 0, text: "A short recap", items: [])
        ]
        let summary = CheckInAISummary(
            id: "checkin-summary-1",
            entryId: "entry-1",
            mediaId: "checkin-media-1",
            status: "ready",
            format: "document",
            language: "en",
            overview: "Overview",
            keyPoints: ["A"],
            sections: [],
            summaryText: "Summary",
            documentTitle: "Workout clip",
            oneLiner: "A quick workout note",
            documentBlocks: blocks,
            inputTranscriptLength: 500,
            inputDurationSeconds: 8,
            inputTokenCount: 100,
            outputTokenCount: 40,
            totalTokenCount: 140,
            promptVersion: "checkin-summary-v1",
            provider: "openai",
            model: "model-name",
            errorCode: "failed",
            errorMessage: "diagnostic",
            createdAt: now.addingTimeInterval(3),
            updatedAt: now.addingTimeInterval(4),
            deletedAt: nil
        )

        let mediaPayload = CloudKitRecordMapper.payload(for: media)
        let summaryPayload = CloudKitRecordMapper.payload(for: summary)

        XCTAssertEqual(mediaPayload.entityType, .checkInMedia)
        XCTAssertEqual(mediaPayload.fields["entryId"], .string("entry-1"))
        XCTAssertEqual(mediaPayload.fields["kind"], .string("video"))
        XCTAssertEqual(mediaPayload.fields["mimeType"], .string("video/mp4"))
        XCTAssertEqual(mediaPayload.fields["durationSeconds"], .double(8))
        XCTAssertEqual(mediaPayload.fields["sortOrder"], .int(1))
        XCTAssertEqual(mediaPayload.fields["checksum"], .string("sha256:def"))
        XCTAssertNil(mediaPayload.fields["localCompressedPath"])
        XCTAssertNil(mediaPayload.fields["remoteCompressedPath"])
        XCTAssertNil(mediaPayload.fields["uploadStatus"])
        XCTAssertNil(mediaPayload.fields["uploadError"])
        XCTAssertNil(mediaPayload.fields["transcriptionText"])

        XCTAssertEqual(summaryPayload.entityType, .checkInAISummary)
        XCTAssertEqual(summaryPayload.fields["entryId"], .string("entry-1"))
        XCTAssertEqual(summaryPayload.fields["mediaId"], .string("checkin-media-1"))
        XCTAssertEqual(summaryPayload.fields["keyPoints"], .stringList(["A"]))
        XCTAssertEqual(try decodedField([TimelineAISummaryBlock].self, "documentBlocks", summaryPayload), blocks)
        XCTAssertNil(summaryPayload.fields["inputTranscriptLength"])
        XCTAssertNil(summaryPayload.fields["inputDurationSeconds"])
        XCTAssertNil(summaryPayload.fields["inputTokenCount"])
        XCTAssertNil(summaryPayload.fields["provider"])
        XCTAssertNil(summaryPayload.fields["model"])
        XCTAssertNil(summaryPayload.fields["errorCode"])
        XCTAssertNil(summaryPayload.fields["errorMessage"])
    }

    func testMapsWeeklyReviewDisplayContentWithoutProviderDiagnostics() throws {
        let review = Self.weeklyReview(
            id: "review-1",
            updatedAt: "2026-06-03T10:20:30Z",
            deletedAt: nil
        )

        let payload = CloudKitRecordMapper.payload(for: review)

        XCTAssertEqual(payload.entityType, .weeklyReview)
        XCTAssertEqual(payload.recordType, "PMWeeklyReview")
        XCTAssertEqual(payload.recordName, "pm.weekly_review.review-1")
        XCTAssertEqual(payload.fields["kind"], .string("weekly"))
        XCTAssertEqual(payload.fields["rangeMode"], .string("weekly"))
        XCTAssertEqual(payload.fields["rangeStart"], .string("2026-05-27T10:20:30Z"))
        XCTAssertEqual(payload.fields["rangeEnd"], .string("2026-06-03T10:20:30Z"))
        XCTAssertEqual(payload.fields["status"], .string("ready"))
        XCTAssertEqual(payload.fields["trigger"], .string("manual"))
        XCTAssertEqual(payload.fields["promptVersion"], .string("weekly-review-v1"))
        XCTAssertEqual(payload.fields["language"], .string("zh-Hans"))
        XCTAssertEqual(payload.fields["generatedAt"], .string("2026-06-03T10:20:30Z"))
        XCTAssertEqual(payload.fields["publishedPostId"], .string("review-post-1"))
        XCTAssertEqual(payload.fields["createdAt"], .string("2026-06-03T10:20:00Z"))
        XCTAssertEqual(payload.fields["updatedAt"], .string("2026-06-03T10:20:30Z"))
        let content = try decodedField(ReviewContentPayload.self, "content", payload)
        XCTAssertEqual(content.title, "A useful week")
        XCTAssertEqual(content.oneLiner, "Several ideas became concrete.")
        let feedback = try decodedField(ReviewFeedbackStatePayload.self, "feedback", payload)
        XCTAssertEqual(feedback.selectedTypes, ["more_concrete"])
        XCTAssertEqual(feedback.customNote, "Keep it practical.")
        XCTAssertNil(payload.fields["provider"])
        XCTAssertNil(payload.fields["model"])
        XCTAssertNil(payload.fields["errorCode"])
        XCTAssertNil(payload.fields["errorMessage"])
    }

    func testMapsPreferenceSnapshotWithOnlyCloudSafePreferenceFields() {
        let snapshot = CloudKitPreferenceSnapshot(
            showTagsInTimeline: false,
            showCheckInSummaries: true,
            memoryLinksEnabled: false,
            aiTitleAutoInsertEnabled: true,
            appAppearanceMode: .dark,
            appLanguageMode: .simplifiedChinese,
            aiLanguageMode: .chinese,
            aiAnalysisEnabled: true,
            aiExternalProcessingConsentAccepted: true,
            useTextProviderForTranscription: true,
            transcriptionProviderMode: .customOpenAICompatible,
            preferredSpeechTranscriptionLocaleIdentifier: "zh-CN",
            autoWeeklyReviewEnabled: true,
            publishWeeklyReviewToMoments: false,
            markdownMathRenderingEnabled: true,
            markdownRemoteImagesEnabled: false,
            markdownRawHTMLRenderingEnabled: true
        )

        let payload = CloudKitRecordMapper.payload(for: snapshot)

        XCTAssertEqual(payload.entityType, .preference)
        XCTAssertEqual(payload.entityId, "app")
        XCTAssertEqual(payload.recordType, "PMPreference")
        XCTAssertEqual(payload.recordName, "pm.preference.app")
        XCTAssertEqual(payload.fields["schemaVersion"], .int(1))
        XCTAssertEqual(payload.fields["showTagsInTimeline"], .bool(false))
        XCTAssertEqual(payload.fields["showCheckInSummaries"], .bool(true))
        XCTAssertEqual(payload.fields["memoryLinksEnabled"], .bool(false))
        XCTAssertEqual(payload.fields["aiTitleAutoInsertEnabled"], .bool(true))
        XCTAssertEqual(payload.fields["appAppearanceMode"], .string("dark"))
        XCTAssertEqual(payload.fields["appLanguageMode"], .string("simplifiedChinese"))
        XCTAssertEqual(payload.fields["aiLanguageMode"], .string("chinese"))
        XCTAssertEqual(payload.fields["aiAnalysisEnabled"], .bool(true))
        XCTAssertEqual(payload.fields["aiExternalProcessingConsentAccepted"], .bool(true))
        XCTAssertEqual(payload.fields["useTextProviderForTranscription"], .bool(true))
        XCTAssertEqual(payload.fields["transcriptionProviderMode"], .string("custom_openai_compatible"))
        XCTAssertEqual(payload.fields["preferredSpeechTranscriptionLocaleIdentifier"], .string("zh-CN"))
        XCTAssertEqual(payload.fields["autoWeeklyReviewEnabled"], .bool(true))
        XCTAssertEqual(payload.fields["publishWeeklyReviewToMoments"], .bool(false))
        XCTAssertEqual(payload.fields["markdownMathRenderingEnabled"], .bool(true))
        XCTAssertEqual(payload.fields["markdownRemoteImagesEnabled"], .bool(false))
        XCTAssertEqual(payload.fields["markdownRawHTMLRenderingEnabled"], .bool(true))
        XCTAssertNil(payload.fields["serverURLString"])
        XCTAssertNil(payload.fields["deviceId"])
        XCTAssertNil(payload.fields["deviceKey"])
        XCTAssertNil(payload.fields["lastSyncCursor"])
        XCTAssertNil(payload.fields["automaticSyncEnabled"])
        XCTAssertNil(payload.fields["aiProviderProfiles"])
        XCTAssertNil(payload.fields["aiProviderFallbackState"])
        XCTAssertNil(payload.fields["localTranscriptionGatewaySettings"])
        XCTAssertNil(payload.fields["lastMediaDownloadError"])
        XCTAssertNil(payload.fields["localWeeklyReviews"])
        XCTAssertNil(payload.fields["welcomeOnboardingShown"])
        XCTAssertNil(payload.fields["welcomeSampleDeleted"])
    }

    func testMapsDraftSnapshotsWithoutEmbeddingDraftMediaBytes() {
        let occurredAt = Date(timeIntervalSince1970: 9_000)
        let updatedAt = occurredAt.addingTimeInterval(120)
        let composer = CloudKitDraftSnapshot(
            kind: .composer,
            entityId: CloudKitDraftSnapshot.composerRecordId,
            postId: nil,
            text: "A half-written private note",
            occurredAt: occurredAt,
            updatedAt: updatedAt,
            existingMediaIds: [],
            hasUnsupportedMediaDrafts: true
        )
        let edit = CloudKitDraftSnapshot(
            kind: .editMoment,
            entityId: CloudKitDraftSnapshot.editRecordId(postId: "post-1"),
            postId: "post-1",
            text: "Edited but not saved yet",
            occurredAt: occurredAt.addingTimeInterval(-300),
            updatedAt: updatedAt.addingTimeInterval(10),
            existingMediaIds: ["media-1", "media-2"],
            hasUnsupportedMediaDrafts: false
        )

        let composerPayload = CloudKitRecordMapper.payload(for: composer)
        let editPayload = CloudKitRecordMapper.payload(for: edit)

        XCTAssertEqual(composerPayload.entityType, .draft)
        XCTAssertEqual(composerPayload.entityId, "composer")
        XCTAssertEqual(composerPayload.recordType, "PMDraft")
        XCTAssertEqual(composerPayload.recordName, "pm.draft.composer")
        XCTAssertEqual(composerPayload.fields["schemaVersion"], .int(1))
        XCTAssertEqual(composerPayload.fields["draftKind"], .string("composer"))
        XCTAssertEqual(composerPayload.fields["text"], .string("A half-written private note"))
        XCTAssertEqual(composerPayload.fields["occurredAt"], .date(occurredAt))
        XCTAssertEqual(composerPayload.fields["updatedAt"], .date(updatedAt))
        XCTAssertEqual(composerPayload.fields["existingMediaIds"], .stringList([]))
        XCTAssertEqual(composerPayload.fields["hasUnsupportedMediaDrafts"], .bool(true))
        XCTAssertNil(composerPayload.fields["mediaBytes"])
        XCTAssertNil(composerPayload.fields["localFilePath"])

        XCTAssertEqual(editPayload.entityType, .draft)
        XCTAssertEqual(editPayload.entityId, "edit:post-1")
        XCTAssertEqual(editPayload.recordName, "pm.draft.edit_post-1")
        XCTAssertEqual(editPayload.fields["draftKind"], .string("edit_moment"))
        XCTAssertEqual(editPayload.fields["postId"], .string("post-1"))
        XCTAssertEqual(editPayload.fields["existingMediaIds"], .stringList(["media-1", "media-2"]))
        XCTAssertEqual(editPayload.fields["hasUnsupportedMediaDrafts"], .bool(false))
        XCTAssertNil(editPayload.fields["newMediaBytes"])
    }

    private func decodedField<T: Decodable>(
        _ type: T.Type,
        _ key: String,
        _ payload: CloudKitRecordPayload
    ) throws -> T {
        guard case .string(let rawValue) = payload.fields[key] else {
            XCTFail("Expected \(key) to be encoded as a string")
            throw TestError.missingJSONField
        }

        let data = try XCTUnwrap(rawValue.data(using: .utf8))
        return try JSONDecoder().decode(T.self, from: data)
    }
}

private extension CloudKitRecordMapperTests {
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

private enum TestError: Error {
    case missingJSONField
}
