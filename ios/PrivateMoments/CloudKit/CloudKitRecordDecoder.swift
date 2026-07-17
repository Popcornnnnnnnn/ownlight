import CloudKit
import Foundation

enum CloudKitRecordDecoder {
    static func payload(from record: CKRecord) throws -> CloudKitRecordPayload {
        let identity = try CloudKitRecordIdentityDecoder.identity(
            recordType: record.recordType,
            recordName: record.recordID.recordName,
            zoneName: record.recordID.zoneID.zoneName
        )
        var fields = [String: CloudKitRecordFieldValue]()
        for key in record.allKeys() {
            guard let value = record[key] else {
                continue
            }
            if value is CKAsset {
                continue
            }
            fields[key] = try fieldValue(from: value, key: key)
        }

        return CloudKitRecordPayload(
            entityType: identity.entityType,
            entityId: identity.entityId,
            zoneName: identity.zoneName,
            fields: fields
        )
    }

    static func assetFields(from record: CKRecord) -> [CloudKitAssetField] {
        record.allKeys()
            .compactMap { key -> CloudKitAssetField? in
                guard
                    let asset = record[key] as? CKAsset,
                    let fileURL = asset.fileURL
                else {
                    return nil
                }
                return CloudKitAssetField(fieldName: key, fileURL: fileURL)
            }
            .sorted { $0.fieldName < $1.fieldName }
    }

    private static func fieldValue(from value: CKRecordValue, key: String) throws -> CloudKitRecordFieldValue {
        if let value = value as? String {
            return .string(value)
        }

        if let value = value as? Date {
            return .date(value)
        }

        if let value = value as? [String] {
            return .stringList(value)
        }

        if let value = value as? NSArray {
            let strings = value.compactMap { $0 as? String }
            if strings.count == value.count {
                return .stringList(strings)
            }
        }

        if let value = value as? NSNumber {
            switch String(cString: value.objCType) {
            case "c", "B":
                return .bool(value.boolValue)
            case "f", "d":
                return .double(value.doubleValue)
            default:
                return .int(value.intValue)
            }
        }

        throw CloudKitRecordDecoderError.unsupportedFieldValue(key)
    }
}

enum CloudKitRecordDecoderError: Error, Equatable {
    case unsupportedRecordType(String)
    case invalidRecordName(String)
    case unsupportedFieldValue(String)
}
