import Foundation

struct CloudKitIncomingRecordContext: Equatable {
    var entityType: CloudKitSyncEntityType
    var entityId: String
    var payload: CloudKitRecordPayload?
    var cloudDeletedAt: Date?
    var localRecordState: CloudKitRecordState?
    var hasPendingLocalChange: Bool

    init(
        entityType: CloudKitSyncEntityType,
        entityId: String,
        payload: CloudKitRecordPayload? = nil,
        cloudDeletedAt: Date? = nil,
        localRecordState: CloudKitRecordState?,
        hasPendingLocalChange: Bool
    ) {
        self.entityType = entityType
        self.entityId = entityId
        self.payload = payload
        self.cloudDeletedAt = cloudDeletedAt
        self.localRecordState = localRecordState
        self.hasPendingLocalChange = hasPendingLocalChange
    }

    init(
        payload: CloudKitRecordPayload,
        cloudDeletedAt: Date? = nil,
        localRecordState: CloudKitRecordState?,
        hasPendingLocalChange: Bool
    ) {
        self.init(
            entityType: payload.entityType,
            entityId: payload.entityId,
            payload: payload,
            cloudDeletedAt: cloudDeletedAt,
            localRecordState: localRecordState,
            hasPendingLocalChange: hasPendingLocalChange
        )
    }
}

enum CloudKitIncomingRecordDecision: Equatable {
    case applyUpsert(CloudKitRecordPayload)
    case applyDelete(entityType: CloudKitSyncEntityType, entityId: String, cloudDeletedAt: Date?)
    case deferForLocalPendingChange
    case ignoreAlreadyApplied
    case ignoreInvalidIncomingRecord
}

enum CloudKitIncomingRecordPolicy {
    static func decision(for context: CloudKitIncomingRecordContext) -> CloudKitIncomingRecordDecision {
        guard payloadMatchesIncomingIdentity(context) else {
            return .ignoreInvalidIncomingRecord
        }

        if context.hasPendingLocalChange {
            return .deferForLocalPendingChange
        }

        if let deletedAt = context.cloudDeletedAt {
            return .applyDelete(
                entityType: context.entityType,
                entityId: context.entityId,
                cloudDeletedAt: deletedAt
            )
        }

        if payloadMatchesLastKnownSnapshot(context) {
            return .ignoreAlreadyApplied
        }

        if let deletedAt = context.payload?.deletedAt {
            return .applyDelete(
                entityType: context.entityType,
                entityId: context.entityId,
                cloudDeletedAt: deletedAt
            )
        }

        guard let payload = context.payload else {
            return .ignoreInvalidIncomingRecord
        }

        return .applyUpsert(payload)
    }

    private static func payloadMatchesIncomingIdentity(_ context: CloudKitIncomingRecordContext) -> Bool {
        guard let payload = context.payload else {
            return true
        }

        return payload.entityType == context.entityType && payload.entityId == context.entityId
    }

    private static func payloadMatchesLastKnownSnapshot(_ context: CloudKitIncomingRecordContext) -> Bool {
        guard
            let payload = context.payload,
            let lastKnownRecordJson = context.localRecordState?.lastKnownRecordJson,
            let incomingSnapshotJson = try? CloudKitRecordPayloadSnapshot.json(from: payload)
        else {
            return false
        }

        return lastKnownRecordJson == incomingSnapshotJson
    }
}

private extension CloudKitRecordPayload {
    var deletedAt: Date? {
        guard case .date(let value) = fields["deletedAt"] else {
            return nil
        }
        return value
    }
}
