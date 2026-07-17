import Foundation

enum CloudKitRecordFieldValue: Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case date(Date)
    case stringList([String])
}

struct CloudKitRecordPayload: Equatable {
    var entityType: CloudKitSyncEntityType
    var entityId: String
    var recordType: String
    var recordName: String
    var zoneName: String
    var fields: [String: CloudKitRecordFieldValue]

    init(
        entityType: CloudKitSyncEntityType,
        entityId: String,
        zoneName: String = CloudKitSyncDefaults.zoneName,
        fields: [String: CloudKitRecordFieldValue]
    ) {
        self.entityType = entityType
        self.entityId = entityId
        self.recordType = entityType.recordType
        self.recordName = entityType.recordName(entityId: entityId)
        self.zoneName = zoneName
        self.fields = fields
    }
}

struct CloudKitAssetField: Equatable {
    var fieldName: String
    var fileURL: URL
}

struct CloudKitAssetRecordPayload: Equatable {
    var metadataPayload: CloudKitRecordPayload
    var assetFields: [CloudKitAssetField]
}

struct CloudKitDownloadedAssetRecord: Equatable {
    var payload: CloudKitRecordPayload
    var assetFields: [CloudKitAssetField]
}

struct CloudKitDeletedRecordIdentity: Equatable {
    var entityType: CloudKitSyncEntityType
    var entityId: String
    var recordType: String
    var recordName: String
    var zoneName: String
}

struct CloudKitDownloadedChanges: Equatable {
    var modifiedPayloads: [CloudKitRecordPayload]
    var modifiedAssetRecords: [CloudKitDownloadedAssetRecord] = []
    var deletedRecords: [CloudKitDeletedRecordIdentity]
    var serverChangeTokenData: Data?
    var moreComing: Bool
}
