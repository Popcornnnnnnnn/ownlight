import Foundation

enum CloudKitSyncDefaults {
    static let zoneName = "PrivateMomentsV1"
    static let fullReconciliationScope = "cloudkit_full_reconcile_v1"
}

enum CloudKitSyncEntityType: String, CaseIterable, Codable, Equatable {
    case moment
    case media
    case comment
    case tag
    case tagAlias = "tag_alias"
    case postTag = "post_tag"
    case checkInItem = "checkin_item"
    case checkInEntry = "checkin_entry"
    case checkInMedia = "checkin_media"
    case aiSummary = "ai_summary"
    case checkInAISummary = "checkin_ai_summary"
    case weeklyReview = "weekly_review"
    case preference
    case draft

    var recordType: String {
        switch self {
        case .moment:
            return "PMMoment"
        case .media:
            return "PMMedia"
        case .comment:
            return "PMComment"
        case .tag:
            return "PMTag"
        case .tagAlias:
            return "PMTagAlias"
        case .postTag:
            return "PMPostTag"
        case .checkInItem:
            return "PMCheckInItem"
        case .checkInEntry:
            return "PMCheckInEntry"
        case .checkInMedia:
            return "PMCheckInMedia"
        case .aiSummary:
            return "PMAISummary"
        case .checkInAISummary:
            return "PMCheckInAISummary"
        case .weeklyReview:
            return "PMWeeklyReview"
        case .preference:
            return "PMPreference"
        case .draft:
            return "PMDraft"
        }
    }

    func localRecordStateId(entityId: String) -> String {
        "\(rawValue):\(entityId)"
    }

    func recordName(entityId: String) -> String {
        "pm.\(rawValue).\(Self.recordNameComponent(entityId))"
    }

    private static func recordNameComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        let scalars = value.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "_"
        }
        let sanitized = String(scalars)
        return sanitized.isEmpty ? "empty" : sanitized
    }
}

struct CloudKitPreferenceSnapshot: Equatable {
    static let recordId = "app"
    static let schemaVersion = 1

    var showTagsInTimeline: Bool
    var showCheckInSummaries: Bool
    var memoryLinksEnabled: Bool
    var aiTitleAutoInsertEnabled: Bool
    var appAppearanceMode: AppAppearanceMode
    var appLanguageMode: AppLanguageMode
    var aiLanguageMode: AILanguageMode
    var aiAnalysisEnabled: Bool
    var aiExternalProcessingConsentAccepted: Bool
    var useTextProviderForTranscription: Bool
    var transcriptionProviderMode: TranscriptionProviderMode
    var preferredSpeechTranscriptionLocaleIdentifier: String?
    var autoWeeklyReviewEnabled: Bool
    var publishWeeklyReviewToMoments: Bool
    var markdownMathRenderingEnabled: Bool
    var markdownRemoteImagesEnabled: Bool
    var markdownRawHTMLRenderingEnabled: Bool

    static func current() -> Self {
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
            useTextProviderForTranscription: AppSettings.useTextProviderForTranscription,
            transcriptionProviderMode: AppSettings.transcriptionProviderMode,
            preferredSpeechTranscriptionLocaleIdentifier: AppSettings.preferredSpeechTranscriptionLocaleIdentifier,
            autoWeeklyReviewEnabled: AppSettings.autoWeeklyReviewEnabled,
            publishWeeklyReviewToMoments: AppSettings.publishWeeklyReviewToMoments,
            markdownMathRenderingEnabled: AppSettings.markdownMathRenderingEnabled,
            markdownRemoteImagesEnabled: AppSettings.markdownRemoteImagesEnabled,
            markdownRawHTMLRenderingEnabled: AppSettings.markdownRawHTMLRenderingEnabled
        )
    }
}

struct CloudKitDraftSnapshot: Equatable {
    enum Kind: String, Equatable {
        case composer
        case editMoment = "edit_moment"
    }

    static let schemaVersion = 1
    static let composerRecordId = "composer"

    var kind: Kind
    var entityId: String
    var postId: String?
    var text: String
    var occurredAt: Date
    var updatedAt: Date
    var existingMediaIds: [String]
    var hasUnsupportedMediaDrafts: Bool

    static func editRecordId(postId: String) -> String {
        "edit:\(postId)"
    }

    static func editPostId(from entityId: String) -> String? {
        for prefix in ["edit:", "edit_"] where entityId.hasPrefix(prefix) {
            return String(entityId.dropFirst(prefix.count))
        }
        return nil
    }

    static func matchesEditRecordId(_ entityId: String, postId: String) -> Bool {
        entityId == editRecordId(postId: postId) || entityId == "edit_\(postId)"
    }

    static func currentComposer() -> Self? {
        guard ComposerDraftStore.hasTextOrDateDraft() else {
            return nil
        }

        let occurredAt = ComposerDraftStore.loadOccurredAt()
        return Self(
            kind: .composer,
            entityId: composerRecordId,
            postId: nil,
            text: ComposerDraftStore.loadText(),
            occurredAt: occurredAt,
            updatedAt: ComposerDraftStore.loadUpdatedAt() ?? occurredAt,
            existingMediaIds: [],
            hasUnsupportedMediaDrafts: false
        )
    }

    static func currentEdit(postId: String) -> Self? {
        guard let metadata = EditDraftStore.loadMetadata(postId: postId) else {
            return nil
        }

        return Self(
            kind: .editMoment,
            entityId: editRecordId(postId: postId),
            postId: postId,
            text: metadata.text,
            occurredAt: metadata.occurredAt,
            updatedAt: metadata.updatedAt,
            existingMediaIds: metadata.existingMediaIds,
            hasUnsupportedMediaDrafts: metadata.hasNewMediaDrafts
        )
    }
}

struct CloudKitRecordState: Equatable {
    var id: String
    var entityType: CloudKitSyncEntityType
    var entityId: String
    var recordType: String
    var recordName: String
    var zoneName: String
    var recordChangeTag: String?
    var lastKnownRecordJson: String?
    var localContentHash: String?
    var cloudDeletedAt: Date?
    var lastMappedAt: Date
    var lastUploadedAt: Date?
    var lastDownloadedAt: Date?

    init(
        entityType: CloudKitSyncEntityType,
        entityId: String,
        recordChangeTag: String? = nil,
        lastKnownRecordJson: String? = nil,
        localContentHash: String? = nil,
        cloudDeletedAt: Date? = nil,
        lastMappedAt: Date,
        lastUploadedAt: Date? = nil,
        lastDownloadedAt: Date? = nil,
        zoneName: String = CloudKitSyncDefaults.zoneName
    ) {
        self.id = entityType.localRecordStateId(entityId: entityId)
        self.entityType = entityType
        self.entityId = entityId
        self.recordType = entityType.recordType
        self.recordName = entityType.recordName(entityId: entityId)
        self.zoneName = zoneName
        self.recordChangeTag = recordChangeTag
        self.lastKnownRecordJson = lastKnownRecordJson
        self.localContentHash = localContentHash
        self.cloudDeletedAt = cloudDeletedAt
        self.lastMappedAt = lastMappedAt
        self.lastUploadedAt = lastUploadedAt
        self.lastDownloadedAt = lastDownloadedAt
    }
}

enum CloudKitPendingChangeKind: String, Codable, Equatable {
    case upsert
    case delete
    case assetUpload = "asset_upload"
}

enum CloudKitPendingChangeStatus: String, Codable, Equatable {
    case pending
    case running
    case failed
    case finished
}

struct CloudKitPendingChange: Equatable {
    var id: String
    var entityType: CloudKitSyncEntityType
    var entityId: String
    var recordStateId: String?
    var changeKind: CloudKitPendingChangeKind
    var reason: String?
    var status: CloudKitPendingChangeStatus
    var attemptCount: Int
    var lastErrorCode: String?
    var lastErrorMessage: String?
    var createdAt: Date
    var updatedAt: Date
    var nextAttemptAt: Date?
    var finishedAt: Date?
}

struct CloudKitSyncState: Equatable {
    var scope: String
    var serverChangeTokenData: Data?
    var lastAccountStatus: String?
    var lastSyncStartedAt: Date?
    var lastSyncFinishedAt: Date?
    var lastErrorCode: String?
    var lastErrorMessage: String? = nil
    var updatedAt: Date
}
