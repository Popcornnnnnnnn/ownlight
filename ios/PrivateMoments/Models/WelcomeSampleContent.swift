import Foundation

enum WelcomeSampleContent {
    static let postId = "welcome-sample-post-v1"
    static let audioMediaId = "welcome-sample-audio-v1"
    static let summaryId = "welcome-sample-summary-v1"
    static let commentId = "welcome-sample-comment-v1"
    static let privateTimelineTopicId = "welcome-sample-topic-private-timeline-v1"
    static let aiSummaryTopicId = "welcome-sample-topic-ai-summary-v1"
    static let topicTagIds = [privateTimelineTopicId, aiSummaryTopicId]

    private static let idPrefix = "welcome-sample-"

    static func isSamplePostId(_ id: String) -> Bool {
        id == postId || id.hasPrefix(idPrefix)
    }

    static func isSampleMediaId(_ id: String) -> Bool {
        id == audioMediaId || id.hasPrefix("\(idPrefix)audio-") || id.hasPrefix("\(idPrefix)media-")
    }

    static func isSampleTagId(_ id: String) -> Bool {
        topicTagIds.contains(id) || id.hasPrefix("\(idPrefix)topic-")
    }

    static func isSampleCommentId(_ id: String) -> Bool {
        id == commentId || id.hasPrefix("\(idPrefix)comment-")
    }

    static func isSampleAISummaryId(_ id: String) -> Bool {
        id == summaryId || id.hasPrefix("\(idPrefix)summary-")
    }

    static func isSample(_ item: TimelineItem) -> Bool {
        isSamplePostId(item.post.id)
    }

    static func postText(language: AppResolvedLanguage) -> String {
        switch language {
        case .simplifiedChinese:
            return """
            # 你的第一条 Moment

            一条只给自己看的私人 timeline：没有观众，也不需要账号。

            ## 一条记录可以很轻

            写几句话，放一段语音，补一句评论，再用 topic tags 帮自己以后找回。
            """
        case .english:
            return """
            # Your first Moment

            A private timeline entry with no audience, account, or public feed.

            ## A moment can stay light

            Write a few lines, add voice, leave a small comment, and use topic tags to find it later.
            """
        }
    }

    static func topicTags(language: AppResolvedLanguage, now: Date) -> [TimelineTag] {
        [
            TimelineTag(
                id: privateTimelineTopicId,
                type: "topic",
                name: language == .simplifiedChinese ? "私人时间线" : "Private timeline",
                normalizedName: LocalDatabase.normalizedTagName(language == .simplifiedChinese ? "私人时间线" : "Private timeline"),
                colorHex: nil,
                isDefault: false,
                isArchived: false,
                aiUsableAsPrimary: false,
                createdAt: now,
                updatedAt: now,
                archivedAt: nil,
                areaId: TopicTagArea.life.rawValue
            ),
            TimelineTag(
                id: aiSummaryTopicId,
                type: "topic",
                name: language == .simplifiedChinese ? "AI 总结" : "AI summaries",
                normalizedName: LocalDatabase.normalizedTagName(language == .simplifiedChinese ? "AI 总结" : "AI summaries"),
                colorHex: nil,
                isDefault: false,
                isArchived: false,
                aiUsableAsPrimary: false,
                createdAt: now,
                updatedAt: now,
                archivedAt: nil,
                areaId: TopicTagArea.productDesign.rawValue
            )
        ]
    }

    static func comment(language: AppResolvedLanguage, now: Date) -> TimelineComment {
        TimelineComment(
            id: commentId,
            postId: postId,
            text: language == .simplifiedChinese
                ? "评论可以放一句补充。"
                : "Comments can hold a small follow-up.",
            createdAt: now.addingTimeInterval(3),
            updatedAt: now.addingTimeInterval(3),
            serverVersion: nil,
            deletedAt: nil
        )
    }

    static func audioMedia(now: Date) -> TimelineMedia {
        TimelineMedia(
            id: audioMediaId,
            postId: postId,
            kind: "audio",
            localCompressedPath: "",
            localOriginalStagingPath: nil,
            localThumbnailPath: nil,
            remoteCompressedPath: nil,
            remoteOriginalPath: nil,
            remoteThumbnailPath: nil,
            originalPreserved: false,
            uploadStatus: "synced",
            mimeType: "audio/mp4",
            durationSeconds: 42,
            transcriptionText: nil,
            transcriptionStatus: "ready",
            transcriptionError: nil,
            transcriptionUpdatedAt: now.addingTimeInterval(2),
            sortOrder: 0,
            checksum: nil,
            createdAt: now,
            updatedAt: now
        )
    }

    static func summary(language: AppResolvedLanguage, now: Date) -> TimelineAISummary {
        let blocks: [TimelineAISummaryBlock]
        let title: String
        let oneLiner: String
        let summaryText: String

        switch language {
        case .simplifiedChinese:
            title = "Sample generated summary"
            oneLiner = "AI summary 只是补充功能；可在 Settings > AI & Analysis 中配置。"
            summaryText = "示例音频展示语音 summary 如何辅助回顾。"
            blocks = [
                TimelineAISummaryBlock(kind: "heading", level: 2, text: "可以怎么辅助回看", items: []),
                TimelineAISummaryBlock(kind: "paragraph", level: 0, text: "语音内容可以整理成一句摘要和少量要点；没有配置 AI 时，普通记录功能仍然完整可用。", items: []),
                TimelineAISummaryBlock(kind: "callout", level: 0, text: "这条示例没有发送给任何 AI provider。", items: [])
            ]
        case .english:
            title = "Sample generated summary"
            oneLiner = "AI summaries are optional; configure them later in Settings > AI & Analysis."
            summaryText = "The sample audio shows how a voice summary can support review."
            blocks = [
                TimelineAISummaryBlock(kind: "heading", level: 2, text: "How it can help review", items: []),
                TimelineAISummaryBlock(kind: "paragraph", level: 0, text: "Voice notes can become one short summary plus a few useful points; core timeline capture still works without AI.", items: []),
                TimelineAISummaryBlock(kind: "callout", level: 0, text: "This sample was not sent to any AI provider.", items: [])
            ]
        }

        return TimelineAISummary(
            id: summaryId,
            postId: postId,
            mediaId: audioMediaId,
            status: "ready",
            format: "document",
            language: language == .simplifiedChinese ? "zh" : "en",
            overview: oneLiner,
            keyPoints: language == .simplifiedChinese
                ? [
                    "语音可以整理成几句重点。",
                    "真实 summary 使用你自己配置的 provider。"
                ]
                : [
                    "Voice can be reduced to a few useful notes.",
                    "Real summaries use the provider you configure."
                ],
            sections: [],
            summaryText: summaryText,
            documentTitle: title,
            oneLiner: oneLiner,
            documentBlocks: blocks,
            inputTranscriptLength: nil,
            inputDurationSeconds: 42,
            inputTokenCount: nil,
            outputTokenCount: nil,
            totalTokenCount: nil,
            promptVersion: "welcome-sample-v1",
            provider: "Sample",
            model: "Welcome Sample",
            errorCode: nil,
            errorMessage: nil,
            createdAt: now.addingTimeInterval(2),
            updatedAt: now.addingTimeInterval(2),
            deletedAt: nil
        )
    }
}
