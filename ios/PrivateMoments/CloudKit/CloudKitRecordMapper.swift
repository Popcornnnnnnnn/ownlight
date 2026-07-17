import Foundation

enum CloudKitRecordMapper {
    static func payload(for post: TimelinePost) -> CloudKitRecordPayload {
        var fields: [String: CloudKitRecordFieldValue] = [
            "text": .string(post.text),
            "isFavorite": .bool(post.isFavorite),
            "isPinned": .bool(post.isPinned),
            "occurredAt": .date(post.occurredAt),
            "localCreatedAt": .date(post.localCreatedAt),
            "localUpdatedAt": .date(post.localUpdatedAt)
        ]

        fields.setDate("pinnedAt", post.pinnedAt)
        fields.setDate("aiTagProcessedAt", post.aiTagProcessedAt)
        fields.setDate("tagsUserEditedAt", post.tagsUserEditedAt)
        fields.setDate("localEditedAt", post.localEditedAt)
        fields.setDate("deletedAt", post.deletedAt)

        return CloudKitRecordPayload(
            entityType: .moment,
            entityId: post.id,
            fields: fields
        )
    }

    static func payload(for comment: TimelineComment) -> CloudKitRecordPayload {
        var fields: [String: CloudKitRecordFieldValue] = [
            "postId": .string(comment.postId),
            "text": .string(comment.text),
            "createdAt": .date(comment.createdAt),
            "updatedAt": .date(comment.updatedAt)
        ]

        fields.setDate("deletedAt", comment.deletedAt)

        return CloudKitRecordPayload(
            entityType: .comment,
            entityId: comment.id,
            fields: fields
        )
    }

    static func payload(for media: TimelineMedia) -> CloudKitRecordPayload {
        var fields: [String: CloudKitRecordFieldValue] = [
            "postId": .string(media.postId),
            "kind": .string(media.kind),
            "originalPreserved": .bool(media.originalPreserved),
            "sortOrder": .int(media.sortOrder),
            "createdAt": .date(media.createdAt),
            "updatedAt": .date(media.updatedAt)
        ]

        fields.setString("mimeType", media.mimeType)
        fields.setDouble("durationSeconds", media.durationSeconds)
        fields.setString("checksum", media.checksum)

        return CloudKitRecordPayload(
            entityType: .media,
            entityId: media.id,
            fields: fields
        )
    }

    static func payload(for summary: TimelineAISummary) -> CloudKitRecordPayload {
        var fields: [String: CloudKitRecordFieldValue] = [
            "postId": .string(summary.postId),
            "mediaId": .string(summary.mediaId),
            "status": .string(summary.status),
            "keyPoints": .stringList(summary.keyPoints),
            "sections": .string(jsonString(summary.sections)),
            "documentBlocks": .string(jsonString(summary.documentBlocks)),
            "promptVersion": .string(summary.promptVersion),
            "createdAt": .date(summary.createdAt),
            "updatedAt": .date(summary.updatedAt)
        ]

        fields.setString("format", summary.format)
        fields.setString("language", summary.language)
        fields.setString("overview", summary.overview)
        fields.setString("summaryText", summary.summaryText)
        fields.setString("documentTitle", summary.documentTitle)
        fields.setString("oneLiner", summary.oneLiner)
        fields.setDate("deletedAt", summary.deletedAt)

        return CloudKitRecordPayload(
            entityType: .aiSummary,
            entityId: summary.id,
            fields: fields
        )
    }

    static func payload(for tag: TimelineTag) -> CloudKitRecordPayload {
        var fields: [String: CloudKitRecordFieldValue] = [
            "type": .string(tag.type),
            "name": .string(tag.name),
            "normalizedName": .string(tag.normalizedName),
            "isDefault": .bool(tag.isDefault),
            "isArchived": .bool(tag.isArchived),
            "aiUsableAsPrimary": .bool(tag.aiUsableAsPrimary),
            "createdAt": .date(tag.createdAt),
            "updatedAt": .date(tag.updatedAt)
        ]

        fields.setString("colorHex", tag.colorHex)
        fields.setString("areaId", tag.isTopic ? tag.resolvedArea.rawValue : nil)
        fields.setDate("archivedAt", tag.archivedAt)

        return CloudKitRecordPayload(
            entityType: .tag,
            entityId: tag.id,
            fields: fields
        )
    }

    static func payload(for alias: TimelineTagAlias) -> CloudKitRecordPayload {
        var fields: [String: CloudKitRecordFieldValue] = [
            "tagId": .string(alias.tagId),
            "alias": .string(alias.alias),
            "normalizedAlias": .string(alias.normalizedAlias),
            "createdAt": .date(alias.createdAt)
        ]

        fields.setDate("deletedAt", alias.deletedAt)

        return CloudKitRecordPayload(
            entityType: .tagAlias,
            entityId: alias.id,
            fields: fields
        )
    }

    static func payload(for assignedTag: TimelineAssignedTag) -> CloudKitRecordPayload {
        var fields: [String: CloudKitRecordFieldValue] = [
            "postId": .string(assignedTag.postId),
            "tagId": .string(assignedTag.tagId),
            "role": .string(assignedTag.role),
            "source": .string(assignedTag.source),
            "createdAt": .date(assignedTag.createdAt),
            "updatedAt": .date(assignedTag.updatedAt)
        ]

        fields.setDouble("confidence", assignedTag.confidence)
        fields.setString("aiSummaryId", assignedTag.aiSummaryId)
        fields.setDate("deletedAt", assignedTag.deletedAt)

        return CloudKitRecordPayload(
            entityType: .postTag,
            entityId: assignedTag.id,
            fields: fields
        )
    }

    static func payload(for item: CheckInItem) -> CloudKitRecordPayload {
        var fields: [String: CloudKitRecordFieldValue] = [
            "name": .string(item.name),
            "symbolName": .string(item.symbolName),
            "colorHex": .string(item.colorHex),
            "recordMode": .string(item.recordMode.rawValue),
            "timeVisualization": .string(item.timeVisualization.rawValue),
            "dayStartHour": .int(item.dayStartHour),
            "activeWeekdays": .stringList(item.activeWeekdays.map(String.init)),
            "sortOrder": .int(item.sortOrder),
            "defaultShowInTimeline": .bool(item.defaultShowInTimeline),
            "createdAt": .date(item.createdAt),
            "updatedAt": .date(item.updatedAt)
        ]

        fields.setString("tagId", item.tagId)
        fields.setDate("archivedAt", item.archivedAt)
        fields.setDate("deletedAt", item.deletedAt)

        return CloudKitRecordPayload(
            entityType: .checkInItem,
            entityId: item.id,
            fields: fields
        )
    }

    static func payload(for entry: CheckInEntry) -> CloudKitRecordPayload {
        var fields: [String: CloudKitRecordFieldValue] = [
            "itemId": .string(entry.itemId),
            "occurredAt": .date(entry.occurredAt),
            "note": .string(entry.note),
            "showInTimeline": .bool(entry.showInTimeline),
            "createdAt": .date(entry.createdAt),
            "updatedAt": .date(entry.updatedAt)
        ]

        fields.setDate("deletedAt", entry.deletedAt)

        return CloudKitRecordPayload(
            entityType: .checkInEntry,
            entityId: entry.id,
            fields: fields
        )
    }

    static func payload(for media: CheckInMedia) -> CloudKitRecordPayload {
        var fields: [String: CloudKitRecordFieldValue] = [
            "entryId": .string(media.entryId),
            "kind": .string(media.kind),
            "sortOrder": .int(media.sortOrder),
            "createdAt": .date(media.createdAt),
            "updatedAt": .date(media.updatedAt)
        ]

        fields.setString("mimeType", media.mimeType)
        fields.setDouble("durationSeconds", media.durationSeconds)
        fields.setString("checksum", media.checksum)
        fields.setDate("deletedAt", media.deletedAt)

        return CloudKitRecordPayload(
            entityType: .checkInMedia,
            entityId: media.id,
            fields: fields
        )
    }

    static func payload(for summary: CheckInAISummary) -> CloudKitRecordPayload {
        var fields: [String: CloudKitRecordFieldValue] = [
            "entryId": .string(summary.entryId),
            "mediaId": .string(summary.mediaId),
            "status": .string(summary.status),
            "keyPoints": .stringList(summary.keyPoints),
            "sections": .string(jsonString(summary.sections)),
            "documentBlocks": .string(jsonString(summary.documentBlocks)),
            "promptVersion": .string(summary.promptVersion),
            "createdAt": .date(summary.createdAt),
            "updatedAt": .date(summary.updatedAt)
        ]

        fields.setString("format", summary.format)
        fields.setString("language", summary.language)
        fields.setString("overview", summary.overview)
        fields.setString("summaryText", summary.summaryText)
        fields.setString("documentTitle", summary.documentTitle)
        fields.setString("oneLiner", summary.oneLiner)
        fields.setDate("deletedAt", summary.deletedAt)

        return CloudKitRecordPayload(
            entityType: .checkInAISummary,
            entityId: summary.id,
            fields: fields
        )
    }

    static func payload(for review: ReviewPayload) -> CloudKitRecordPayload {
        var fields: [String: CloudKitRecordFieldValue] = [
            "kind": .string(review.kind),
            "rangeMode": .string(review.rangeMode),
            "rangeStart": .string(review.rangeStart),
            "rangeEnd": .string(review.rangeEnd),
            "status": .string(review.status),
            "trigger": .string(review.trigger),
            "content": .string(jsonString(review.content)),
            "promptVersion": .string(review.promptVersion),
            "createdAt": .string(review.createdAt),
            "updatedAt": .string(review.updatedAt)
        ]

        fields.setString("language", review.language)
        fields.setString("generatedAt", review.generatedAt)
        fields.setString("regeneratedFromReviewId", review.regeneratedFromReviewId)
        fields.setString("publishedPostId", review.publishedPostId)
        fields.setJSON("feedback", review.feedback)
        fields.setISODate("deletedAt", review.deletedAt)

        return CloudKitRecordPayload(
            entityType: .weeklyReview,
            entityId: review.id,
            fields: fields
        )
    }

    static func payload(for preferences: CloudKitPreferenceSnapshot) -> CloudKitRecordPayload {
        var fields: [String: CloudKitRecordFieldValue] = [
            "schemaVersion": .int(CloudKitPreferenceSnapshot.schemaVersion),
            "showTagsInTimeline": .bool(preferences.showTagsInTimeline),
            "showCheckInSummaries": .bool(preferences.showCheckInSummaries),
            "memoryLinksEnabled": .bool(preferences.memoryLinksEnabled),
            "aiTitleAutoInsertEnabled": .bool(preferences.aiTitleAutoInsertEnabled),
            "appAppearanceMode": .string(preferences.appAppearanceMode.rawValue),
            "appLanguageMode": .string(preferences.appLanguageMode.rawValue),
            "aiLanguageMode": .string(preferences.aiLanguageMode.rawValue),
            "aiAnalysisEnabled": .bool(preferences.aiAnalysisEnabled),
            "aiExternalProcessingConsentAccepted": .bool(preferences.aiExternalProcessingConsentAccepted),
            "useTextProviderForTranscription": .bool(preferences.useTextProviderForTranscription),
            "transcriptionProviderMode": .string(preferences.transcriptionProviderMode.rawValue),
            "autoWeeklyReviewEnabled": .bool(preferences.autoWeeklyReviewEnabled),
            "publishWeeklyReviewToMoments": .bool(preferences.publishWeeklyReviewToMoments),
            "markdownMathRenderingEnabled": .bool(preferences.markdownMathRenderingEnabled),
            "markdownRemoteImagesEnabled": .bool(preferences.markdownRemoteImagesEnabled),
            "markdownRawHTMLRenderingEnabled": .bool(preferences.markdownRawHTMLRenderingEnabled)
        ]

        fields.setString(
            "preferredSpeechTranscriptionLocaleIdentifier",
            preferences.preferredSpeechTranscriptionLocaleIdentifier
        )

        return CloudKitRecordPayload(
            entityType: .preference,
            entityId: CloudKitPreferenceSnapshot.recordId,
            fields: fields
        )
    }

    static func payload(for draft: CloudKitDraftSnapshot) -> CloudKitRecordPayload {
        var fields: [String: CloudKitRecordFieldValue] = [
            "schemaVersion": .int(CloudKitDraftSnapshot.schemaVersion),
            "draftKind": .string(draft.kind.rawValue),
            "text": .string(draft.text),
            "occurredAt": .date(draft.occurredAt),
            "updatedAt": .date(draft.updatedAt),
            "existingMediaIds": .stringList(draft.existingMediaIds),
            "hasUnsupportedMediaDrafts": .bool(draft.hasUnsupportedMediaDrafts)
        ]

        fields.setString("postId", draft.postId)

        return CloudKitRecordPayload(
            entityType: .draft,
            entityId: draft.entityId,
            fields: fields
        )
    }

    fileprivate static func jsonString<T: Encodable>(_ value: T) -> String {
        guard let data = try? JSONEncoder().encode(value) else {
            return "[]"
        }

        return String(decoding: data, as: UTF8.self)
    }
}

private extension Dictionary where Key == String, Value == CloudKitRecordFieldValue {
    mutating func setString(_ key: String, _ value: String?) {
        guard let value else {
            return
        }
        self[key] = .string(value)
    }

    mutating func setDouble(_ key: String, _ value: Double?) {
        guard let value else {
            return
        }
        self[key] = .double(value)
    }

    mutating func setDate(_ key: String, _ value: Date?) {
        guard let value else {
            return
        }
        self[key] = .date(value)
    }

    mutating func setISODate(_ key: String, _ value: String?) {
        guard let value else {
            return
        }

        if let date = CloudKitRecordMapper.isoDate(value) {
            self[key] = .date(date)
        } else {
            self[key] = .string(value)
        }
    }

    mutating func setJSON<T: Encodable>(_ key: String, _ value: T?) {
        guard let value else {
            return
        }

        self[key] = .string(CloudKitRecordMapper.jsonString(value))
    }
}

fileprivate extension CloudKitRecordMapper {
    static func isoDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }
}
