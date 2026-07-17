import CloudKit
import Foundation

enum CloudKitRecordEncoder {
    static func record(from payload: CloudKitRecordPayload) -> CKRecord {
        record(from: payload, assetFields: [])
    }

    static func record(from payload: CloudKitAssetRecordPayload) -> CKRecord {
        record(from: payload.metadataPayload, assetFields: payload.assetFields)
    }

    static func record(from payload: CloudKitRecordPayload, updating record: CKRecord) -> CKRecord {
        apply(payload.fields, assetFields: [], to: record)
        return record
    }

    static func record(from payload: CloudKitAssetRecordPayload, updating record: CKRecord) -> CKRecord {
        apply(payload.metadataPayload.fields, assetFields: payload.assetFields, to: record)
        return record
    }

    private static func record(
        from payload: CloudKitRecordPayload,
        assetFields: [CloudKitAssetField]
    ) -> CKRecord {
        let zoneID = CKRecordZone.ID(
            zoneName: payload.zoneName,
            ownerName: CKCurrentUserDefaultName
        )
        let recordID = CKRecord.ID(
            recordName: payload.recordName,
            zoneID: zoneID
        )
        let record = CKRecord(
            recordType: payload.recordType,
            recordID: recordID
        )

        apply(payload.fields, assetFields: assetFields, to: record)

        return record
    }

    private static func apply(
        _ fields: [String: CloudKitRecordFieldValue],
        assetFields: [CloudKitAssetField],
        to record: CKRecord
    ) {
        for (key, value) in fields {
            set(value, forKey: key, in: record)
        }

        for field in assetFields {
            record[field.fieldName] = CKAsset(fileURL: field.fileURL)
        }
    }

    private static func set(
        _ value: CloudKitRecordFieldValue,
        forKey key: String,
        in record: CKRecord
    ) {
        switch value {
        case .string(let value):
            record[key] = value as NSString
        case .int(let value):
            record[key] = NSNumber(value: value)
        case .double(let value):
            record[key] = NSNumber(value: value)
        case .bool(let value):
            record[key] = NSNumber(value: value)
        case .date(let value):
            record[key] = value as NSDate
        case .stringList(let value):
            record[key] = value.isEmpty ? nil : value as NSArray
        }
    }
}
