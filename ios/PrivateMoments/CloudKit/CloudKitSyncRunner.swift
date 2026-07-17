import Foundation

protocol CloudKitSyncPayloadResolving {
    func payload(for change: CloudKitPendingChange) throws -> CloudKitRecordPayload?
    func assetPayload(for change: CloudKitPendingChange) throws -> CloudKitAssetRecordPayload?
}

protocol CloudKitSyncTransporting {
    func save(_ payload: CloudKitRecordPayload) async throws -> CloudKitSavedRecordMetadata
    func saveAssets(_ payload: CloudKitAssetRecordPayload) async throws -> CloudKitSavedRecordMetadata
    func delete(recordType: String, recordName: String, zoneName: String) async throws
    func fetchRecord(entityType: CloudKitSyncEntityType, entityId: String, zoneName: String) async throws -> CloudKitRecordPayload?
    func fetchChanges(zoneName: String, sinceChangeTokenData: Data?, resultsLimit: Int?) async throws -> CloudKitDownloadedChanges
}

protocol CloudKitIncomingRecordApplying {
    func applyUpsert(_ payload: CloudKitRecordPayload, downloadedAt: Date) throws
    func applyAssets(_ assetRecord: CloudKitDownloadedAssetRecord, downloadedAt: Date) throws
    func applyDelete(
        entityType: CloudKitSyncEntityType,
        entityId: String,
        cloudDeletedAt: Date?,
        downloadedAt: Date
    ) throws
}

extension CloudKitIncomingRecordApplying {
    func applyAssets(_: CloudKitDownloadedAssetRecord, downloadedAt _: Date) throws {}
}

struct CloudKitSavedRecordMetadata: Equatable {
    var recordChangeTag: String?
    var lastKnownRecordJson: String?
}

struct CloudKitSyncRunSummary: Equatable {
    var claimed: Int
    var saved: Int
    var deleted: Int
    var failed: Int
}

struct CloudKitPullRunSummary: Equatable {
    var fetchedModified: Int
    var fetchedDeleted: Int
    var appliedUpserts: Int
    var appliedDeletes: Int
    var deferred: Int
    var ignored: Int
    var failed: Int
    var moreComing: Bool
}

final class CloudKitSyncRunner {
    private let database: LocalDatabase
    private let payloadResolver: CloudKitSyncPayloadResolving
    private let transport: CloudKitSyncTransporting
    private let incomingRecordApplier: CloudKitIncomingRecordApplying
    private let now: () -> Date
    private let retryDelay: TimeInterval

    init(
        database: LocalDatabase,
        payloadResolver: CloudKitSyncPayloadResolving,
        transport: CloudKitSyncTransporting,
        incomingRecordApplier: CloudKitIncomingRecordApplying,
        now: @escaping () -> Date = Date.init,
        retryDelay: TimeInterval = 60
    ) {
        self.database = database
        self.payloadResolver = payloadResolver
        self.transport = transport
        self.incomingRecordApplier = incomingRecordApplier
        self.now = now
        self.retryDelay = retryDelay
    }

    func runOnce(limit: Int) async -> CloudKitSyncRunSummary {
        let runAt = now()
        let changes: [CloudKitPendingChange]
        do {
            changes = try database.claimDueCloudKitPendingChanges(limit: limit, now: runAt)
        } catch {
            return .init(claimed: 0, saved: 0, deleted: 0, failed: 0)
        }

        var summary = CloudKitSyncRunSummary(
            claimed: changes.count,
            saved: 0,
            deleted: 0,
            failed: 0
        )

        for change in changes.sorted(by: Self.shouldUploadBefore) {
            do {
                switch change.changeKind {
                case .upsert:
                    try await save(change, runAt: runAt)
                    summary.saved += 1
                case .assetUpload:
                    try await saveAssets(change, runAt: runAt)
                    summary.saved += 1
                case .delete:
                    try await delete(change, runAt: runAt)
                    summary.deleted += 1
                }
                _ = try database.markCloudKitPendingChangeFinished(id: change.id, now: runAt)
            } catch {
                summary.failed += 1
                _ = try? database.markCloudKitPendingChangeFailed(
                    id: change.id,
                    errorCode: "cloudkit_sync_failed",
                    errorMessage: String(describing: error),
                    retryAfter: retryDelay,
                    now: runAt
                )
            }
        }

        return summary
    }

    func pullOnce(
        zoneName: String = CloudKitSyncDefaults.zoneName,
        stateScope: String? = nil,
        resultsLimit: Int?
    ) async -> CloudKitPullRunSummary {
        let runAt = now()
        let syncStateScope = stateScope ?? zoneName
        var summary = CloudKitPullRunSummary(
            fetchedModified: 0,
            fetchedDeleted: 0,
            appliedUpserts: 0,
            appliedDeletes: 0,
            deferred: 0,
            ignored: 0,
            failed: 0,
            moreComing: false
        )

        let previousState: CloudKitSyncState
        do {
            previousState = try markPullStarted(scope: syncStateScope, runAt: runAt)
        } catch {
            summary.failed = 1
            return summary
        }

        let downloadedChanges: CloudKitDownloadedChanges
        do {
            downloadedChanges = try await transport.fetchChanges(
                zoneName: zoneName,
                sinceChangeTokenData: previousState.serverChangeTokenData,
                resultsLimit: resultsLimit
            )
        } catch {
            summary.failed = 1
            _ = try? database.markCloudKitSyncStateFailed(
                scope: syncStateScope,
                errorCode: "cloudkit_pull_failed",
                errorMessage: Self.diagnosticDescription(for: error),
                now: runAt
            )
            return summary
        }

        summary.fetchedModified = downloadedChanges.modifiedPayloads.count
        summary.fetchedDeleted = downloadedChanges.deletedRecords.count
        summary.moreComing = downloadedChanges.moreComing
        let assetRecordsByLocalStateId = Dictionary(
            uniqueKeysWithValues: downloadedChanges.modifiedAssetRecords.map {
                (
                    $0.payload.entityType.localRecordStateId(entityId: $0.payload.entityId),
                    $0
                )
            }
        )

        do {
            for payload in downloadedChanges.modifiedPayloads.sorted(by: Self.shouldApplyBefore) {
                do {
                    let decision = try incomingDecision(for: payload)
                    let localStateId = payload.entityType.localRecordStateId(entityId: payload.entityId)
                    try await apply(
                        decision,
                        downloadedAt: runAt,
                        assetRecord: assetRecordsByLocalStateId[localStateId],
                        summary: &summary
                    )
                } catch {
                    throw CloudKitSyncRunnerError.incomingRecordApplyFailed(
                        recordType: payload.recordType,
                        recordName: payload.recordName,
                        entityType: payload.entityType.rawValue,
                        entityId: payload.entityId,
                        underlying: error
                    )
                }
            }

            for deletedRecord in downloadedChanges.deletedRecords {
                do {
                    let decision = try incomingDecision(for: deletedRecord, cloudDeletedAt: runAt)
                    try await apply(decision, downloadedAt: runAt, assetRecord: nil, summary: &summary)
                } catch {
                    throw CloudKitSyncRunnerError.incomingRecordApplyFailed(
                        recordType: deletedRecord.recordType,
                        recordName: deletedRecord.recordName,
                        entityType: deletedRecord.entityType.rawValue,
                        entityId: deletedRecord.entityId,
                        underlying: error
                    )
                }
            }
        } catch {
            summary.failed += 1
            _ = try? database.markCloudKitSyncStateFailed(
                scope: syncStateScope,
                errorCode: "cloudkit_pull_failed",
                errorMessage: Self.diagnosticDescription(for: error),
                now: runAt
            )
            return summary
        }

        do {
            let nextToken = downloadedChanges.serverChangeTokenData ?? previousState.serverChangeTokenData
            try markPullFinished(
                scope: syncStateScope,
                runAt: runAt,
                serverChangeTokenData: summary.deferred == 0 ? nextToken : previousState.serverChangeTokenData
            )
        } catch {
            summary.failed += 1
        }

        return summary
    }

    private func save(_ change: CloudKitPendingChange, runAt: Date) async throws {
        guard let payload = try payloadResolver.payload(for: change) else {
            throw CloudKitSyncRunnerError.missingPayload(change.entityType.rawValue, change.entityId)
        }

        let metadata = try await transport.save(payload)
        try markUploadApplied(payload: payload, metadata: metadata, uploadedAt: runAt)
    }

    private func saveAssets(_ change: CloudKitPendingChange, runAt: Date) async throws {
        guard let assetPayload = try payloadResolver.assetPayload(for: change) else {
            throw CloudKitSyncRunnerError.missingPayload(change.entityType.rawValue, change.entityId)
        }

        let metadata = try await transport.saveAssets(assetPayload)
        try markUploadApplied(
            payload: assetPayload.metadataPayload,
            metadata: metadata,
            uploadedAt: runAt
        )
    }

    private func markUploadApplied(
        payload: CloudKitRecordPayload,
        metadata: CloudKitSavedRecordMetadata,
        uploadedAt: Date
    ) throws {
        var state = try database.fetchCloudKitRecordState(
            entityType: payload.entityType,
            entityId: payload.entityId
        ) ?? CloudKitRecordState(
            entityType: payload.entityType,
            entityId: payload.entityId,
            lastMappedAt: uploadedAt,
            zoneName: payload.zoneName
        )
        state.recordChangeTag = metadata.recordChangeTag
        state.lastKnownRecordJson = metadata.lastKnownRecordJson
        state.cloudDeletedAt = nil
        state.lastUploadedAt = uploadedAt
        state.zoneName = payload.zoneName
        try database.upsertCloudKitRecordState(state)
    }

    private func delete(_ change: CloudKitPendingChange, runAt: Date) async throws {
        let state = try database.fetchCloudKitRecordState(
            entityType: change.entityType,
            entityId: change.entityId
        ) ?? CloudKitRecordState(
            entityType: change.entityType,
            entityId: change.entityId,
            lastMappedAt: runAt
        )

        try await transport.delete(
            recordType: state.recordType,
            recordName: state.recordName,
            zoneName: state.zoneName
        )

        var deletedState = state
        deletedState.cloudDeletedAt = runAt
        deletedState.lastUploadedAt = runAt
        try database.upsertCloudKitRecordState(deletedState)
    }

    private func incomingDecision(for payload: CloudKitRecordPayload) throws -> CloudKitIncomingRecordDecision {
        let localRecordState = try database.fetchCloudKitRecordState(
            entityType: payload.entityType,
            entityId: payload.entityId
        )
        let hasPendingLocalChange = try database.hasUnfinishedCloudKitPendingChange(
            entityType: payload.entityType,
            entityId: payload.entityId
        )
        return CloudKitIncomingRecordPolicy.decision(for: .init(
            payload: payload,
            localRecordState: localRecordState,
            hasPendingLocalChange: hasPendingLocalChange
        ))
    }

    private func incomingDecision(
        for deletedRecord: CloudKitDeletedRecordIdentity,
        cloudDeletedAt: Date
    ) throws -> CloudKitIncomingRecordDecision {
        let localRecordState = try database.fetchCloudKitRecordState(
            entityType: deletedRecord.entityType,
            entityId: deletedRecord.entityId
        )
        let hasPendingLocalChange = try database.hasUnfinishedCloudKitPendingChange(
            entityType: deletedRecord.entityType,
            entityId: deletedRecord.entityId
        )
        return CloudKitIncomingRecordPolicy.decision(for: .init(
            entityType: deletedRecord.entityType,
            entityId: deletedRecord.entityId,
            cloudDeletedAt: cloudDeletedAt,
            localRecordState: localRecordState,
            hasPendingLocalChange: hasPendingLocalChange
        ))
    }

    private func apply(
        _ decision: CloudKitIncomingRecordDecision,
        downloadedAt: Date,
        assetRecord: CloudKitDownloadedAssetRecord?,
        summary: inout CloudKitPullRunSummary
    ) async throws {
        switch decision {
        case .applyUpsert(let payload):
            try await applyUpsertWithMissingParentRecovery(
                payload,
                downloadedAt: downloadedAt,
                assetRecord: assetRecord,
                summary: &summary
            )
        case .applyDelete(let entityType, let entityId, let cloudDeletedAt):
            try incomingRecordApplier.applyDelete(
                entityType: entityType,
                entityId: entityId,
                cloudDeletedAt: cloudDeletedAt,
                downloadedAt: downloadedAt
            )
            try markRemoteDeleteApplied(
                entityType: entityType,
                entityId: entityId,
                cloudDeletedAt: cloudDeletedAt,
                downloadedAt: downloadedAt
            )
            summary.appliedDeletes += 1
        case .deferForLocalPendingChange:
            summary.deferred += 1
        case .ignoreAlreadyApplied, .ignoreInvalidIncomingRecord:
            summary.ignored += 1
        }
    }

    private func applyUpsertWithMissingParentRecovery(
        _ payload: CloudKitRecordPayload,
        downloadedAt: Date,
        assetRecord: CloudKitDownloadedAssetRecord?,
        summary: inout CloudKitPullRunSummary,
        recoveryDepth: Int = 0
    ) async throws {
        do {
            try applyUpsert(payload, downloadedAt: downloadedAt, assetRecord: assetRecord, summary: &summary)
        } catch CloudKitLocalRecordApplyError.missingParent(let parentDescription) {
            guard recoveryDepth < 4,
                  let parentIdentity = Self.parentIdentity(from: parentDescription),
                  parentIdentity.entityType != payload.entityType || parentIdentity.entityId != payload.entityId
            else {
                throw CloudKitLocalRecordApplyError.missingParent(parentDescription)
            }

            guard let parentPayload = try await transport.fetchRecord(
                entityType: parentIdentity.entityType,
                entityId: parentIdentity.entityId,
                zoneName: payload.zoneName
            ) else {
                if Self.canIgnoreUnresolvableMissingParent(
                    childEntityType: payload.entityType,
                    parentEntityType: parentIdentity.entityType
                ) {
                    summary.ignored += 1
                    return
                }
                throw CloudKitLocalRecordApplyError.missingParent(parentDescription)
            }

            let canIgnoreChildIfParentStaysUnavailable = Self.canIgnoreUnresolvableMissingParent(
                childEntityType: payload.entityType,
                parentEntityType: parentIdentity.entityType
            )

            do {
                let parentDecision = try incomingDecision(for: parentPayload)
                switch parentDecision {
                case .applyUpsert(let fetchedPayload):
                    try await applyUpsertWithMissingParentRecovery(
                        fetchedPayload,
                        downloadedAt: downloadedAt,
                        assetRecord: nil,
                        summary: &summary,
                        recoveryDepth: recoveryDepth + 1
                    )
                case .applyDelete(let entityType, let entityId, let cloudDeletedAt):
                    try incomingRecordApplier.applyDelete(
                        entityType: entityType,
                        entityId: entityId,
                        cloudDeletedAt: cloudDeletedAt,
                        downloadedAt: downloadedAt
                    )
                    try markRemoteDeleteApplied(
                        entityType: entityType,
                        entityId: entityId,
                        cloudDeletedAt: cloudDeletedAt,
                        downloadedAt: downloadedAt
                    )
                    summary.appliedDeletes += 1
                    summary.deferred += 1
                    return
                case .deferForLocalPendingChange:
                    summary.deferred += 1
                    return
                case .ignoreInvalidIncomingRecord:
                    if canIgnoreChildIfParentStaysUnavailable {
                        summary.ignored += 1
                        return
                    }
                    summary.ignored += 1
                case .ignoreAlreadyApplied:
                    break
                }

                try applyUpsert(payload, downloadedAt: downloadedAt, assetRecord: assetRecord, summary: &summary)
            } catch {
                if canIgnoreChildIfParentStaysUnavailable {
                    summary.ignored += 1
                    return
                }
                throw error
            }
        }
    }

    private func applyUpsert(
        _ payload: CloudKitRecordPayload,
        downloadedAt: Date,
        assetRecord: CloudKitDownloadedAssetRecord?,
        summary: inout CloudKitPullRunSummary
    ) throws {
        try incomingRecordApplier.applyUpsert(payload, downloadedAt: downloadedAt)
        if let assetRecord {
            try incomingRecordApplier.applyAssets(assetRecord, downloadedAt: downloadedAt)
        }
        try markRemoteUpsertApplied(payload, downloadedAt: downloadedAt)
        summary.appliedUpserts += 1
    }

    private func markRemoteUpsertApplied(
        _ payload: CloudKitRecordPayload,
        downloadedAt: Date
    ) throws {
        var state = try database.fetchCloudKitRecordState(
            entityType: payload.entityType,
            entityId: payload.entityId
        ) ?? CloudKitRecordState(
            entityType: payload.entityType,
            entityId: payload.entityId,
            lastMappedAt: downloadedAt,
            zoneName: payload.zoneName
        )
        state.lastKnownRecordJson = try CloudKitRecordPayloadSnapshot.json(from: payload)
        state.cloudDeletedAt = nil
        state.lastDownloadedAt = downloadedAt
        state.zoneName = payload.zoneName
        try database.upsertCloudKitRecordState(state)
    }

    private func markRemoteDeleteApplied(
        entityType: CloudKitSyncEntityType,
        entityId: String,
        cloudDeletedAt: Date?,
        downloadedAt: Date
    ) throws {
        var state = try database.fetchCloudKitRecordState(
            entityType: entityType,
            entityId: entityId
        ) ?? CloudKitRecordState(
            entityType: entityType,
            entityId: entityId,
            lastMappedAt: downloadedAt
        )
        state.cloudDeletedAt = cloudDeletedAt ?? downloadedAt
        state.lastDownloadedAt = downloadedAt
        try database.upsertCloudKitRecordState(state)
    }

    private func markPullStarted(scope: String, runAt: Date) throws -> CloudKitSyncState {
        var state = try database.fetchCloudKitSyncState(scope: scope) ?? CloudKitSyncState(
            scope: scope,
            serverChangeTokenData: nil,
            lastAccountStatus: nil,
            lastSyncStartedAt: nil,
            lastSyncFinishedAt: nil,
            lastErrorCode: nil,
            updatedAt: runAt
        )
        state.lastSyncStartedAt = runAt
        state.updatedAt = runAt
        try database.upsertCloudKitSyncState(state)
        return state
    }

    private func markPullFinished(
        scope: String,
        runAt: Date,
        serverChangeTokenData: Data?
    ) throws {
        var state = try database.fetchCloudKitSyncState(scope: scope) ?? CloudKitSyncState(
            scope: scope,
            serverChangeTokenData: nil,
            lastAccountStatus: nil,
            lastSyncStartedAt: runAt,
            lastSyncFinishedAt: nil,
            lastErrorCode: nil,
            updatedAt: runAt
        )
        state.serverChangeTokenData = serverChangeTokenData
        state.lastSyncStartedAt = runAt
        state.lastSyncFinishedAt = runAt
        state.lastErrorCode = nil
        state.lastErrorMessage = nil
        state.updatedAt = runAt
        try database.upsertCloudKitSyncState(state)
    }

    private static func shouldApplyBefore(
        _ lhs: CloudKitRecordPayload,
        _ rhs: CloudKitRecordPayload
    ) -> Bool {
        let lhsRank = incomingApplyRank(for: lhs.entityType)
        let rhsRank = incomingApplyRank(for: rhs.entityType)
        if lhsRank != rhsRank {
            return lhsRank < rhsRank
        }
        if lhs.entityType.rawValue != rhs.entityType.rawValue {
            return lhs.entityType.rawValue < rhs.entityType.rawValue
        }
        return lhs.entityId < rhs.entityId
    }

    private static func shouldUploadBefore(
        _ lhs: CloudKitPendingChange,
        _ rhs: CloudKitPendingChange
    ) -> Bool {
        let lhsRank = incomingApplyRank(for: lhs.entityType)
        let rhsRank = incomingApplyRank(for: rhs.entityType)
        if lhsRank != rhsRank {
            return lhsRank < rhsRank
        }
        let lhsKindRank = uploadChangeKindRank(for: lhs.changeKind)
        let rhsKindRank = uploadChangeKindRank(for: rhs.changeKind)
        if lhsKindRank != rhsKindRank {
            return lhsKindRank < rhsKindRank
        }
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }
        return lhs.id < rhs.id
    }

    private static func uploadChangeKindRank(for changeKind: CloudKitPendingChangeKind) -> Int {
        switch changeKind {
        case .upsert, .delete:
            return 0
        case .assetUpload:
            return 1
        }
    }

    private static func incomingApplyRank(for entityType: CloudKitSyncEntityType) -> Int {
        switch entityType {
        case .moment, .tag, .checkInItem, .preference:
            return 0
        case .media, .comment, .tagAlias, .checkInEntry, .draft:
            return 1
        case .postTag, .checkInMedia:
            return 2
        case .aiSummary, .checkInAISummary, .weeklyReview:
            return 3
        }
    }

    private static func parentIdentity(from description: String) -> (entityType: CloudKitSyncEntityType, entityId: String)? {
        let parts = description.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[1].isEmpty else {
            return nil
        }

        let entityType: CloudKitSyncEntityType?
        switch String(parts[0]) {
        case "post":
            entityType = .moment
        default:
            entityType = CloudKitSyncEntityType(rawValue: String(parts[0]))
        }

        guard let entityType else {
            return nil
        }

        return (entityType, String(parts[1]))
    }

    private static func canIgnoreUnresolvableMissingParent(
        childEntityType: CloudKitSyncEntityType,
        parentEntityType: CloudKitSyncEntityType
    ) -> Bool {
        switch (childEntityType, parentEntityType) {
        case (.postTag, .moment),
             (.postTag, .tag),
             (.tagAlias, .tag),
             (.aiSummary, .moment),
             (.aiSummary, .media),
             (.checkInAISummary, .checkInEntry),
             (.checkInAISummary, .checkInMedia):
            return true
        default:
            return false
        }
    }

    private static func diagnosticDescription(for error: Error) -> String {
        if let runnerError = error as? CloudKitSyncRunnerError {
            return runnerError.diagnosticDescription
        }
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription,
           !description.isEmpty {
            return description
        }
        return String(describing: error)
    }
}

private enum CloudKitSyncRunnerError: Error {
    case missingPayload(String, String)
    case incomingRecordApplyFailed(
        recordType: String,
        recordName: String,
        entityType: String,
        entityId: String,
        underlying: Error
    )

    var diagnosticDescription: String {
        switch self {
        case .missingPayload(let entityType, let entityId):
            return "Missing local payload for \(entityType) / \(entityId)."
        case .incomingRecordApplyFailed(let recordType, let recordName, let entityType, let entityId, let underlying):
            let underlyingDescription: String
            if let localizedError = underlying as? LocalizedError,
               let description = localizedError.errorDescription,
               !description.isEmpty {
                underlyingDescription = description
            } else {
                underlyingDescription = String(describing: underlying)
            }
            return [
                "Apply CloudKit incoming record failed.",
                "Record: \(recordType) / \(recordName)",
                "Entity: \(entityType) / \(entityId)",
                "Underlying: \(underlyingDescription)"
            ].joined(separator: "\n")
        }
    }
}
