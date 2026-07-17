import Foundation

struct TimelinePost: Identifiable, Codable {
    var id: String
    var text: String
    var isFavorite: Bool
    var isPinned: Bool
    var pinnedAt: Date?
    var aiTagProcessedAt: Date?
    var tagsUserEditedAt: Date?
    var occurredAt: Date
    var localCreatedAt: Date
    var localUpdatedAt: Date
    var localEditedAt: Date?
    var serverVersion: Int?
    var syncStatus: String
    var deletedAt: Date?
}

struct TimelineTag: Identifiable, Codable, Equatable {
    private static let defaultPrimaryTagIds: Set<String> = [
        "tag-primary-diary",
        "tag-primary-idea",
        "tag-primary-learning",
        "tag-primary-emotion",
        "tag-primary-casual",
        "tag-primary-review",
    ]

    var id: String
    var type: String
    var name: String
    var normalizedName: String
    var colorHex: String?
    var isDefault: Bool
    var isArchived: Bool
    var aiUsableAsPrimary: Bool
    var createdAt: Date
    var updatedAt: Date
    var archivedAt: Date?
    var areaId: String? = nil

    var isPrimary: Bool {
        type == "primary"
    }

    var isTopic: Bool {
        type == "topic"
    }

    var isDefaultPrimaryTag: Bool {
        isPrimary && (isDefault || Self.defaultPrimaryTagIds.contains(id))
    }

    var resolvedArea: TopicTagArea {
        guard isTopic else {
            return .life
        }

        return TopicTagArea.fromProviderValue(areaId, topicName: name)
    }
}

enum TopicTagArea: String, Codable, CaseIterable, Equatable, Identifiable {
    case technology = "technology"
    case productDesign = "product_design"
    case learningKnowledge = "learning_knowledge"
    case work = "work"
    case life = "life"
    case healthFitness = "health_fitness"
    case emotionRelationships = "emotion_relationships"

    var id: String {
        rawValue
    }

    static var displayAreas: [TopicTagArea] {
        [
            .technology,
            .productDesign,
            .learningKnowledge,
            .work,
            .life,
            .healthFitness,
            .emotionRelationships
        ]
    }

    static func isFixedAreaId(_ value: String?) -> Bool {
        guard let value else {
            return false
        }

        return displayAreas.contains { $0.rawValue == value }
    }

    var title: String {
        switch self {
        case .technology:
            return "Technology"
        case .productDesign:
            return "Product & Design"
        case .learningKnowledge:
            return "Learning & Knowledge"
        case .work:
            return "Work"
        case .life:
            return "Life"
        case .healthFitness:
            return "Health & Fitness"
        case .emotionRelationships:
            return "Emotions & Relationships"
        }
    }

    var chineseTitle: String {
        switch self {
        case .technology:
            return "技术"
        case .productDesign:
            return "产品与设计"
        case .learningKnowledge:
            return "学习与知识"
        case .work:
            return "工作事务"
        case .life:
            return "生活记录"
        case .healthFitness:
            return "健康与运动"
        case .emotionRelationships:
            return "情绪与关系"
        }
    }

    var symbolName: String {
        switch self {
        case .technology:
            return "terminal"
        case .productDesign:
            return "square.grid.2x2"
        case .learningKnowledge:
            return "book"
        case .work:
            return "briefcase"
        case .life:
            return "house"
        case .healthFitness:
            return "figure.run"
        case .emotionRelationships:
            return "heart"
        }
    }

    func localizedTitle(language: AppResolvedLanguage) -> String {
        language == .simplifiedChinese ? chineseTitle : title
    }

    static func fromProviderValue(_ value: String?, topicName: String? = nil) -> TopicTagArea {
        guard let value else {
            return inferredArea(forTopicName: topicName)
        }

        let normalized = normalizeAreaInput(value)
        switch normalized {
        case "technology", "tech", "coding", "development", "software", "技术", "编程", "开发", "软件":
            return .technology
        case "productdesign", "product", "design", "product_design", "产品", "设计", "产品与设计", "产品设计":
            return .productDesign
        case "learningknowledge", "learning", "knowledge", "study", "research", "学习", "知识", "学习与知识", "读书", "研究":
            return .learningKnowledge
        case "work", "business", "office", "工作", "工作事务", "事务", "项目":
            return .work
        case "life", "daily", "personal", "生活", "生活记录", "日常", "个人":
            return .life
        case "healthfitness", "health", "fitness", "exercise", "sport", "健康", "运动", "健康与运动", "健身":
            return .healthFitness
        case "emotionrelationships", "emotion", "relationship", "relationships", "mood", "情绪", "关系", "情绪与关系", "亲密关系":
            return .emotionRelationships
        case "uncategorized", "unknown", "other", "未分类", "其他":
            return inferredArea(forTopicName: topicName)
        default:
            return inferredArea(forTopicName: topicName)
        }
    }

    static func inferredArea(forTopicName value: String?) -> TopicTagArea {
        guard let value else {
            return .life
        }

        let normalized = normalizeAreaInput(value)
        guard !normalized.isEmpty else {
            return .life
        }

        if containsAny(normalized, [
            "ai", "llm", "gpt", "claude", "codex", "mcp", "api", "http", "https", "dns", "ssh",
            "ios", "swift", "swiftui", "python", "typescript", "javascript", "sqlite", "database",
            "server", "cloudflare", "tailscale", "github", "git", "docker", "代码", "编程", "开发",
            "软件", "服务器", "数据库", "接口", "网络", "安全", "证书", "中间人", "模型", "大模型", "技术"
        ]) {
            return .technology
        }

        if containsAny(normalized, [
            "product", "design", "ui", "ux", "figma", "feature", "roadmap", "filter", "topic", "tag",
            "app设计", "产品", "设计", "界面", "交互", "功能", "路线图", "筛选", "标签", "体验"
        ]) {
            return .productDesign
        }

        if containsAny(normalized, [
            "learning", "study", "knowledge", "research", "paper", "thesis", "book", "course", "reading",
            "学习", "知识", "论文", "研究", "读书", "课程", "笔记", "整理"
        ]) {
            return .learningKnowledge
        }

        if containsAny(normalized, [
            "work", "office", "business", "meeting", "client", "deadline", "job", "工作", "会议", "客户",
            "岗位", "面试", "任务", "同事"
        ]) {
            return .work
        }

        if containsAny(normalized, [
            "health", "fitness", "exercise", "sport", "run", "sleep", "medicine", "rehab", "gym",
            "健康", "运动", "跑步", "健身", "睡眠", "康复", "训练", "饮食", "药"
        ]) {
            return .healthFitness
        }

        if containsAny(normalized, [
            "emotion", "relationship", "mood", "family", "friend", "love", "stress", "anxiety",
            "情绪", "关系", "心情", "家人", "朋友", "压力", "焦虑", "亲密"
        ]) {
            return .emotionRelationships
        }

        return .life
    }

    private static func normalizeAreaInput(_ value: String) -> String {
        value
            .precomposedStringWithCompatibilityMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "[\\s\\p{P}\\p{S}_]+", with: "", options: .regularExpression)
    }

    private static func containsAny(_ value: String, _ needles: [String]) -> Bool {
        needles.contains { value.contains(normalizeAreaInput($0)) }
    }
}

enum TimelineTopicMatchMode: String, Codable, Equatable {
    case any
    case all
}

struct TimelineTagAlias: Identifiable, Codable, Equatable {
    var id: String
    var tagId: String
    var alias: String
    var normalizedAlias: String
    var createdAt: Date
    var deletedAt: Date?
}

struct TimelineAssignedTag: Identifiable, Codable, Equatable {
    var id: String
    var postId: String
    var tagId: String
    var role: String
    var source: String
    var confidence: Double?
    var aiSummaryId: String?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var tag: TimelineTag
}

struct TimelineMedia: Identifiable, Codable {
    var id: String
    var postId: String
    var kind: String
    var localCompressedPath: String
    var localOriginalStagingPath: String?
    var localThumbnailPath: String?
    var remoteCompressedPath: String?
    var remoteOriginalPath: String?
    var remoteThumbnailPath: String?
    var originalPreserved: Bool
    var uploadStatus: String
    var mimeType: String?
    var durationSeconds: Double?
    var transcriptionText: String?
    var transcriptionStatus: String
    var transcriptionError: String?
    var transcriptionUpdatedAt: Date?
    var sortOrder: Int
    var checksum: String?
    var createdAt: Date
    var updatedAt: Date
}

extension TimelineMedia {
    var isImage: Bool {
        kind == "image"
    }

    var isVideo: Bool {
        kind == "video"
    }

    var isAudio: Bool {
        kind == "audio"
    }

    var isDocument: Bool {
        kind == "document"
    }

    var localDisplayImagePath: String {
        if isVideo, let localThumbnailPath, !localThumbnailPath.isEmpty {
            return localThumbnailPath
        }

        return localCompressedPath
    }

    var hasLocalPlayableFile: Bool {
        !localCompressedPath.isEmpty && FileManager.default.fileExists(atPath: localCompressedPath)
    }
}

struct TimelineComment: Identifiable, Codable, Equatable {
    var id: String
    var postId: String
    var text: String
    var createdAt: Date
    var updatedAt: Date
    var serverVersion: Int?
    var deletedAt: Date?
}

struct TimelineAISummarySection: Codable, Equatable {
    var heading: String
    var bullets: [String]
}

struct TimelineAISummaryBlock: Codable, Equatable {
    var kind: String
    var level: Int
    var text: String
    var items: [String]
}

struct AITokenUsage: Codable, Equatable {
    var inputTokens: Int?
    var outputTokens: Int?
    var totalTokens: Int?

    var hasValues: Bool {
        inputTokens != nil || outputTokens != nil || totalTokens != nil
    }

    var resolvedTotalTokens: Int? {
        if let totalTokens {
            return totalTokens
        }

        let input = inputTokens ?? 0
        let output = outputTokens ?? 0
        let total = input + output
        return total > 0 ? total : nil
    }
}

struct TimelineAISummary: Identifiable, Codable, Equatable {
    var id: String
    var postId: String
    var mediaId: String
    var status: String
    var format: String?
    var language: String?
    var overview: String?
    var keyPoints: [String]
    var sections: [TimelineAISummarySection]
    var summaryText: String?
    var documentTitle: String? = nil
    var oneLiner: String? = nil
    var documentBlocks: [TimelineAISummaryBlock] = []
    var inputTranscriptLength: Int?
    var inputDurationSeconds: Double?
    var inputTokenCount: Int? = nil
    var outputTokenCount: Int? = nil
    var totalTokenCount: Int? = nil
    var promptVersion: String
    var provider: String?
    var model: String?
    var errorCode: String?
    var errorMessage: String?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    var isReady: Bool {
        status == "ready" && deletedAt == nil
    }

    var isSummarizing: Bool {
        (status == "transcribing" || status == "summarizing") && deletedAt == nil
    }

    var isFailed: Bool {
        status == "failed" && deletedAt == nil
    }

    var hasDisplayContent: Bool {
        guard deletedAt == nil else {
            return false
        }

        return Self.hasText(overview)
            || Self.hasText(summaryText)
            || Self.hasText(documentTitle)
            || Self.hasText(oneLiner)
            || !keyPoints.isEmpty
            || !sections.isEmpty
            || !documentBlocks.isEmpty
    }

    private static func hasText(_ value: String?) -> Bool {
        guard let value else {
            return false
        }

        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct TimelineItem: Identifiable {
    let post: TimelinePost
    let media: [TimelineMedia]
    let comments: [TimelineComment]
    let aiSummaries: [TimelineAISummary]
    let tags: [TimelineAssignedTag]

    var id: String {
        post.id
    }

    var primaryTag: TimelineAssignedTag? {
        tags.first { $0.role == "primary" && $0.deletedAt == nil && !$0.tag.isArchived }
    }

    var topicTags: [TimelineAssignedTag] {
        tags.filter { $0.role == "topic" && $0.deletedAt == nil && !$0.tag.isArchived }
    }
}

enum TimelineTagFilter {
    static func matches(
        _ item: MomentFeedItem,
        selectedArea: TopicTagArea?,
        selectedTopicTagIds: Set<String>,
        topicMatchMode: TimelineTopicMatchMode
    ) -> Bool {
        guard let moment = item.moment else {
            return selectedArea == nil && selectedTopicTagIds.isEmpty
        }

        return matches(
            moment,
            selectedArea: selectedArea,
            selectedTopicTagIds: selectedTopicTagIds,
            topicMatchMode: topicMatchMode
        )
    }

    static func matches(
        _ item: TimelineItem,
        selectedArea: TopicTagArea?,
        selectedTopicTagIds: Set<String>,
        topicMatchMode: TimelineTopicMatchMode
    ) -> Bool {
        let activeTopicTags = item.topicTags

        if let selectedArea,
           !activeTopicTags.contains(where: { $0.tag.resolvedArea == selectedArea }) {
            return false
        }

        guard !selectedTopicTagIds.isEmpty else {
            return true
        }

        let itemTopicIds = Set(activeTopicTags.map(\.tagId))
        switch topicMatchMode {
        case .any:
            return !selectedTopicTagIds.isDisjoint(with: itemTopicIds)
        case .all:
            return selectedTopicTagIds.isSubset(of: itemTopicIds)
        }
    }
}

enum MemoryLinkSourceWindow: String, Codable, CaseIterable, Equatable {
    case oneYear
    case sixMonths
    case threeMonths
    case oneMonth

    var title: String {
        switch self {
        case .oneYear:
            return "1 year ago today"
        case .sixMonths:
            return "6 months ago today"
        case .threeMonths:
            return "3 months ago today"
        case .oneMonth:
            return "1 month ago today"
        }
    }

    func targetDate(for today: Date, calendar: Calendar) -> Date? {
        switch self {
        case .oneYear:
            return calendar.date(byAdding: .year, value: -1, to: today)
        case .sixMonths:
            return calendar.date(byAdding: .month, value: -6, to: today)
        case .threeMonths:
            return calendar.date(byAdding: .month, value: -3, to: today)
        case .oneMonth:
            return calendar.date(byAdding: .month, value: -1, to: today)
        }
    }
}

struct MemoryLink: Identifiable, Equatable {
    let id: String
    let postId: String
    let title: String
    let subtitle: String
    let sourceWindow: MemoryLinkSourceWindow
    let score: Int
    let shownDate: Date
}

struct MemoryLinkHistoryEntry: Identifiable, Codable, Equatable {
    let id: String
    let postId: String
    let shownDate: Date
    let sourceWindow: MemoryLinkSourceWindow
    let score: Int
    let shownAt: Date
    let openedAt: Date?
    let dismissedAt: Date?
}

enum MemoryLinkSelector {
    private static let minimumScore = 50
    private static let sourceDayTolerance = 3
    private static let minimumAgeInDays = 30
    private static let weeklyDisplayLimit = 2
    private static let rollingWeekLengthInDays = 7
    private static let minimumDisplayGapInDays = 2
    private static let samePostCooldownInDays = 180
    private static let unopenedCooldownInDays = 7

    static func select(
        from items: [TimelineItem],
        history: [MemoryLinkHistoryEntry],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> MemoryLink? {
        let today = calendar.startOfDay(for: now)
        let visibleItems = items.filter { $0.post.deletedAt == nil }

        if let existingToday = history
            .sorted(by: { $0.shownAt > $1.shownAt })
            .first(where: { calendar.isDate($0.shownDate, inSameDayAs: today) }),
           let item = visibleItems.first(where: { $0.id == existingToday.postId }) {
            return makeLink(
                for: item,
                sourceWindow: existingToday.sourceWindow,
                score: max(existingToday.score, score(for: item)),
                shownDate: today,
                calendar: calendar
            )
        }

        let priorHistory = history
            .filter { !calendar.isDate($0.shownDate, inSameDayAs: today) && $0.shownDate < today }
            .sorted { $0.shownDate > $1.shownDate }

        guard passesFrequencyRules(priorHistory: priorHistory, today: today, calendar: calendar) else {
            return nil
        }

        let samePostCooldownStart = calendar.date(
            byAdding: .day,
            value: -samePostCooldownInDays,
            to: today
        ) ?? today
        let recentlyShownPostIds = Set(
            priorHistory
                .filter { $0.shownDate >= samePostCooldownStart }
                .map(\.postId)
        )

        let memoryCandidates = visibleItems.flatMap { item in
            candidates(
                for: item,
                today: today,
                calendar: calendar,
                recentlyShownPostIds: recentlyShownPostIds
            )
        }

        return memoryCandidates
            .sorted { lhs, rhs in
                if lhs.link.score != rhs.link.score {
                    return lhs.link.score > rhs.link.score
                }

                if lhs.sourceDistance != rhs.sourceDistance {
                    return lhs.sourceDistance < rhs.sourceDistance
                }

                return lhs.occurredAt > rhs.occurredAt
            }
            .first?
            .link
    }

    private static func passesFrequencyRules(
        priorHistory: [MemoryLinkHistoryEntry],
        today: Date,
        calendar: Calendar
    ) -> Bool {
        let rollingWeekStart = calendar.date(
            byAdding: .day,
            value: -(rollingWeekLengthInDays - 1),
            to: today
        ) ?? today
        let recentDisplayCount = priorHistory.filter { $0.shownDate >= rollingWeekStart }.count
        guard recentDisplayCount < weeklyDisplayLimit else {
            return false
        }

        if let latest = priorHistory.first,
           daysBetween(latest.shownDate, today, calendar: calendar) < minimumDisplayGapInDays {
            return false
        }

        let latestThree = Array(priorHistory.prefix(3))
        if latestThree.count == 3,
           latestThree.allSatisfy({ $0.openedAt == nil }),
           let latest = latestThree.first,
           daysBetween(latest.shownDate, today, calendar: calendar) < unopenedCooldownInDays {
            return false
        }

        return true
    }

    private static func candidates(
        for item: TimelineItem,
        today: Date,
        calendar: Calendar,
        recentlyShownPostIds: Set<String>
    ) -> [MemoryLinkCandidate] {
        guard !recentlyShownPostIds.contains(item.id) else {
            return []
        }

        let occurredDay = calendar.startOfDay(for: item.post.occurredAt)
        guard daysBetween(occurredDay, today, calendar: calendar) >= minimumAgeInDays else {
            return []
        }

        let score = score(for: item)
        guard score >= minimumScore else {
            return []
        }

        return MemoryLinkSourceWindow.allCases.compactMap { window in
            guard let targetDay = window.targetDate(for: today, calendar: calendar).map({ calendar.startOfDay(for: $0) }) else {
                return nil
            }

            let sourceDistance = abs(daysBetween(targetDay, occurredDay, calendar: calendar))
            guard sourceDistance <= sourceDayTolerance else {
                return nil
            }

            return MemoryLinkCandidate(
                link: makeLink(
                    for: item,
                    sourceWindow: window,
                    score: score,
                    shownDate: today,
                    calendar: calendar
                ),
                sourceDistance: sourceDistance,
                occurredAt: item.post.occurredAt
            )
        }
    }

    private static func makeLink(
        for item: TimelineItem,
        sourceWindow: MemoryLinkSourceWindow,
        score: Int,
        shownDate: Date,
        calendar: Calendar
    ) -> MemoryLink {
        MemoryLink(
            id: "\(sourceWindow.rawValue)-\(item.id)-\(Int(shownDate.timeIntervalSince1970))",
            postId: item.id,
            title: sourceWindow.title,
            subtitle: subtitle(for: item),
            sourceWindow: sourceWindow,
            score: score,
            shownDate: calendar.startOfDay(for: shownDate)
        )
    }

    private static func score(for item: TimelineItem) -> Int {
        let text = item.post.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let readySummaries = item.aiSummaries.filter { $0.isReady && $0.hasDisplayContent }
        var value = 0

        if firstMarkdownHeading(in: text) != nil {
            value += 20
        }

        if text.count >= 200 {
            value += 30
        } else if text.count >= 80 {
            value += 15
        }

        if item.post.isFavorite {
            value += 15
        }

        if item.post.isPinned {
            value += 15
        }

        if !item.comments.filter({ $0.deletedAt == nil }).isEmpty {
            value += 12
        }

        if !item.topicTags.isEmpty {
            value += 8
        }

        if item.primaryTag != nil {
            value += 5
        }

        if !item.media.isEmpty {
            value += 8
        }

        if item.media.contains(where: { $0.isAudio || $0.isVideo }) {
            value += 12
        }

        if !readySummaries.isEmpty {
            value += 40
        }

        return value
    }

    private static func subtitle(for item: TimelineItem) -> String {
        let text = item.post.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let heading = firstMarkdownHeading(in: text) {
            return heading
        }

        let readySummaries = item.aiSummaries.filter { $0.isReady && $0.hasDisplayContent }
        for summary in readySummaries {
            if let title = compactSubtitle(summary.documentTitle) {
                return title
            }

            if let oneLiner = compactSubtitle(summary.oneLiner) {
                return oneLiner
            }

            if let overview = compactSubtitle(summary.overview) {
                return overview
            }
        }

        if let firstLine = text
            .components(separatedBy: .newlines)
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { !$0.isEmpty }) {
            return compactSubtitle(firstLine) ?? "Memory"
        }

        return "Memory"
    }

    private static func firstMarkdownHeading(in text: String) -> String? {
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let title: String?
            if trimmed.hasPrefix("## ") {
                title = String(trimmed.dropFirst(3))
            } else if trimmed.hasPrefix("# ") {
                title = String(trimmed.dropFirst(2))
            } else {
                title = nil
            }

            if let compact = compactSubtitle(title) {
                return compact
            }
        }

        return nil
    }

    private static func compactSubtitle(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let collapsed = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        guard !collapsed.isEmpty else {
            return nil
        }

        if collapsed.count <= 72 {
            return collapsed
        }

        return String(collapsed.prefix(69)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    private static func daysBetween(_ start: Date, _ end: Date, calendar: Calendar) -> Int {
        calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: start),
            to: calendar.startOfDay(for: end)
        ).day ?? 0
    }
}

private struct MemoryLinkCandidate {
    let link: MemoryLink
    let sourceDistance: Int
    let occurredAt: Date
}
