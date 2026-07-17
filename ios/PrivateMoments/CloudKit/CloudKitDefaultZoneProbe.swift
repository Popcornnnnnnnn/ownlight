import CloudKit
import Foundation

struct CloudKitDefaultZoneProbeResult: Equatable {
    var recordName: String
    var recordChangeTag: String?
    var recordIDStrategy: RecordIDStrategy

    enum RecordIDStrategy: String, Equatable {
        case custom = "custom"
        case automatic = "automatic"
    }
}

final class CloudKitDefaultZoneProbe {
    private let database: CloudKitDatabaseWriting
    private let now: () -> Date
    private let idGenerator: () -> String

    init(
        database: CloudKitDatabaseWriting,
        now: @escaping () -> Date = Date.init,
        idGenerator: @escaping () -> String = { UUID().uuidString }
    ) {
        self.database = database
        self.now = now
        self.idGenerator = idGenerator
    }

    convenience init(
        configuration: CloudKitConfiguration = CloudKitConfiguration(),
        now: @escaping () -> Date = Date.init,
        idGenerator: @escaping () -> String = { UUID().uuidString }
    ) throws {
        guard let containerIdentifier = configuration.containerIdentifier else {
            throw CloudKitDefaultSyncTransportError.notConfigured
        }

        self.init(
            database: DefaultCloudKitDatabaseWriter(containerIdentifier: containerIdentifier),
            now: now,
            idGenerator: idGenerator
        )
    }

    func run() async throws -> CloudKitDefaultZoneProbeResult {
        let recordName = "pm.probe.\(idGenerator())"
        let customRecord = makeProbeRecord(
            recordID: CKRecord.ID(recordName: recordName),
            purpose: "default-zone-smoke-custom"
        )

        do {
            return try await saveAndCleanup(
                customRecord,
                strategy: .custom
            )
        } catch {
            let customRecordError = error
            let automaticRecord = makeProbeRecord(
                recordID: CKRecord.ID(),
                purpose: "default-zone-smoke-automatic"
            )

            do {
                return try await saveAndCleanup(
                    automaticRecord,
                    strategy: .automatic
                )
            } catch {
                throw CloudKitDefaultZoneProbeError(
                    customRecordError: customRecordError,
                    automaticRecordError: error
                )
            }
        }
    }

    private func makeProbeRecord(recordID: CKRecord.ID, purpose: String) -> CKRecord {
        let record = CKRecord(recordType: "PMCloudKitProbe", recordID: recordID)
        record["purpose"] = purpose as CKRecordValue
        record["createdAt"] = now() as CKRecordValue
        return record
    }

    private func saveAndCleanup(
        _ record: CKRecord,
        strategy: CloudKitDefaultZoneProbeResult.RecordIDStrategy
    ) async throws -> CloudKitDefaultZoneProbeResult {
        let savedRecord: CKRecord
        do {
            savedRecord = try await database.saveRecord(record)
        } catch {
            throw CloudKitOperationError(
                operation: "Save CloudKit default-zone probe",
                recordType: record.recordType,
                recordName: record.recordID.recordName,
                zoneName: record.recordID.zoneID.zoneName,
                fieldNames: ["createdAt", "purpose"],
                underlying: error
            )
        }

        try? await database.deleteRecord(withID: savedRecord.recordID)
        return CloudKitDefaultZoneProbeResult(
            recordName: savedRecord.recordID.recordName,
            recordChangeTag: savedRecord.recordChangeTag,
            recordIDStrategy: strategy
        )
    }
}

struct CloudKitDefaultZoneProbeError: LocalizedError {
    let customRecordError: Error
    let automaticRecordError: Error

    var errorDescription: String? {
        "CloudKit private database is not accepting writes right now."
    }

    var failureReason: String? {
        "Both a custom record ID and a CloudKit-generated record ID failed in the default private zone."
    }

    var recoverySuggestion: String? {
        "Your local Ownlight data was not uploaded. Check iCloud status, try again later, or use the diagnostic details when contacting Apple Developer Support."
    }

    var diagnosticDescription: String {
        """
        CloudKit default-zone probe failed for both custom and automatic record IDs.

        Custom record ID:
        \(customRecordError.localizedDescription)

        Automatic record ID:
        \(automaticRecordError.localizedDescription)
        """
    }
}
