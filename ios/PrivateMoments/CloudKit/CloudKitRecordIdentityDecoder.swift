import Foundation

enum CloudKitRecordIdentityDecoder {
    static func identity(
        recordType: String,
        recordName: String,
        zoneName: String
    ) throws -> CloudKitDeletedRecordIdentity {
        guard let entityType = CloudKitSyncEntityType.allCases.first(where: { $0.recordType == recordType }) else {
            throw CloudKitRecordDecoderError.unsupportedRecordType(recordType)
        }

        let prefix = "pm.\(entityType.rawValue)."
        guard recordName.hasPrefix(prefix) else {
            throw CloudKitRecordDecoderError.invalidRecordName(recordName)
        }

        let rawEntityId = String(recordName.dropFirst(prefix.count))
        let entityId = canonicalEntityId(rawEntityId, entityType: entityType)
        guard !entityId.isEmpty else {
            throw CloudKitRecordDecoderError.invalidRecordName(recordName)
        }

        return CloudKitDeletedRecordIdentity(
            entityType: entityType,
            entityId: entityId,
            recordType: recordType,
            recordName: recordName,
            zoneName: zoneName
        )
    }

    private static func canonicalEntityId(
        _ entityId: String,
        entityType: CloudKitSyncEntityType
    ) -> String {
        guard entityType == .draft,
              entityId.hasPrefix("edit_")
        else {
            return entityId
        }

        let postId = String(entityId.dropFirst("edit_".count))
        guard !postId.isEmpty else {
            return entityId
        }
        return CloudKitDraftSnapshot.editRecordId(postId: postId)
    }
}
