import Foundation
import SQLite3
import UIKit

extension LocalDatabase {
    func seedDemoDataIfNeeded(
        reset: Bool = false,
        now: Date = Date(),
        calendar: Calendar = .current,
        language: AppResolvedLanguage = .english
    ) throws {
        let isChinese = language == .simplifiedChinese

        if reset {
            try deleteDemoData()
        }

        let existingDemoPosts = try count("SELECT COUNT(*) FROM local_posts WHERE id LIKE 'demo-%'")
        guard existingDemoPosts == 0 else {
            return
        }

        let today = calendar.startOfDay(for: now)
        let demoDeviceDate = calendar.date(byAdding: .day, value: -1, to: today) ?? today

        let topicTags = [
            TimelineTag(
                id: "demo-topic-local-first",
                type: "topic",
                name: isChinese ? "本地优先" : "local-first",
                normalizedName: Self.normalizedTagName(isChinese ? "本地优先" : "local-first"),
                colorHex: "#B9D6C2",
                isDefault: false,
                isArchived: false,
                aiUsableAsPrimary: false,
                createdAt: demoDeviceDate,
                updatedAt: demoDeviceDate,
                archivedAt: nil,
                areaId: TopicTagArea.technology.rawValue
            ),
            TimelineTag(
                id: "demo-topic-audio-notes",
                type: "topic",
                name: isChinese ? "语音记录" : "audio notes",
                normalizedName: Self.normalizedTagName(isChinese ? "语音记录" : "audio notes"),
                colorHex: "#D8C6F0",
                isDefault: false,
                isArchived: false,
                aiUsableAsPrimary: false,
                createdAt: demoDeviceDate,
                updatedAt: demoDeviceDate,
                archivedAt: nil,
                areaId: TopicTagArea.life.rawValue
            ),
            TimelineTag(
                id: "demo-topic-trip",
                type: "topic",
                name: isChinese ? "周末散步" : "weekend trip",
                normalizedName: Self.normalizedTagName(isChinese ? "周末散步" : "weekend trip"),
                colorHex: "#F0D0B6",
                isDefault: false,
                isArchived: false,
                aiUsableAsPrimary: false,
                createdAt: demoDeviceDate,
                updatedAt: demoDeviceDate,
                archivedAt: nil,
                areaId: TopicTagArea.life.rawValue
            ),
            TimelineTag(
                id: "demo-topic-markdown-writing",
                type: "topic",
                name: isChinese ? "Markdown 写作" : "Markdown writing",
                normalizedName: Self.normalizedTagName(isChinese ? "Markdown 写作" : "Markdown writing"),
                colorHex: "#C7DCF8",
                isDefault: false,
                isArchived: false,
                aiUsableAsPrimary: false,
                createdAt: demoDeviceDate,
                updatedAt: demoDeviceDate,
                archivedAt: nil,
                areaId: TopicTagArea.learningKnowledge.rawValue
            ),
        ]

        let posts = [
            DemoPost(
                id: "demo-post-audio-summary",
                text: isChinese
                    ? "## 早晨散步后的语音\n走完一圈之后录了两分钟想法。原本只是随口说说，后来被整理成摘要和主题标签，回头看时不用重新听完整录音。"
                    : "## Morning field note\nRecorded a short reflection after the walk. On-device transcription and the configured AI provider turned it into a structured summary with suggested topic tags.",
                primaryTagId: "tag-primary-learning",
                topicTagIds: ["demo-topic-audio-notes", "demo-topic-local-first"],
                dayOffset: 0,
                hour: 9,
                minute: 12,
                isFavorite: true,
                isPinned: true,
                mediaKind: "audio",
                mediaTitle: isChinese ? "语音记录" : "audio-note",
                imagePalette: nil,
                comments: [isChinese ? "这条适合之后做成周回顾里的一个小线索。" : "Keep the next summary short enough to reuse as the title."],
                summary: DemoSummary(
                    title: isChinese ? "早晨散步后的语音" : "Morning field note",
                    oneLiner: isChinese
                        ? "这段语音把散步后的状态、今天想做的小事和后续整理方向串了起来。"
                        : "A compact reflection about local-first capture, walking, and the next writing block.",
                    bullets: isChinese
                        ? [
                            "先记录当下，再等网络和 AI 准备好时补充整理。",
                            "今天真正重要的是把下一段文字写小一点、写具体一点。",
                            "主题标签复用了已有方向，没有再制造一堆重复分类。"
                        ]
                        : [
                            "Capture happened offline first, then synced when iCloud was available.",
                            "The useful action item is to keep the next draft small and concrete.",
                            "Suggested tags reused the existing local-first vocabulary."
                        ],
                    language: isChinese ? "zh-Hans" : "en",
                    detailsHeading: isChinese ? "录音里提到的线索" : "Key points",
                    callout: isChinese ? "AI 建议的主题会显示在这条记录下面，之后仍然可以手动调整。" : "AI suggested tags are shown as topic tags on the moment."
                )
            ),
            DemoPost(
                id: "demo-post-photo-grid",
                text: isChinese
                    ? "## 周末照片整理\n只留下几张真正能想起当天气味和路线的照片，其他的就安静待在相册里。"
                    : "## Weekend archive pass\nSorted photos, clipped the important context, and left the rest in the archive instead of the main timeline.",
                primaryTagId: "tag-primary-diary",
                topicTagIds: ["demo-topic-trip"],
                dayOffset: -1,
                hour: 16,
                minute: 35,
                isFavorite: false,
                isPinned: false,
                mediaKind: "image",
                mediaTitle: isChinese ? "周末照片" : "weekend-photo",
                imagePalette: DemoImagePalette(top: UIColor(red: 0.84, green: 0.91, blue: 0.88, alpha: 1), bottom: UIColor(red: 0.93, green: 0.76, blue: 0.61, alpha: 1), accent: UIColor(red: 0.23, green: 0.35, blue: 0.30, alpha: 1)),
                comments: [isChinese ? "照片不用每张都解释，有一句背景就够了。" : "This is the right level of detail for the public demo."],
                summary: nil
            ),
            DemoPost(
                id: "demo-post-markdown-showcase",
                text: isChinese
                    ? """
                    # Markdown 记录模板
                    一条记录可以很短，也可以在需要时写得更有结构。

                    ## 今天留下什么
                    - [x] 先写下原始想法
                    - [ ] 晚上再补一张照片
                    - 支持 **加粗**、_强调_、`inline code` 和链接：[Ownlight](https://private-moments.popcornnn.xyz)

                    ## 小表格
                    | 类型 | 用法 |
                    | --- | --- |
                    | 文字 | 记录完整想法 |
                    | 语音 | 先说出来，再让 AI 摘要 |
                    | 标签 | 自动归到大的生活方向 |

                    > 私密记录不是为了表演，而是给未来的自己留一条线索。
                    """
                    : """
                    # Markdown capture template
                    A moment can stay short, or become structured when it needs more shape.

                    ## What to keep
                    - [x] Capture the raw thought
                    - [ ] Add one image later
                    - Supports **bold**, _emphasis_, `inline code`, and links: [Ownlight](https://private-moments.popcornnn.xyz)

                    ## Compact table
                    | Type | Use |
                    | --- | --- |
                    | Text | Keep the full thought |
                    | Audio | Speak first, summarize later |
                    | Tags | Group related memories |

                    > Private records are not performance. They are clues for your future self.
                    """,
                primaryTagId: "tag-primary-learning",
                topicTagIds: ["demo-topic-markdown-writing", "demo-topic-local-first"],
                dayOffset: -2,
                hour: 20,
                minute: 8,
                isFavorite: false,
                isPinned: false,
                mediaKind: nil,
                mediaTitle: nil,
                imagePalette: nil,
                comments: [],
                summary: nil
            ),
            DemoPost(
                id: "demo-post-text",
                text: isChinese
                    ? "## 上架前检查\n确认本地优先、可选 iCloud、导出恢复和 AI 自带 provider 这些边界都讲清楚。"
                    : "## Release checklist\nREADME should explain the actual product path: iPhone-first capture, optional private replication, local export boundaries, and no provider lock-in.",
                primaryTagId: "tag-primary-review",
                topicTagIds: ["demo-topic-local-first"],
                dayOffset: -3,
                hour: 21,
                minute: 4,
                isFavorite: true,
                isPinned: false,
                mediaKind: nil,
                mediaTitle: nil,
                imagePalette: nil,
                comments: [],
                summary: nil
            ),
        ]

        let checkInItems = [
            DemoCheckInItem(
                id: "demo-checkin-morning-pages",
                name: isChinese ? "晨间记录" : "Morning pages",
                symbolName: "text.book.closed",
                colorHex: "#9CB7D8",
                recordMode: .oncePerDay,
                timeVisualization: .timeLine,
                defaultShowInTimeline: true,
                sortOrder: 0
            ),
            DemoCheckInItem(
                id: "demo-checkin-workout",
                name: isChinese ? "慢跑" : "Workout",
                symbolName: "figure.run",
                colorHex: "#77B889",
                recordMode: .multiplePerDay,
                timeVisualization: .timeHeatmap,
                defaultShowInTimeline: true,
                sortOrder: 1
            ),
            DemoCheckInItem(
                id: "demo-checkin-sleep",
                name: isChinese ? "睡前收尾" : "Sleep wind-down",
                symbolName: "moon.zzz",
                colorHex: "#B7A5D8",
                recordMode: .oncePerDay,
                timeVisualization: .none,
                defaultShowInTimeline: false,
                sortOrder: 2
            ),
        ]

        try transaction {
            for tag in topicTags {
                try upsertTag(tag)
            }

            for post in posts {
                try insertDemoPost(post, today: today, calendar: calendar, createdAt: demoDeviceDate)
            }

            for item in checkInItems {
                try upsertCheckInItemOnly(item.item(createdAt: demoDeviceDate))
            }

            try insertDemoCheckInEntries(today: today, calendar: calendar, createdAt: demoDeviceDate, language: language)
        }
    }

    #if DEBUG
    func seedMemoryLinkMockData(
        now: Date = Date(),
        calendar: Calendar = .current
    ) throws {
        let today = calendar.startOfDay(for: now)
        let sourceDay = calendar
            .date(byAdding: .month, value: -3, to: today)
            .map { calendar.startOfDay(for: $0) } ?? today
        let occurredAt = calendar.date(bySettingHour: 10, minute: 18, second: 0, of: sourceDay) ?? sourceDay
        let postId = "debug-memory-link-post"
        let mediaId = "debug-memory-link-media"
        let topicTagId = "debug-memory-link-topic"
        let createdAt = now

        let deleteTodayStatement = try prepare(
            """
            DELETE FROM local_memory_link_events
            WHERE postId LIKE 'debug-memory-link-%'
               OR shownDate = ?
            """
        )
        defer {
            sqlite3_finalize(deleteTodayStatement)
        }
        try bind(today, to: 1, in: deleteTodayStatement)

        try transaction {
            try stepDone(deleteTodayStatement)
            try execute("DELETE FROM local_ai_summaries WHERE id LIKE 'debug-memory-link-%' OR postId LIKE 'debug-memory-link-%' OR mediaId LIKE 'debug-memory-link-%'")
            try execute("DELETE FROM local_post_tags WHERE id LIKE 'debug-memory-link-%' OR postId LIKE 'debug-memory-link-%' OR tagId LIKE 'debug-memory-link-%'")
            try execute("DELETE FROM local_comments WHERE id LIKE 'debug-memory-link-%' OR postId LIKE 'debug-memory-link-%'")
            try execute("DELETE FROM local_media WHERE id LIKE 'debug-memory-link-%' OR postId LIKE 'debug-memory-link-%'")
            try execute("DELETE FROM local_posts WHERE id LIKE 'debug-memory-link-%'")
            try execute("DELETE FROM local_tag_aliases WHERE id LIKE 'debug-memory-link-%' OR tagId LIKE 'debug-memory-link-%'")
            try execute("DELETE FROM local_tags WHERE id LIKE 'debug-memory-link-%'")

            let tag = TimelineTag(
                id: topicTagId,
                type: "topic",
                name: "Memory Link UAT",
                normalizedName: Self.normalizedTagName("Memory Link UAT"),
                colorHex: "#9CB7D8",
                isDefault: false,
                isArchived: false,
                aiUsableAsPrimary: false,
                createdAt: createdAt,
                updatedAt: createdAt,
                archivedAt: nil
            )
            try upsertTag(tag)

            try insert(
                TimelinePost(
                    id: postId,
                    text: """
                    ## Local-first archive voice note
                    This is a debug-only memory used to review the lightweight timeline link. The moment is intentionally old, text-heavy, and paired with an AI-style audio summary so the selector treats it as meaningful instead of a low-value check-in.
                    """,
                    isFavorite: true,
                    isPinned: false,
                    pinnedAt: nil,
                    aiTagProcessedAt: occurredAt,
                    tagsUserEditedAt: nil,
                    occurredAt: occurredAt,
                    localCreatedAt: occurredAt,
                    localUpdatedAt: occurredAt,
                    localEditedAt: nil,
                    serverVersion: nil,
                    syncStatus: "synced",
                    deletedAt: nil
                )
            )

            let fileURL = try AppDirectories.mediaDirectory().appending(path: "\(mediaId).m4a")
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                try Data("debug memory link audio placeholder".utf8).write(to: fileURL, options: [.atomic])
            }
            try insert(
                TimelineMedia(
                    id: mediaId,
                    postId: postId,
                    kind: "audio",
                    localCompressedPath: fileURL.path,
                    localOriginalStagingPath: nil,
                    localThumbnailPath: nil,
                    remoteCompressedPath: nil,
                    remoteOriginalPath: nil,
                    remoteThumbnailPath: nil,
                    originalPreserved: false,
                    uploadStatus: "uploaded",
                    mimeType: "audio/mp4",
                    durationSeconds: 128,
                    transcriptionText: "Debug placeholder transcript for reviewing the memory link interaction.",
                    transcriptionStatus: "completed",
                    transcriptionError: nil,
                    transcriptionUpdatedAt: occurredAt,
                    sortOrder: 0,
                    checksum: nil,
                    createdAt: occurredAt,
                    updatedAt: occurredAt
                )
            )

            try upsertAISummary(
                DemoSummary(
                    title: "Local-first archive voice note",
                    oneLiner: "A debug memory about private capture, lightweight recall, and keeping the timeline quiet.",
                    bullets: [
                        "The source moment is three months old relative to today.",
                        "The entry has enough text, audio, tags, comments, and a ready summary to pass quality rules.",
                        "Opening the link should jump straight into the original moment detail."
                    ]
                ).summary(postId: postId, mediaId: mediaId, createdAt: occurredAt)
            )

            try insert(
                TimelineComment(
                    id: "debug-memory-link-comment",
                    postId: postId,
                    text: "Use this as the tap target for the first real-device UAT.",
                    createdAt: calendar.date(byAdding: .minute, value: 8, to: occurredAt) ?? occurredAt,
                    updatedAt: calendar.date(byAdding: .minute, value: 8, to: occurredAt) ?? occurredAt,
                    serverVersion: nil,
                    deletedAt: nil
                )
            )

            try upsertAssignedTag(
                TimelineAssignedTag(
                    id: "debug-memory-link-post-tag",
                    postId: postId,
                    tagId: tag.id,
                    role: "topic",
                    source: "ai",
                    confidence: 0.9,
                    aiSummaryId: "demo-summary-\(postId)",
                    createdAt: createdAt,
                    updatedAt: createdAt,
                    deletedAt: nil,
                    tag: tag
                )
            )
        }
    }
    #endif

    private func deleteDemoData() throws {
        try transaction {
            try execute("DELETE FROM local_ai_summaries WHERE id LIKE 'demo-%' OR postId LIKE 'demo-%' OR mediaId LIKE 'demo-%'")
            try execute("DELETE FROM local_checkin_ai_summaries WHERE id LIKE 'demo-%' OR entryId LIKE 'demo-%' OR mediaId LIKE 'demo-%'")
            try execute("DELETE FROM local_post_tags WHERE id LIKE 'demo-%' OR postId LIKE 'demo-%' OR tagId LIKE 'demo-topic-%'")
            try execute("DELETE FROM local_comments WHERE id LIKE 'demo-%' OR postId LIKE 'demo-%'")
            try execute("DELETE FROM local_media WHERE id LIKE 'demo-%' OR postId LIKE 'demo-%'")
            try execute("DELETE FROM local_posts WHERE id LIKE 'demo-%'")
            try execute("DELETE FROM local_tag_aliases WHERE id LIKE 'demo-%' OR tagId LIKE 'demo-topic-%'")
            try execute("DELETE FROM local_tags WHERE id LIKE 'demo-topic-%'")
            try execute("DELETE FROM local_checkin_media WHERE id LIKE 'demo-%' OR entryId LIKE 'demo-%'")
            try execute("DELETE FROM local_checkin_entries WHERE id LIKE 'demo-%' OR itemId LIKE 'demo-%'")
            try execute("DELETE FROM local_checkin_items WHERE id LIKE 'demo-%'")
        }
    }

    private func insertDemoPost(
        _ demo: DemoPost,
        today: Date,
        calendar: Calendar,
        createdAt: Date
    ) throws {
        let occurredAt = demo.date(relativeTo: today, calendar: calendar)
        let post = TimelinePost(
            id: demo.id,
            text: demo.text,
            isFavorite: demo.isFavorite,
            isPinned: demo.isPinned,
            pinnedAt: demo.isPinned ? occurredAt : nil,
            aiTagProcessedAt: demo.summary == nil ? nil : occurredAt,
            tagsUserEditedAt: nil,
            occurredAt: occurredAt,
            localCreatedAt: occurredAt,
            localUpdatedAt: occurredAt,
            localEditedAt: nil,
            serverVersion: nil,
            syncStatus: "synced",
            deletedAt: nil
        )

        try insert(post)

        if let media = try demo.makeMedia(createdAt: occurredAt) {
            try insert(media)

            if let summary = demo.summary {
                try upsertAISummary(summary.summary(postId: demo.id, mediaId: media.id, createdAt: occurredAt))
            }
        }

        for (index, text) in demo.comments.enumerated() {
            let commentDate = calendar.date(byAdding: .minute, value: index + 6, to: occurredAt) ?? occurredAt
            try insert(
                TimelineComment(
                    id: "demo-comment-\(demo.id)-\(index)",
                    postId: demo.id,
                    text: text,
                    createdAt: commentDate,
                    updatedAt: commentDate,
                    serverVersion: nil,
                    deletedAt: nil
                )
            )
        }

        if let tag = try fetchTag(id: demo.primaryTagId) {
            try upsertAssignedTag(
                TimelineAssignedTag(
                    id: "demo-post-tag-\(demo.id)-primary",
                    postId: demo.id,
                    tagId: tag.id,
                    role: "primary",
                    source: "manual",
                    confidence: nil,
                    aiSummaryId: nil,
                    createdAt: createdAt,
                    updatedAt: createdAt,
                    deletedAt: nil,
                    tag: tag
                )
            )
        }

        for tagId in demo.topicTagIds {
            guard let tag = try fetchTag(id: tagId) else {
                continue
            }

            try upsertAssignedTag(
                TimelineAssignedTag(
                    id: "demo-post-tag-\(demo.id)-\(tagId)",
                    postId: demo.id,
                    tagId: tag.id,
                    role: "topic",
                    source: "ai",
                    confidence: 0.86,
                    aiSummaryId: demo.summary == nil ? nil : "demo-summary-\(demo.id)",
                    createdAt: createdAt,
                    updatedAt: createdAt,
                    deletedAt: nil,
                    tag: tag
                )
            )
        }
    }

    private func insertDemoCheckInEntries(
        today: Date,
        calendar: Calendar,
        createdAt: Date,
        language: AppResolvedLanguage = .english
    ) throws {
        let isChinese = language == .simplifiedChinese
        let entries = [
            CheckInEntry(
                id: "demo-checkin-entry-pages-today",
                itemId: "demo-checkin-morning-pages",
                occurredAt: date(dayOffset: 0, hour: 7, minute: 40, relativeTo: today, calendar: calendar),
                note: isChinese ? "打开电脑前先写三页。" : "Three pages before opening the laptop.",
                showInTimeline: true,
                createdAt: createdAt,
                updatedAt: createdAt,
                deletedAt: nil,
                syncStatus: "synced"
            ),
            CheckInEntry(
                id: "demo-checkin-entry-workout-yesterday",
                itemId: "demo-checkin-workout",
                occurredAt: date(dayOffset: -1, hour: 18, minute: 20, relativeTo: today, calendar: calendar),
                note: isChinese ? "轻松跑了 35 分钟。" : "Easy 35 minute run.",
                showInTimeline: true,
                createdAt: createdAt,
                updatedAt: createdAt,
                deletedAt: nil,
                syncStatus: "synced"
            ),
            CheckInEntry(
                id: "demo-checkin-entry-sleep",
                itemId: "demo-checkin-sleep",
                occurredAt: date(dayOffset: -2, hour: 22, minute: 15, relativeTo: today, calendar: calendar),
                note: isChinese ? "睡前把手机放远一点。" : "Phone away before bed.",
                showInTimeline: false,
                createdAt: createdAt,
                updatedAt: createdAt,
                deletedAt: nil,
                syncStatus: "synced"
            ),
        ]

        for entry in entries {
            try upsertCheckInEntryOnly(entry)
        }
    }

    private func date(
        dayOffset: Int,
        hour: Int,
        minute: Int,
        relativeTo today: Date,
        calendar: Calendar
    ) -> Date {
        let day = calendar.date(byAdding: .day, value: dayOffset, to: today) ?? today
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }
}

private struct DemoPost {
    let id: String
    let text: String
    let primaryTagId: String
    let topicTagIds: [String]
    let dayOffset: Int
    let hour: Int
    let minute: Int
    let isFavorite: Bool
    let isPinned: Bool
    let mediaKind: String?
    let mediaTitle: String?
    let imagePalette: DemoImagePalette?
    let comments: [String]
    let summary: DemoSummary?

    func date(relativeTo today: Date, calendar: Calendar) -> Date {
        let day = calendar.date(byAdding: .day, value: dayOffset, to: today) ?? today
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    func makeMedia(createdAt: Date) throws -> TimelineMedia? {
        guard let mediaKind, let mediaTitle else {
            return nil
        }

        let mediaId = "demo-media-\(id)"
        let fileExtension = mediaKind == "audio" ? "m4a" : "png"
        let fileURL = try AppDirectories.mediaDirectory().appending(path: "\(mediaId).\(fileExtension)")

        if mediaKind == "image" {
            let palette = imagePalette ?? DemoImagePalette.default
            try DemoImageRenderer.writePNG(title: mediaTitle, palette: palette, to: fileURL)
        } else {
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                try Data("demo audio placeholder".utf8).write(to: fileURL, options: [.atomic])
            }
        }

        return TimelineMedia(
            id: mediaId,
            postId: id,
            kind: mediaKind,
            localCompressedPath: fileURL.path,
            localOriginalStagingPath: nil,
            localThumbnailPath: nil,
            remoteCompressedPath: nil,
            remoteOriginalPath: nil,
            remoteThumbnailPath: nil,
            originalPreserved: false,
            uploadStatus: "uploaded",
            mimeType: mediaKind == "audio" ? "audio/mp4" : "image/png",
            durationSeconds: mediaKind == "audio" ? 94 : nil,
            transcriptionText: mediaKind == "audio" ? "Demo transcript placeholder for screenshot fixtures." : nil,
            transcriptionStatus: mediaKind == "audio" ? "completed" : "not_requested",
            transcriptionError: nil,
            transcriptionUpdatedAt: mediaKind == "audio" ? createdAt : nil,
            sortOrder: 0,
            checksum: nil,
            createdAt: createdAt,
            updatedAt: createdAt
        )
    }
}

private struct DemoSummary {
    let title: String
    let oneLiner: String
    let bullets: [String]
    var language: String = "en"
    var detailsHeading: String = "Key points"
    var callout: String = "AI suggested tags are shown as topic tags on the moment."

    func summary(postId: String, mediaId: String, createdAt: Date) -> TimelineAISummary {
        TimelineAISummary(
            id: "demo-summary-\(postId)",
            postId: postId,
            mediaId: mediaId,
            status: "ready",
            format: "document-v1",
            language: language,
            overview: oneLiner,
            keyPoints: bullets,
            sections: [],
            summaryText: nil,
            documentTitle: title,
            oneLiner: oneLiner,
            documentBlocks: [
                TimelineAISummaryBlock(kind: "heading", level: 2, text: detailsHeading, items: []),
                TimelineAISummaryBlock(kind: "list", level: 0, text: "", items: bullets),
                TimelineAISummaryBlock(kind: "callout", level: 0, text: callout, items: []),
            ],
            inputTranscriptLength: 248,
            inputDurationSeconds: 94,
            promptVersion: "media-summary-v4",
            provider: nil,
            model: nil,
            errorCode: nil,
            errorMessage: nil,
            createdAt: createdAt,
            updatedAt: createdAt,
            deletedAt: nil
        )
    }
}

private struct DemoCheckInItem {
    let id: String
    let name: String
    let symbolName: String
    let colorHex: String
    let recordMode: CheckInRecordMode
    let timeVisualization: CheckInTimeVisualization
    let defaultShowInTimeline: Bool
    let sortOrder: Int

    func item(createdAt: Date) -> CheckInItem {
        CheckInItem(
            id: id,
            name: name,
            symbolName: symbolName,
            colorHex: colorHex,
            recordMode: recordMode,
            timeVisualization: timeVisualization,
            dayStartHour: 0,
            activeWeekdays: [1, 2, 3, 4, 5, 6, 7],
            sortOrder: sortOrder,
            defaultShowInTimeline: defaultShowInTimeline,
            tagId: nil,
            createdAt: createdAt,
            updatedAt: createdAt,
            archivedAt: nil,
            deletedAt: nil,
            syncStatus: "synced"
        )
    }
}

private struct DemoImagePalette {
    static let `default` = DemoImagePalette(
        top: UIColor(red: 0.80, green: 0.88, blue: 0.93, alpha: 1),
        bottom: UIColor(red: 0.91, green: 0.84, blue: 0.72, alpha: 1),
        accent: UIColor(red: 0.22, green: 0.31, blue: 0.40, alpha: 1)
    )

    let top: UIColor
    let bottom: UIColor
    let accent: UIColor
}

private enum DemoImageRenderer {
    static func writePNG(title: String, palette: DemoImagePalette, to url: URL) throws {
        let size = CGSize(width: 1200, height: 900)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            let rect = CGRect(origin: .zero, size: size)
            let cgContext = context.cgContext
            let colors = [palette.top.cgColor, palette.bottom.cgColor] as CFArray
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0, 1])
            cgContext.drawLinearGradient(
                gradient!,
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: size.width, y: size.height),
                options: []
            )

            palette.accent.withAlphaComponent(0.18).setFill()
            UIBezierPath(roundedRect: rect.insetBy(dx: 120, dy: 120), cornerRadius: 44).fill()

            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 76, weight: .semibold),
                .foregroundColor: palette.accent,
                .paragraphStyle: paragraph,
            ]
            NSString(string: title).draw(
                in: CGRect(x: 120, y: 390, width: size.width - 240, height: 120),
                withAttributes: attributes
            )
        }

        guard let data = image.pngData() else {
            return
        }

        try data.write(to: url, options: [.atomic])
    }
}
