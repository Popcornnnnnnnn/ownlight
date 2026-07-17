import CloudKit
import Foundation

protocol CloudKitDatabaseWriting {
    func saveZone(_ zone: CKRecordZone) async throws -> CKRecordZone
    func fetchRecordZone(withID zoneID: CKRecordZone.ID) async throws -> CKRecordZone
    func saveRecord(_ record: CKRecord) async throws -> CKRecord
    func fetchRecord(withID recordID: CKRecord.ID) async throws -> CKRecord
    func deleteRecord(withID recordID: CKRecord.ID) async throws
    func fetchRecordZoneChanges(
        inZoneWith zoneID: CKRecordZone.ID,
        sinceChangeTokenData: Data?,
        desiredKeys: [CKRecord.FieldKey]?,
        resultsLimit: Int?
    ) async throws -> CloudKitRawZoneChanges
}

protocol CloudKitZonePreparing {
    func prepareZone(named zoneName: String) async throws
}

final class DefaultCloudKitDatabaseWriter: CloudKitDatabaseWriting {
    private let database: CKDatabase

    init(containerIdentifier: String) {
        database = CKContainer(identifier: containerIdentifier).privateCloudDatabase
    }

    func saveZone(_ zone: CKRecordZone) async throws -> CKRecordZone {
        try await database.save(zone)
    }

    func fetchRecordZone(withID zoneID: CKRecordZone.ID) async throws -> CKRecordZone {
        try await database.recordZone(for: zoneID)
    }

    func saveRecord(_ record: CKRecord) async throws -> CKRecord {
        try await database.save(record)
    }

    func fetchRecord(withID recordID: CKRecord.ID) async throws -> CKRecord {
        try await database.record(for: recordID)
    }

    func deleteRecord(withID recordID: CKRecord.ID) async throws {
        _ = try await database.deleteRecord(withID: recordID)
    }

    func fetchRecordZoneChanges(
        inZoneWith zoneID: CKRecordZone.ID,
        sinceChangeTokenData: Data?,
        desiredKeys: [CKRecord.FieldKey]?,
        resultsLimit: Int?
    ) async throws -> CloudKitRawZoneChanges {
        let previousToken = try Self.serverChangeToken(from: sinceChangeTokenData)
        let changes = try await database.recordZoneChanges(
            inZoneWith: zoneID,
            since: previousToken,
            desiredKeys: desiredKeys,
            resultsLimit: resultsLimit
        )
        let modifiedRecords = try changes.modificationResultsByID.values
            .map { try $0.get().record }
            .sorted { $0.recordID.recordName < $1.recordID.recordName }
        let deletedRecords = changes.deletions
            .map { CloudKitRawDeletedRecord(recordID: $0.recordID, recordType: $0.recordType) }
            .sorted { $0.recordID.recordName < $1.recordID.recordName }
        return CloudKitRawZoneChanges(
            modifiedRecords: modifiedRecords,
            deletedRecords: deletedRecords,
            serverChangeTokenData: try Self.data(from: changes.changeToken),
            moreComing: changes.moreComing
        )
    }

    private static func serverChangeToken(from data: Data?) throws -> CKServerChangeToken? {
        guard let data else {
            return nil
        }
        return try NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
    }

    private static func data(from token: CKServerChangeToken?) throws -> Data? {
        guard let token else {
            return nil
        }
        return try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
    }
}

final class CloudKitZonePreparer: CloudKitZonePreparing {
    private let database: CloudKitDatabaseWriting
    private var preparedZoneNames = Set<String>()

    init(database: CloudKitDatabaseWriting) {
        self.database = database
    }

    func prepareZone(named zoneName: String) async throws {
        guard !preparedZoneNames.contains(zoneName) else {
            return
        }

        let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
        let zone = CKRecordZone(zoneID: zoneID)

        do {
            _ = try await database.saveZone(zone)
        } catch {
            let saveZoneError = error
            do {
                _ = try await database.fetchRecordZone(withID: zoneID)
            } catch {
                throw CloudKitOperationError(
                    operation: "Prepare CloudKit zone",
                    recordType: nil,
                    recordName: nil,
                    zoneName: zoneName,
                    fieldNames: [],
                    underlying: saveZoneError
                )
            }
        }
        preparedZoneNames.insert(zoneName)
    }
}

final class CloudKitDefaultSyncTransport: CloudKitSyncTransporting {
    private let database: CloudKitDatabaseWriting
    private let zonePreparer: CloudKitZonePreparing

    init(
        database: CloudKitDatabaseWriting,
        zonePreparer: CloudKitZonePreparing? = nil
    ) {
        self.database = database
        self.zonePreparer = zonePreparer ?? CloudKitZonePreparer(database: database)
    }

    convenience init(configuration: CloudKitConfiguration = CloudKitConfiguration()) throws {
        guard let containerIdentifier = configuration.containerIdentifier else {
            throw CloudKitDefaultSyncTransportError.notConfigured
        }

        let database = DefaultCloudKitDatabaseWriter(containerIdentifier: containerIdentifier)
        self.init(database: database)
    }

    func save(_ payload: CloudKitRecordPayload) async throws -> CloudKitSavedRecordMetadata {
        try await zonePreparer.prepareZone(named: payload.zoneName)
        let record = CloudKitRecordEncoder.record(from: payload)
        let savedRecord: CKRecord
        do {
            savedRecord = try await database.saveRecord(record)
        } catch {
            savedRecord = try await retryServerRecordChanged(
                error: error,
                operation: "Save CloudKit record",
                recordType: payload.recordType,
                recordName: payload.recordName,
                zoneName: payload.zoneName,
                fieldNames: payload.fields.keys.sorted()
            ) { serverRecord in
                CloudKitRecordEncoder.record(from: payload, updating: serverRecord)
            }
        }
        return CloudKitSavedRecordMetadata(
            recordChangeTag: savedRecord.recordChangeTag,
            lastKnownRecordJson: try CloudKitRecordPayloadSnapshot.json(from: payload)
        )
    }

    func saveAssets(_ payload: CloudKitAssetRecordPayload) async throws -> CloudKitSavedRecordMetadata {
        try await zonePreparer.prepareZone(named: payload.metadataPayload.zoneName)
        let record = CloudKitRecordEncoder.record(from: payload)
        let savedRecord: CKRecord
        do {
            savedRecord = try await database.saveRecord(record)
        } catch {
            savedRecord = try await retryServerRecordChanged(
                error: error,
                operation: "Save CloudKit asset record",
                recordType: payload.metadataPayload.recordType,
                recordName: payload.metadataPayload.recordName,
                zoneName: payload.metadataPayload.zoneName,
                fieldNames: payload.metadataPayload.fields.keys.sorted() + payload.assetFields.map(\.fieldName).sorted()
            ) { serverRecord in
                CloudKitRecordEncoder.record(from: payload, updating: serverRecord)
            }
        }
        return CloudKitSavedRecordMetadata(
            recordChangeTag: savedRecord.recordChangeTag,
            lastKnownRecordJson: try CloudKitRecordPayloadSnapshot.json(from: payload.metadataPayload)
        )
    }

    func delete(recordType _: String, recordName: String, zoneName: String) async throws {
        try await zonePreparer.prepareZone(named: zoneName)
        let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
        let recordID = CKRecord.ID(recordName: recordName, zoneID: zoneID)
        try await database.deleteRecord(withID: recordID)
    }

    func fetchRecord(
        entityType: CloudKitSyncEntityType,
        entityId: String,
        zoneName: String
    ) async throws -> CloudKitRecordPayload? {
        try await zonePreparer.prepareZone(named: zoneName)
        let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
        let recordID = CKRecord.ID(recordName: entityType.recordName(entityId: entityId), zoneID: zoneID)
        do {
            let record = try await database.fetchRecord(withID: recordID)
            return try CloudKitRecordDecoder.payload(from: record)
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    func fetchChanges(
        zoneName: String,
        sinceChangeTokenData: Data?,
        resultsLimit: Int?
    ) async throws -> CloudKitDownloadedChanges {
        try await zonePreparer.prepareZone(named: zoneName)
        let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
        let rawChanges = try await database.fetchRecordZoneChanges(
            inZoneWith: zoneID,
            sinceChangeTokenData: sinceChangeTokenData,
            desiredKeys: nil,
            resultsLimit: resultsLimit
        )
        let modifiedPayloads = try rawChanges.modifiedRecords.map(CloudKitRecordDecoder.payload(from:))
        let modifiedAssetRecords = zip(rawChanges.modifiedRecords, modifiedPayloads)
            .compactMap { pair -> CloudKitDownloadedAssetRecord? in
                let (record, payload) = pair
                let assetFields = CloudKitRecordDecoder.assetFields(from: record)
                guard !assetFields.isEmpty else {
                    return nil
                }
                return CloudKitDownloadedAssetRecord(payload: payload, assetFields: assetFields)
            }
        return CloudKitDownloadedChanges(
            modifiedPayloads: modifiedPayloads,
            modifiedAssetRecords: modifiedAssetRecords,
            deletedRecords: try rawChanges.deletedRecords.map {
                try CloudKitRecordIdentityDecoder.identity(
                    recordType: $0.recordType,
                    recordName: $0.recordID.recordName,
                    zoneName: $0.recordID.zoneID.zoneName
                )
            },
            serverChangeTokenData: rawChanges.serverChangeTokenData,
            moreComing: rawChanges.moreComing
        )
    }

    private func retryServerRecordChanged(
        error: Error,
        operation: String,
        recordType: String,
        recordName: String,
        zoneName: String,
        fieldNames: [String],
        updating: (CKRecord) -> CKRecord
    ) async throws -> CKRecord {
        guard let serverRecord = Self.serverRecordChangedServerRecord(from: error),
              serverRecord.recordType == recordType,
              serverRecord.recordID.recordName == recordName,
              serverRecord.recordID.zoneID.zoneName == zoneName
        else {
            throw CloudKitOperationError(
                operation: operation,
                recordType: recordType,
                recordName: recordName,
                zoneName: zoneName,
                fieldNames: fieldNames,
                underlying: error
            )
        }

        do {
            return try await database.saveRecord(updating(serverRecord))
        } catch {
            throw CloudKitOperationError(
                operation: "\(operation) existing record",
                recordType: recordType,
                recordName: recordName,
                zoneName: zoneName,
                fieldNames: fieldNames,
                underlying: error
            )
        }
    }

    private static func serverRecordChangedServerRecord(from error: Error) -> CKRecord? {
        let nsError = error as NSError
        if nsError.domain == CKError.errorDomain,
           nsError.code == CKError.Code.serverRecordChanged.rawValue,
           let serverRecord = nsError.userInfo[CKRecordChangedErrorServerRecordKey] as? CKRecord {
            return serverRecord
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            return serverRecordChangedServerRecord(from: underlying)
        }
        return nil
    }
}

enum CloudKitDefaultSyncTransportError: Error, Equatable {
    case notConfigured
}

struct CloudKitOperationError: LocalizedError {
    var operation: String
    var recordType: String?
    var recordName: String?
    var zoneName: String
    var fieldNames: [String]
    var underlying: Error

    var errorDescription: String? {
        var parts = [String]()
        parts.append("\(operation) failed.")
        if let recordType, let recordName {
            parts.append("Record: \(recordType) / \(recordName)")
        }
        parts.append("Zone: \(zoneName)")
        if !fieldNames.isEmpty {
            let renderedFieldNames = fieldNames.joined(separator: ", ")
            parts.append("Fields: \(renderedFieldNames)")
        }
        parts.append(CloudKitErrorDescription.describe(underlying))
        return parts.joined(separator: "\n")
    }
}

enum CloudKitErrorDescription {
    static func describe(_ error: Error) -> String {
        describe(error as NSError, depth: 0)
    }

    private static func describe(_ error: NSError, depth: Int) -> String {
        var parts = [String]()
        let codeName = cloudKitCodeName(domain: error.domain, code: error.code)
        let codeSummary = codeName.map { "\(error.domain) \(error.code) (\($0))" }
            ?? "\(error.domain) \(error.code)"
        parts.append(codeSummary)

        if !error.localizedDescription.isEmpty {
            parts.append(error.localizedDescription)
        }
        if let reason = error.localizedFailureReason, !reason.isEmpty {
            parts.append(reason)
        }
        if let suggestion = error.localizedRecoverySuggestion, !suggestion.isEmpty {
            parts.append(suggestion)
        }

        let extraUserInfo = error.userInfo
            .filter { key, _ in
                ![
                    NSLocalizedDescriptionKey,
                    NSLocalizedFailureReasonErrorKey,
                    NSLocalizedRecoverySuggestionErrorKey,
                    NSUnderlyingErrorKey
                ].contains(key)
            }
            .compactMap { key, value -> String? in
                guard let rendered = renderUserInfoValue(value) else {
                    return nil
                }
                return "\(key): \(rendered)"
            }
            .sorted()

        if !extraUserInfo.isEmpty {
            parts.append(extraUserInfo.joined(separator: "\n"))
        }

        if depth == 0,
           let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            parts.append("Underlying: \(describe(underlying, depth: depth + 1))")
        }

        return parts.joined(separator: "\n")
    }

    private static func cloudKitCodeName(domain: String, code: Int) -> String? {
        guard domain == CKError.errorDomain,
              let cloudKitCode = CKError.Code(rawValue: code) else {
            return nil
        }

        switch cloudKitCode {
        case .internalError:
            return "internalError"
        case .partialFailure:
            return "partialFailure"
        case .networkUnavailable:
            return "networkUnavailable"
        case .networkFailure:
            return "networkFailure"
        case .badContainer:
            return "badContainer"
        case .serviceUnavailable:
            return "serviceUnavailable"
        case .requestRateLimited:
            return "requestRateLimited"
        case .missingEntitlement:
            return "missingEntitlement"
        case .notAuthenticated:
            return "notAuthenticated"
        case .permissionFailure:
            return "permissionFailure"
        case .unknownItem:
            return "unknownItem"
        case .invalidArguments:
            return "invalidArguments"
        case .resultsTruncated:
            return "resultsTruncated"
        case .serverRecordChanged:
            return "serverRecordChanged"
        case .serverRejectedRequest:
            return "serverRejectedRequest"
        case .assetFileNotFound:
            return "assetFileNotFound"
        case .assetFileModified:
            return "assetFileModified"
        case .incompatibleVersion:
            return "incompatibleVersion"
        case .constraintViolation:
            return "constraintViolation"
        case .operationCancelled:
            return "operationCancelled"
        case .changeTokenExpired:
            return "changeTokenExpired"
        case .batchRequestFailed:
            return "batchRequestFailed"
        case .zoneBusy:
            return "zoneBusy"
        case .badDatabase:
            return "badDatabase"
        case .quotaExceeded:
            return "quotaExceeded"
        case .zoneNotFound:
            return "zoneNotFound"
        case .limitExceeded:
            return "limitExceeded"
        case .userDeletedZone:
            return "userDeletedZone"
        case .tooManyParticipants:
            return "tooManyParticipants"
        case .alreadyShared:
            return "alreadyShared"
        case .referenceViolation:
            return "referenceViolation"
        case .managedAccountRestricted:
            return "managedAccountRestricted"
        case .participantMayNeedVerification:
            return "participantMayNeedVerification"
        case .serverResponseLost:
            return "serverResponseLost"
        case .assetNotAvailable:
            return "assetNotAvailable"
        case .accountTemporarilyUnavailable:
            return "accountTemporarilyUnavailable"
        case .participantAlreadyInvited:
            return "participantAlreadyInvited"
        @unknown default:
            return "unknownCloudKitCode"
        }
    }

    private static func renderUserInfoValue(_ value: Any) -> String? {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        case let date as Date:
            return ISO8601DateFormatter().string(from: date)
        case let url as URL:
            return url.absoluteString
        default:
            return nil
        }
    }
}

struct CloudKitRawZoneChanges {
    var modifiedRecords: [CKRecord]
    var deletedRecords: [CloudKitRawDeletedRecord]
    var serverChangeTokenData: Data?
    var moreComing: Bool
}

struct CloudKitRawDeletedRecord {
    var recordID: CKRecord.ID
    var recordType: String
}
