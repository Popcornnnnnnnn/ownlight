import Foundation

enum CheckInRecordMode: String, CaseIterable, Codable, Identifiable {
    case oncePerDay
    case multiplePerDay

    var id: String {
        rawValue
    }

    func title(language: AppResolvedLanguage = .english) -> String {
        switch self {
        case .oncePerDay:
            return L10n.t("Once per day", language)
        case .multiplePerDay:
            return L10n.t("Multiple per day", language)
        }
    }

    var systemImage: String {
        switch self {
        case .oncePerDay:
            return "checkmark.circle"
        case .multiplePerDay:
            return "plus.circle"
        }
    }
}

enum CheckInTimeVisualization: String, CaseIterable, Codable, Identifiable {
    case none
    case timeLine
    case timeHeatmap

    var id: String {
        rawValue
    }

    func title(language: AppResolvedLanguage = .english) -> String {
        switch self {
        case .none:
            return L10n.t("None", language)
        case .timeLine:
            return L10n.t("Time Line", language)
        case .timeHeatmap:
            return L10n.t("Time Heatmap", language)
        }
    }

    var systemImage: String {
        switch self {
        case .none:
            return "minus.circle"
        case .timeLine:
            return "chart.xyaxis.line"
        case .timeHeatmap:
            return "square.grid.3x3"
        }
    }
}

struct CheckInItem: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var symbolName: String
    var colorHex: String
    var recordMode: CheckInRecordMode
    var timeVisualization: CheckInTimeVisualization
    var dayStartHour: Int
    var activeWeekdays: [Int]
    var sortOrder: Int
    var defaultShowInTimeline: Bool
    var tagId: String?
    var createdAt: Date
    var updatedAt: Date
    var archivedAt: Date?
    var deletedAt: Date?
    var syncStatus: String

    var isArchived: Bool {
        archivedAt != nil
    }

    func isScheduled(on date: Date, calendar: Calendar = .current) -> Bool {
        let itemDayStart = CheckInDayBoundary.dayStart(
            containing: date,
            dayStartHour: dayStartHour,
            calendar: calendar
        )
        return activeWeekdays.contains(calendar.component(.weekday, from: itemDayStart))
    }
}

struct CheckInEntry: Identifiable, Codable, Equatable {
    var id: String
    var itemId: String
    var occurredAt: Date
    var note: String
    var showInTimeline: Bool
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var syncStatus: String

    var hasNote: Bool {
        !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct CheckInMedia: Identifiable, Codable, Equatable {
    var id: String
    var entryId: String
    var kind: String
    var localCompressedPath: String
    var remoteCompressedPath: String?
    var uploadStatus: String
    var uploadError: String?
    var mimeType: String?
    var durationSeconds: Double?
    var transcriptionText: String? = nil
    var transcriptionStatus: String = "not_requested"
    var transcriptionError: String? = nil
    var transcriptionUpdatedAt: Date? = nil
    var sortOrder: Int
    var checksum: String?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    var isImage: Bool {
        kind == "image"
    }

    var isAudio: Bool {
        kind == "audio"
    }

    var isVideo: Bool {
        kind == "video"
    }

    var hasLocalDisplayFile: Bool {
        !localCompressedPath.isEmpty && FileManager.default.fileExists(atPath: localCompressedPath)
    }

    var hasLocalPlayableFile: Bool {
        hasLocalDisplayFile
    }

    var preferredFileExtension: String {
        if isAudio {
            return "m4a"
        }

        if isVideo {
            return "mp4"
        }

        return "jpg"
    }
}

struct CheckInAISummary: Identifiable, Codable, Equatable {
    var id: String
    var entryId: String
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

struct CheckInFeedEntry: Identifiable {
    let entry: CheckInEntry
    let item: CheckInItem
    let tag: TimelineTag?
    let media: [CheckInMedia]

    var id: String {
        entry.id
    }

    var occurredAt: Date {
        entry.occurredAt
    }

    var syncStatus: String {
        if entry.syncStatus != "synced" {
            return entry.syncStatus
        }

        if item.syncStatus != "synced" {
            return item.syncStatus
        }

        if media.contains(where: { $0.uploadStatus == "failed" }) {
            return "failed"
        }

        if media.contains(where: { $0.uploadStatus == "pending" }) {
            return "partial"
        }

        return "synced"
    }

    var isDeleted: Bool {
        entry.deletedAt != nil || item.deletedAt != nil
    }
}

enum MomentFeedItem: Identifiable {
    case moment(TimelineItem)
    case checkIn(CheckInFeedEntry)

    var id: String {
        switch self {
        case .moment(let item):
            return "moment-\(item.id)"
        case .checkIn(let checkIn):
            return "checkin-\(checkIn.id)"
        }
    }

    var rawItemID: String {
        switch self {
        case .moment(let item):
            return item.id
        case .checkIn(let checkIn):
            return checkIn.id
        }
    }

    var occurredAt: Date {
        switch self {
        case .moment(let item):
            return item.post.occurredAt
        case .checkIn(let checkIn):
            return checkIn.occurredAt
        }
    }

    var isMoment: Bool {
        if case .moment = self {
            return true
        }

        return false
    }

    var isCheckIn: Bool {
        if case .checkIn = self {
            return true
        }

        return false
    }

    var moment: TimelineItem? {
        if case .moment(let item) = self {
            return item
        }

        return nil
    }

    var checkIn: CheckInFeedEntry? {
        if case .checkIn(let item) = self {
            return item
        }

        return nil
    }

    var media: [TimelineMedia] {
        moment?.media ?? []
    }

    var comments: [TimelineComment] {
        moment?.comments ?? []
    }

    var primaryTagId: String? {
        switch self {
        case .moment(let item):
            return item.primaryTag?.tagId
        case .checkIn(let item):
            return item.tag?.id
        }
    }

    var topicTagIds: Set<String> {
        Set(moment?.topicTags.map(\.tagId) ?? [])
    }

    var syncStatus: String {
        switch self {
        case .moment(let item):
            return item.post.syncStatus
        case .checkIn(let item):
            return item.syncStatus
        }
    }

    var sortKey: String {
        switch self {
        case .moment(let item):
            return item.id
        case .checkIn(let item):
            return item.id
        }
    }
}
