import Foundation

struct CloudKitLocalRecordApplier: CloudKitIncomingRecordApplying {
    private let database: LocalDatabase

    init(database: LocalDatabase) {
        self.database = database
    }

    func applyUpsert(_ payload: CloudKitRecordPayload, downloadedAt: Date) throws {
        switch payload.entityType {
        case .moment:
            try database.upsertCloudKitRemotePost(Self.post(from: payload))
        case .media:
            try database.upsertCloudKitRemoteMedia(Self.media(from: payload, database: database))
        case .comment:
            try database.upsertCloudKitRemoteComment(Self.comment(from: payload, database: database))
        case .tag:
            try database.upsertTag(Self.tag(from: payload))
        case .tagAlias:
            let alias = try Self.tagAlias(from: payload)
            guard try database.fetchTag(id: alias.tagId) != nil else {
                throw CloudKitLocalRecordApplyError.missingParent("tag:\(alias.tagId)")
            }
            try database.upsertTagAlias(alias)
        case .postTag:
            let assignedTag = try Self.assignedTag(from: payload, database: database)
            try database.upsertAssignedTag(assignedTag)
        case .checkInItem:
            try database.upsertCloudKitRemoteCheckInItem(Self.checkInItem(from: payload))
        case .checkInEntry:
            try database.upsertCloudKitRemoteCheckInEntry(Self.checkInEntry(from: payload, database: database))
        case .checkInMedia:
            try database.upsertCloudKitRemoteCheckInMedia(Self.checkInMedia(from: payload, database: database))
        case .aiSummary:
            try database.upsertCloudKitRemoteAISummary(Self.timelineAISummary(from: payload, database: database))
        case .checkInAISummary:
            try database.upsertCloudKitRemoteCheckInAISummary(Self.checkInAISummary(from: payload, database: database))
        case .weeklyReview:
            Self.upsertWeeklyReview(try Self.weeklyReview(from: payload))
        case .preference:
            Self.applyPreference(try Self.preference(from: payload))
        case .draft:
            try Self.applyDraft(try Self.draft(from: payload))
        }
    }

    func applyAssets(_ assetRecord: CloudKitDownloadedAssetRecord, downloadedAt: Date) throws {
        switch assetRecord.payload.entityType {
        case .media:
            let assets = try Self.materializedMediaAssets(from: assetRecord)
            try database.updateCloudKitRemoteMediaAssetPaths(
                mediaId: assetRecord.payload.entityId,
                compressedPath: assets.compressedPath,
                thumbnailPath: assets.thumbnailPath,
                originalPath: assets.originalPath,
                downloadedAt: downloadedAt
            )
        case .checkInMedia:
            let assets = try Self.materializedMediaAssets(from: assetRecord)
            if let compressedPath = assets.compressedPath {
                try database.updateCloudKitRemoteCheckInMediaAssetPath(
                    mediaId: assetRecord.payload.entityId,
                    localPath: compressedPath,
                    downloadedAt: downloadedAt
                )
            }
        default:
            return
        }
    }

    func applyDelete(
        entityType: CloudKitSyncEntityType,
        entityId: String,
        cloudDeletedAt: Date?,
        downloadedAt: Date
    ) throws {
        switch entityType {
        case .moment:
            try database.markCloudKitRemotePostDeleted(
                postId: entityId,
                deletedAt: cloudDeletedAt ?? downloadedAt
            )
        case .media:
            try database.markCloudKitRemoteMediaDeleted(
                mediaId: entityId,
                deletedAt: cloudDeletedAt ?? downloadedAt
            )
        case .comment:
            try database.markCloudKitRemoteCommentDeleted(
                commentId: entityId,
                deletedAt: cloudDeletedAt ?? downloadedAt
            )
        case .tag:
            try database.applyTagDeleted(id: entityId)
        case .tagAlias:
            try database.markCloudKitRemoteTagAliasDeleted(aliasId: entityId, deletedAt: cloudDeletedAt ?? downloadedAt)
        case .postTag:
            try database.markCloudKitRemoteAssignedTagDeleted(assignedTagId: entityId, deletedAt: cloudDeletedAt ?? downloadedAt)
        case .checkInItem:
            try database.markCloudKitRemoteCheckInItemDeleted(itemId: entityId, deletedAt: cloudDeletedAt ?? downloadedAt)
        case .checkInEntry:
            try database.markCloudKitRemoteCheckInEntryDeleted(entryId: entityId, deletedAt: cloudDeletedAt ?? downloadedAt)
        case .checkInMedia:
            try database.markCloudKitRemoteCheckInMediaDeleted(mediaId: entityId, deletedAt: cloudDeletedAt ?? downloadedAt)
        case .aiSummary:
            try database.markCloudKitRemoteAISummaryDeleted(summaryId: entityId, deletedAt: cloudDeletedAt ?? downloadedAt)
        case .checkInAISummary:
            try database.markCloudKitRemoteCheckInAISummaryDeleted(summaryId: entityId, deletedAt: cloudDeletedAt ?? downloadedAt)
        case .weeklyReview:
            Self.markWeeklyReviewDeleted(reviewId: entityId, deletedAt: cloudDeletedAt ?? downloadedAt)
        case .preference:
            return
        case .draft:
            try Self.deleteDraft(entityId: entityId)
        }
    }

    private static func post(from payload: CloudKitRecordPayload) throws -> TimelinePost {
        TimelinePost(
            id: payload.entityId,
            text: try payload.requiredString("text"),
            isFavorite: payload.bool("isFavorite") ?? false,
            isPinned: payload.bool("isPinned") ?? false,
            pinnedAt: payload.date("pinnedAt"),
            aiTagProcessedAt: payload.date("aiTagProcessedAt"),
            tagsUserEditedAt: payload.date("tagsUserEditedAt"),
            occurredAt: try payload.requiredDate("occurredAt"),
            localCreatedAt: try payload.requiredDate("localCreatedAt"),
            localUpdatedAt: try payload.requiredDate("localUpdatedAt"),
            localEditedAt: payload.date("localEditedAt"),
            serverVersion: nil,
            syncStatus: "synced",
            deletedAt: payload.date("deletedAt")
        )
    }

    private static func comment(
        from payload: CloudKitRecordPayload,
        database: LocalDatabase
    ) throws -> TimelineComment {
        let postId = try payload.requiredString("postId")
        guard try database.fetchPost(id: postId) != nil else {
            throw CloudKitLocalRecordApplyError.missingParent("post:\(postId)")
        }

        return TimelineComment(
            id: payload.entityId,
            postId: postId,
            text: try payload.requiredString("text"),
            createdAt: try payload.requiredDate("createdAt"),
            updatedAt: try payload.requiredDate("updatedAt"),
            serverVersion: nil,
            deletedAt: payload.date("deletedAt")
        )
    }

    private static func media(
        from payload: CloudKitRecordPayload,
        database: LocalDatabase
    ) throws -> TimelineMedia {
        let postId = try payload.requiredString("postId")
        guard try database.fetchPost(id: postId) != nil else {
            throw CloudKitLocalRecordApplyError.missingParent("post:\(postId)")
        }

        return TimelineMedia(
            id: payload.entityId,
            postId: postId,
            kind: try payload.requiredString("kind"),
            localCompressedPath: "",
            localOriginalStagingPath: nil,
            localThumbnailPath: nil,
            remoteCompressedPath: nil,
            remoteOriginalPath: nil,
            remoteThumbnailPath: nil,
            originalPreserved: try payload.requiredBool("originalPreserved"),
            uploadStatus: "uploaded",
            mimeType: payload.string("mimeType"),
            durationSeconds: payload.double("durationSeconds"),
            transcriptionText: nil,
            transcriptionStatus: "not_requested",
            transcriptionError: nil,
            transcriptionUpdatedAt: nil,
            sortOrder: try payload.requiredInt("sortOrder"),
            checksum: payload.string("checksum"),
            createdAt: try payload.requiredDate("createdAt"),
            updatedAt: try payload.requiredDate("updatedAt")
        )
    }

    private static func checkInItem(from payload: CloudKitRecordPayload) throws -> CheckInItem {
        let recordModeRaw = try payload.requiredString("recordMode")
        guard let recordMode = CheckInRecordMode(rawValue: recordModeRaw) else {
            throw CloudKitLocalRecordApplyError.invalidField("recordMode")
        }
        let timeVisualizationRaw = try payload.requiredString("timeVisualization")
        guard let timeVisualization = CheckInTimeVisualization(rawValue: timeVisualizationRaw) else {
            throw CloudKitLocalRecordApplyError.invalidField("timeVisualization")
        }
        let activeWeekdays = try payload.requiredStringList("activeWeekdays").map { value in
            guard let weekday = Int(value), (1...7).contains(weekday) else {
                throw CloudKitLocalRecordApplyError.invalidField("activeWeekdays")
            }
            return weekday
        }

        return CheckInItem(
            id: payload.entityId,
            name: try payload.requiredString("name"),
            symbolName: try payload.requiredString("symbolName"),
            colorHex: try payload.requiredString("colorHex"),
            recordMode: recordMode,
            timeVisualization: timeVisualization,
            dayStartHour: try payload.requiredInt("dayStartHour"),
            activeWeekdays: activeWeekdays,
            sortOrder: try payload.requiredInt("sortOrder"),
            defaultShowInTimeline: try payload.requiredBool("defaultShowInTimeline"),
            tagId: payload.string("tagId"),
            createdAt: try payload.requiredDate("createdAt"),
            updatedAt: try payload.requiredDate("updatedAt"),
            archivedAt: payload.date("archivedAt"),
            deletedAt: payload.date("deletedAt"),
            syncStatus: "synced"
        )
    }

    private static func checkInEntry(
        from payload: CloudKitRecordPayload,
        database: LocalDatabase
    ) throws -> CheckInEntry {
        let itemId = try payload.requiredString("itemId")
        guard try database.fetchCheckInItem(id: itemId) != nil else {
            throw CloudKitLocalRecordApplyError.missingParent("checkin_item:\(itemId)")
        }

        return CheckInEntry(
            id: payload.entityId,
            itemId: itemId,
            occurredAt: try payload.requiredDate("occurredAt"),
            note: try payload.requiredString("note"),
            showInTimeline: try payload.requiredBool("showInTimeline"),
            createdAt: try payload.requiredDate("createdAt"),
            updatedAt: try payload.requiredDate("updatedAt"),
            deletedAt: payload.date("deletedAt"),
            syncStatus: "synced"
        )
    }

    private static func checkInMedia(
        from payload: CloudKitRecordPayload,
        database: LocalDatabase
    ) throws -> CheckInMedia {
        let entryId = try payload.requiredString("entryId")
        guard try database.fetchCheckInEntry(id: entryId) != nil else {
            throw CloudKitLocalRecordApplyError.missingParent("checkin_entry:\(entryId)")
        }

        return CheckInMedia(
            id: payload.entityId,
            entryId: entryId,
            kind: try payload.requiredString("kind"),
            localCompressedPath: "",
            remoteCompressedPath: nil,
            uploadStatus: "uploaded",
            uploadError: nil,
            mimeType: payload.string("mimeType"),
            durationSeconds: payload.double("durationSeconds"),
            transcriptionText: nil,
            transcriptionStatus: "not_requested",
            transcriptionError: nil,
            transcriptionUpdatedAt: nil,
            sortOrder: try payload.requiredInt("sortOrder"),
            checksum: payload.string("checksum"),
            createdAt: try payload.requiredDate("createdAt"),
            updatedAt: try payload.requiredDate("updatedAt"),
            deletedAt: payload.date("deletedAt")
        )
    }

    private static func timelineAISummary(
        from payload: CloudKitRecordPayload,
        database: LocalDatabase
    ) throws -> TimelineAISummary {
        let postId = try payload.requiredString("postId")
        let mediaId = try payload.requiredString("mediaId")
        guard try database.fetchPost(id: postId) != nil else {
            throw CloudKitLocalRecordApplyError.missingParent("post:\(postId)")
        }
        guard try database.fetchMedia(id: mediaId) != nil else {
            throw CloudKitLocalRecordApplyError.missingParent("media:\(mediaId)")
        }

        return TimelineAISummary(
            id: payload.entityId,
            postId: postId,
            mediaId: mediaId,
            status: try payload.requiredString("status"),
            format: payload.string("format"),
            language: payload.string("language"),
            overview: payload.string("overview"),
            keyPoints: try payload.stringList("keyPoints") ?? [],
            sections: try decodedSummarySections(from: payload, key: "sections"),
            summaryText: payload.string("summaryText"),
            documentTitle: payload.string("documentTitle"),
            oneLiner: payload.string("oneLiner"),
            documentBlocks: try decodedSummaryBlocks(from: payload, key: "documentBlocks"),
            inputTranscriptLength: nil,
            inputDurationSeconds: nil,
            inputTokenCount: nil,
            outputTokenCount: nil,
            totalTokenCount: nil,
            promptVersion: try payload.requiredString("promptVersion"),
            provider: nil,
            model: nil,
            errorCode: nil,
            errorMessage: nil,
            createdAt: try payload.requiredDate("createdAt"),
            updatedAt: try payload.requiredDate("updatedAt"),
            deletedAt: payload.date("deletedAt")
        )
    }

    private static func checkInAISummary(
        from payload: CloudKitRecordPayload,
        database: LocalDatabase
    ) throws -> CheckInAISummary {
        let entryId = try payload.requiredString("entryId")
        let mediaId = try payload.requiredString("mediaId")
        guard try database.fetchCheckInEntry(id: entryId) != nil else {
            throw CloudKitLocalRecordApplyError.missingParent("checkin_entry:\(entryId)")
        }
        guard try database.fetchCheckInMedia(id: mediaId) != nil else {
            throw CloudKitLocalRecordApplyError.missingParent("checkin_media:\(mediaId)")
        }

        return CheckInAISummary(
            id: payload.entityId,
            entryId: entryId,
            mediaId: mediaId,
            status: try payload.requiredString("status"),
            format: payload.string("format"),
            language: payload.string("language"),
            overview: payload.string("overview"),
            keyPoints: try payload.stringList("keyPoints") ?? [],
            sections: try decodedSummarySections(from: payload, key: "sections"),
            summaryText: payload.string("summaryText"),
            documentTitle: payload.string("documentTitle"),
            oneLiner: payload.string("oneLiner"),
            documentBlocks: try decodedSummaryBlocks(from: payload, key: "documentBlocks"),
            inputTranscriptLength: nil,
            inputDurationSeconds: nil,
            inputTokenCount: nil,
            outputTokenCount: nil,
            totalTokenCount: nil,
            promptVersion: try payload.requiredString("promptVersion"),
            provider: nil,
            model: nil,
            errorCode: nil,
            errorMessage: nil,
            createdAt: try payload.requiredDate("createdAt"),
            updatedAt: try payload.requiredDate("updatedAt"),
            deletedAt: payload.date("deletedAt")
        )
    }

    private static func weeklyReview(from payload: CloudKitRecordPayload) throws -> ReviewPayload {
        ReviewPayload(
            id: payload.entityId,
            kind: try payload.requiredString("kind"),
            rangeMode: try payload.requiredString("rangeMode"),
            rangeStart: try payload.requiredString("rangeStart"),
            rangeEnd: try payload.requiredString("rangeEnd"),
            status: try payload.requiredString("status"),
            trigger: try payload.requiredString("trigger"),
            content: try decodedJSON(ReviewContentPayload.self, from: payload, key: "content"),
            promptVersion: try payload.requiredString("promptVersion"),
            provider: nil,
            model: nil,
            language: payload.string("language"),
            errorCode: nil,
            errorMessage: nil,
            generatedAt: payload.string("generatedAt"),
            regeneratedFromReviewId: payload.string("regeneratedFromReviewId"),
            publishedPostId: payload.string("publishedPostId"),
            createdAt: try payload.requiredString("createdAt"),
            updatedAt: try payload.requiredString("updatedAt"),
            deletedAt: payload.stringOrDateString("deletedAt"),
            feedback: try decodedOptionalJSON(ReviewFeedbackStatePayload.self, from: payload, key: "feedback")
        )
    }

    private static func upsertWeeklyReview(_ review: ReviewPayload) {
        var reviews = AppSettings.localWeeklyReviews.filter { $0.id != review.id }
        reviews.append(review)
        AppSettings.localWeeklyReviews = sortedWeeklyReviews(reviews)
    }

    private static func markWeeklyReviewDeleted(reviewId: String, deletedAt: Date) {
        let deletedAtString = isoString(deletedAt)
        var reviews = AppSettings.localWeeklyReviews
        guard let index = reviews.firstIndex(where: { $0.id == reviewId }) else {
            return
        }

        let existing = reviews[index]
        reviews[index] = ReviewPayload(
            id: existing.id,
            kind: existing.kind,
            rangeMode: existing.rangeMode,
            rangeStart: existing.rangeStart,
            rangeEnd: existing.rangeEnd,
            status: "deleted",
            trigger: existing.trigger,
            content: existing.content,
            promptVersion: existing.promptVersion,
            provider: existing.provider,
            model: existing.model,
            language: existing.language,
            errorCode: existing.errorCode,
            errorMessage: existing.errorMessage,
            generatedAt: existing.generatedAt,
            regeneratedFromReviewId: existing.regeneratedFromReviewId,
            publishedPostId: existing.publishedPostId,
            createdAt: existing.createdAt,
            updatedAt: deletedAtString,
            deletedAt: deletedAtString,
            feedback: existing.feedback
        )
        AppSettings.localWeeklyReviews = sortedWeeklyReviews(reviews)
    }

    private static func preference(from payload: CloudKitRecordPayload) throws -> CloudKitPreferenceSnapshot {
        guard payload.entityId == CloudKitPreferenceSnapshot.recordId else {
            throw CloudKitLocalRecordApplyError.invalidField("entityId")
        }
        let schemaVersion = try payload.requiredInt("schemaVersion")
        guard schemaVersion == CloudKitPreferenceSnapshot.schemaVersion else {
            throw CloudKitLocalRecordApplyError.invalidField("schemaVersion")
        }
        let appearanceRaw = try payload.requiredString("appAppearanceMode")
        guard let appearanceMode = AppAppearanceMode(rawValue: appearanceRaw) else {
            throw CloudKitLocalRecordApplyError.invalidField("appAppearanceMode")
        }
        let appLanguageRaw = try payload.requiredString("appLanguageMode")
        guard let appLanguageMode = AppLanguageMode(rawValue: appLanguageRaw) else {
            throw CloudKitLocalRecordApplyError.invalidField("appLanguageMode")
        }
        let aiLanguageRaw = try payload.requiredString("aiLanguageMode")
        guard let aiLanguageMode = AILanguageMode(rawValue: aiLanguageRaw) else {
            throw CloudKitLocalRecordApplyError.invalidField("aiLanguageMode")
        }
        let transcriptionProviderRaw = try payload.requiredString("transcriptionProviderMode")
        guard let transcriptionProviderMode = TranscriptionProviderMode(rawValue: transcriptionProviderRaw) else {
            throw CloudKitLocalRecordApplyError.invalidField("transcriptionProviderMode")
        }

        return CloudKitPreferenceSnapshot(
            showTagsInTimeline: try payload.requiredBool("showTagsInTimeline"),
            showCheckInSummaries: try payload.requiredBool("showCheckInSummaries"),
            memoryLinksEnabled: try payload.requiredBool("memoryLinksEnabled"),
            aiTitleAutoInsertEnabled: try payload.requiredBool("aiTitleAutoInsertEnabled"),
            appAppearanceMode: appearanceMode,
            appLanguageMode: appLanguageMode,
            aiLanguageMode: aiLanguageMode,
            aiAnalysisEnabled: try payload.requiredBool("aiAnalysisEnabled"),
            aiExternalProcessingConsentAccepted: try payload.requiredBool("aiExternalProcessingConsentAccepted"),
            useTextProviderForTranscription: try payload.requiredBool("useTextProviderForTranscription"),
            transcriptionProviderMode: transcriptionProviderMode,
            preferredSpeechTranscriptionLocaleIdentifier: payload.string("preferredSpeechTranscriptionLocaleIdentifier"),
            autoWeeklyReviewEnabled: try payload.requiredBool("autoWeeklyReviewEnabled"),
            publishWeeklyReviewToMoments: try payload.requiredBool("publishWeeklyReviewToMoments"),
            markdownMathRenderingEnabled: try payload.requiredBool("markdownMathRenderingEnabled"),
            markdownRemoteImagesEnabled: try payload.requiredBool("markdownRemoteImagesEnabled"),
            markdownRawHTMLRenderingEnabled: try payload.requiredBool("markdownRawHTMLRenderingEnabled")
        )
    }

    private static func applyPreference(_ preference: CloudKitPreferenceSnapshot) {
        AppSettings.showTagsInTimeline = preference.showTagsInTimeline
        AppSettings.showCheckInSummaries = preference.showCheckInSummaries
        AppSettings.memoryLinksEnabled = preference.memoryLinksEnabled
        AppSettings.aiTitleAutoInsertEnabled = preference.aiTitleAutoInsertEnabled
        AppSettings.appAppearanceMode = preference.appAppearanceMode
        AppSettings.appLanguageMode = preference.appLanguageMode
        AppSettings.aiLanguageMode = preference.aiLanguageMode
        AppSettings.aiAnalysisEnabled = preference.aiAnalysisEnabled
        AppSettings.aiExternalProcessingConsentAccepted = preference.aiExternalProcessingConsentAccepted
        AppSettings.useTextProviderForTranscription = preference.useTextProviderForTranscription
        AppSettings.transcriptionProviderMode = preference.transcriptionProviderMode
        AppSettings.preferredSpeechTranscriptionLocaleIdentifier = preference.preferredSpeechTranscriptionLocaleIdentifier
        AppSettings.autoWeeklyReviewEnabled = preference.autoWeeklyReviewEnabled
        AppSettings.publishWeeklyReviewToMoments = preference.publishWeeklyReviewToMoments
        AppSettings.markdownMathRenderingEnabled = preference.markdownMathRenderingEnabled
        AppSettings.markdownRemoteImagesEnabled = preference.markdownRemoteImagesEnabled
        AppSettings.markdownRawHTMLRenderingEnabled = preference.markdownRawHTMLRenderingEnabled
    }

    private static func draft(from payload: CloudKitRecordPayload) throws -> CloudKitDraftSnapshot {
        let schemaVersion = try payload.requiredInt("schemaVersion")
        guard schemaVersion == CloudKitDraftSnapshot.schemaVersion else {
            throw CloudKitLocalRecordApplyError.invalidField("schemaVersion")
        }
        let draftKindRaw = try payload.requiredString("draftKind")
        guard let draftKind = CloudKitDraftSnapshot.Kind(rawValue: draftKindRaw) else {
            throw CloudKitLocalRecordApplyError.invalidField("draftKind")
        }

        let postId = payload.string("postId") ?? CloudKitDraftSnapshot.editPostId(from: payload.entityId)
        switch draftKind {
        case .composer:
            guard payload.entityId == CloudKitDraftSnapshot.composerRecordId, postId == nil else {
                throw CloudKitLocalRecordApplyError.invalidField("entityId")
            }
        case .editMoment:
            guard let postId,
                  CloudKitDraftSnapshot.matchesEditRecordId(payload.entityId, postId: postId) else {
                throw CloudKitLocalRecordApplyError.invalidField("postId")
            }
        }

        return CloudKitDraftSnapshot(
            kind: draftKind,
            entityId: payload.entityId,
            postId: postId,
            text: try payload.requiredString("text"),
            occurredAt: try payload.requiredDate("occurredAt"),
            updatedAt: try payload.requiredDate("updatedAt"),
            existingMediaIds: try payload.stringList("existingMediaIds") ?? [],
            hasUnsupportedMediaDrafts: try payload.requiredBool("hasUnsupportedMediaDrafts")
        )
    }

    private static func applyDraft(_ draft: CloudKitDraftSnapshot) throws {
        switch draft.kind {
        case .composer:
            ComposerDraftStore.save(
                text: draft.text,
                occurredAt: draft.occurredAt,
                updatedAt: draft.updatedAt
            )
        case .editMoment:
            guard let postId = draft.postId else {
                throw CloudKitLocalRecordApplyError.invalidField("postId")
            }
            try EditDraftStore.saveMetadata(
                postId: postId,
                text: draft.text,
                occurredAt: draft.occurredAt,
                updatedAt: draft.updatedAt,
                existingMediaIds: draft.existingMediaIds
            )
        }
    }

    private static func deleteDraft(entityId: String) throws {
        if entityId == CloudKitDraftSnapshot.composerRecordId {
            ComposerDraftStore.clearTextAndDate()
            return
        }

        guard let postId = CloudKitDraftSnapshot.editPostId(from: entityId) else {
            throw CloudKitLocalRecordApplyError.invalidField("entityId")
        }
        EditDraftStore.clear(postId: postId)
    }

    private static func sortedWeeklyReviews(_ reviews: [ReviewPayload]) -> [ReviewPayload] {
        reviews.sorted { lhs, rhs in
            lhs.updatedAt > rhs.updatedAt
        }
    }

    private static func isoString(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func tag(from payload: CloudKitRecordPayload) throws -> TimelineTag {
        TimelineTag(
            id: payload.entityId,
            type: try payload.requiredString("type"),
            name: try payload.requiredString("name"),
            normalizedName: try payload.requiredString("normalizedName"),
            colorHex: payload.string("colorHex"),
            isDefault: try payload.requiredBool("isDefault"),
            isArchived: try payload.requiredBool("isArchived"),
            aiUsableAsPrimary: try payload.requiredBool("aiUsableAsPrimary"),
            createdAt: try payload.requiredDate("createdAt"),
            updatedAt: try payload.requiredDate("updatedAt"),
            archivedAt: payload.date("archivedAt"),
            areaId: payload.string("areaId")
        )
    }

    private static func tagAlias(from payload: CloudKitRecordPayload) throws -> TimelineTagAlias {
        TimelineTagAlias(
            id: payload.entityId,
            tagId: try payload.requiredString("tagId"),
            alias: try payload.requiredString("alias"),
            normalizedAlias: try payload.requiredString("normalizedAlias"),
            createdAt: try payload.requiredDate("createdAt"),
            deletedAt: payload.date("deletedAt")
        )
    }

    private static func assignedTag(
        from payload: CloudKitRecordPayload,
        database: LocalDatabase
    ) throws -> TimelineAssignedTag {
        let postId = try payload.requiredString("postId")
        let tagId = try payload.requiredString("tagId")
        guard try database.fetchPost(id: postId) != nil else {
            throw CloudKitLocalRecordApplyError.missingParent("post:\(postId)")
        }
        guard let tag = try database.fetchTag(id: tagId) else {
            throw CloudKitLocalRecordApplyError.missingParent("tag:\(tagId)")
        }

        return TimelineAssignedTag(
            id: payload.entityId,
            postId: postId,
            tagId: tagId,
            role: try payload.requiredString("role"),
            source: try payload.requiredString("source"),
            confidence: payload.double("confidence"),
            aiSummaryId: payload.string("aiSummaryId"),
            createdAt: try payload.requiredDate("createdAt"),
            updatedAt: try payload.requiredDate("updatedAt"),
            deletedAt: payload.date("deletedAt"),
            tag: tag
        )
    }

    private static func decodedSummarySections(
        from payload: CloudKitRecordPayload,
        key: String
    ) throws -> [TimelineAISummarySection] {
        try decodedJSON([TimelineAISummarySection].self, from: payload, key: key)
    }

    private static func decodedSummaryBlocks(
        from payload: CloudKitRecordPayload,
        key: String
    ) throws -> [TimelineAISummaryBlock] {
        try decodedJSON([TimelineAISummaryBlock].self, from: payload, key: key)
    }

    private static func decodedJSON<T: Decodable>(
        _ type: T.Type,
        from payload: CloudKitRecordPayload,
        key: String
    ) throws -> T {
        let json = try payload.requiredString(key)
        guard let data = json.data(using: .utf8) else {
            throw CloudKitLocalRecordApplyError.invalidField(key)
        }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw CloudKitLocalRecordApplyError.invalidField(key)
        }
    }

    private static func decodedOptionalJSON<T: Decodable>(
        _ type: T.Type,
        from payload: CloudKitRecordPayload,
        key: String
    ) throws -> T? {
        guard let json = payload.string(key) else {
            return nil
        }
        guard let data = json.data(using: .utf8) else {
            throw CloudKitLocalRecordApplyError.invalidField(key)
        }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw CloudKitLocalRecordApplyError.invalidField(key)
        }
    }

    private static func materializedMediaAssets(
        from assetRecord: CloudKitDownloadedAssetRecord
    ) throws -> MaterializedMediaAssets {
        var assets = MaterializedMediaAssets()
        for assetField in assetRecord.assetFields {
            let localPath = try copyAsset(assetField, payload: assetRecord.payload)
            switch assetField.fieldName {
            case "compressedAsset":
                assets.compressedPath = localPath
            case "thumbnailAsset":
                assets.thumbnailPath = localPath
            case "originalAsset":
                assets.originalPath = localPath
            default:
                break
            }
        }
        return assets
    }

    private static func copyAsset(
        _ assetField: CloudKitAssetField,
        payload: CloudKitRecordPayload
    ) throws -> String {
        let directory = try AppDirectories.mediaDirectory()
        let fileExtension = assetField.fileURL.pathExtension.isEmpty ? "bin" : assetField.fileURL.pathExtension
        let fileName = [
            "cloudkit",
            safeFileNameComponent(payload.entityType.rawValue),
            safeFileNameComponent(payload.entityId),
            safeFileNameComponent(assetField.fieldName)
        ].joined(separator: "-")
        let destination = directory.appending(path: "\(fileName).\(fileExtension)")

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: assetField.fileURL, to: destination)
        return destination.path
    }

    private static func safeFileNameComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        let result = value.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? String(scalar) : "_"
        }.joined()
        return result.isEmpty ? "asset" : result
    }
}

enum CloudKitLocalRecordApplyError: Error, Equatable {
    case missingField(String)
    case invalidField(String)
    case missingParent(String)
    case unsupportedEntityType(CloudKitSyncEntityType)
}

private struct MaterializedMediaAssets {
    var compressedPath: String?
    var thumbnailPath: String?
    var originalPath: String?
}

private extension CloudKitRecordPayload {
    func requiredString(_ key: String) throws -> String {
        guard let value = fields[key] else {
            throw CloudKitLocalRecordApplyError.missingField(key)
        }
        guard case .string(let string) = value else {
            throw CloudKitLocalRecordApplyError.invalidField(key)
        }
        return string
    }

    func requiredBool(_ key: String) throws -> Bool {
        guard let value = fields[key] else {
            throw CloudKitLocalRecordApplyError.missingField(key)
        }
        guard let bool = value.boolValue else {
            throw CloudKitLocalRecordApplyError.invalidField(key)
        }
        return bool
    }

    func requiredInt(_ key: String) throws -> Int {
        guard let value = fields[key] else {
            throw CloudKitLocalRecordApplyError.missingField(key)
        }
        guard case .int(let int) = value else {
            throw CloudKitLocalRecordApplyError.invalidField(key)
        }
        return int
    }

    func requiredDate(_ key: String) throws -> Date {
        guard let value = fields[key] else {
            throw CloudKitLocalRecordApplyError.missingField(key)
        }
        guard case .date(let date) = value else {
            throw CloudKitLocalRecordApplyError.invalidField(key)
        }
        return date
    }

    func requiredStringList(_ key: String) throws -> [String] {
        guard let value = fields[key] else {
            throw CloudKitLocalRecordApplyError.missingField(key)
        }
        return try stringList(key, value: value)
    }

    func bool(_ key: String) -> Bool? {
        fields[key]?.boolValue
    }

    func string(_ key: String) -> String? {
        guard case .string(let string) = fields[key] else {
            return nil
        }
        return string
    }

    func double(_ key: String) -> Double? {
        guard case .double(let double) = fields[key] else {
            return nil
        }
        return double
    }

    func date(_ key: String) -> Date? {
        guard case .date(let date) = fields[key] else {
            return nil
        }
        return date
    }

    func stringList(_ key: String) throws -> [String]? {
        guard let value = fields[key] else {
            return nil
        }
        return try stringList(key, value: value)
    }

    func stringOrDateString(_ key: String) -> String? {
        if let string = string(key) {
            return string
        }
        return date(key).map { ISO8601DateFormatter().string(from: $0) }
    }

    private func stringList(_ key: String, value: CloudKitRecordFieldValue) throws -> [String] {
        guard case .stringList(let strings) = value else {
            throw CloudKitLocalRecordApplyError.invalidField(key)
        }
        return strings
    }
}

private extension CloudKitRecordFieldValue {
    var boolValue: Bool? {
        switch self {
        case .bool(let bool):
            return bool
        case .int(0):
            return false
        case .int(1):
            return true
        default:
            return nil
        }
    }
}
