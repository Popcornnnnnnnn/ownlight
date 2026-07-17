import Foundation

final class CloudKitLocalPayloadResolver: CloudKitSyncPayloadResolving {
    private let database: LocalDatabase

    init(database: LocalDatabase) {
        self.database = database
    }

    func payload(for change: CloudKitPendingChange) throws -> CloudKitRecordPayload? {
        switch change.entityType {
        case .moment:
            return try database.fetchPost(id: change.entityId).map(CloudKitRecordMapper.payload)
        case .media:
            return try database.fetchMedia(id: change.entityId).map(CloudKitRecordMapper.payload)
        case .comment:
            return try database.fetchComment(id: change.entityId).map(CloudKitRecordMapper.payload)
        case .tag:
            return try database.fetchTag(id: change.entityId).map(CloudKitRecordMapper.payload)
        case .tagAlias:
            return try database.fetchTagAlias(id: change.entityId).map(CloudKitRecordMapper.payload)
        case .postTag:
            return try database.fetchAssignedTag(id: change.entityId).map(CloudKitRecordMapper.payload)
        case .checkInItem:
            return try database.fetchCheckInItem(id: change.entityId).map(CloudKitRecordMapper.payload)
        case .checkInEntry:
            return try database.fetchCheckInEntry(id: change.entityId).map(CloudKitRecordMapper.payload)
        case .checkInMedia:
            return try database.fetchCheckInMedia(id: change.entityId).map(CloudKitRecordMapper.payload)
        case .aiSummary:
            return try database.fetchAISummary(id: change.entityId).map(CloudKitRecordMapper.payload)
        case .checkInAISummary:
            return try database.fetchCheckInAISummary(id: change.entityId).map(CloudKitRecordMapper.payload)
        case .weeklyReview:
            return AppSettings.localWeeklyReviews
                .first { $0.id == change.entityId }
                .map(CloudKitRecordMapper.payload)
        case .preference:
            guard change.entityId == CloudKitPreferenceSnapshot.recordId else {
                return nil
            }
            return CloudKitRecordMapper.payload(for: CloudKitPreferenceSnapshot.current())
        case .draft:
            if change.entityId == CloudKitDraftSnapshot.composerRecordId {
                return CloudKitDraftSnapshot.currentComposer().map(CloudKitRecordMapper.payload)
            }
            guard let postId = CloudKitDraftSnapshot.editPostId(from: change.entityId) else {
                return nil
            }
            return CloudKitDraftSnapshot.currentEdit(postId: postId).map(CloudKitRecordMapper.payload)
        }
    }

    func assetPayload(for change: CloudKitPendingChange) throws -> CloudKitAssetRecordPayload? {
        guard change.changeKind == .assetUpload else {
            return nil
        }

        switch change.entityType {
        case .media:
            guard let media = try database.fetchMedia(id: change.entityId) else {
                return nil
            }
            let fields = assetFields(for: media)
            guard !fields.isEmpty else {
                return nil
            }
            return CloudKitAssetRecordPayload(
                metadataPayload: CloudKitRecordMapper.payload(for: media),
                assetFields: fields
            )
        case .checkInMedia:
            guard let media = try database.fetchCheckInMedia(id: change.entityId) else {
                return nil
            }
            let fields = assetFields(for: media)
            guard !fields.isEmpty else {
                return nil
            }
            return CloudKitAssetRecordPayload(
                metadataPayload: CloudKitRecordMapper.payload(for: media),
                assetFields: fields
            )
        case .moment, .comment, .tag, .tagAlias, .postTag, .checkInItem, .checkInEntry,
             .aiSummary, .checkInAISummary, .weeklyReview, .preference, .draft:
            return nil
        }
    }

    private func assetFields(for media: TimelineMedia) -> [CloudKitAssetField] {
        var fields = [CloudKitAssetField]()
        appendExistingAssetField(&fields, name: "compressedAsset", path: media.localCompressedPath)
        appendExistingAssetField(&fields, name: "thumbnailAsset", path: media.localThumbnailPath)
        if media.originalPreserved {
            appendExistingAssetField(&fields, name: "originalAsset", path: media.localOriginalStagingPath)
        }
        return fields
    }

    private func assetFields(for media: CheckInMedia) -> [CloudKitAssetField] {
        var fields = [CloudKitAssetField]()
        appendExistingAssetField(&fields, name: "compressedAsset", path: media.localCompressedPath)
        return fields
    }

    private func appendExistingAssetField(
        _ fields: inout [CloudKitAssetField],
        name: String,
        path: String?
    ) {
        guard let path, !path.isEmpty, FileManager.default.fileExists(atPath: path) else {
            return
        }
        fields.append(.init(fieldName: name, fileURL: URL(fileURLWithPath: path)))
    }
}
