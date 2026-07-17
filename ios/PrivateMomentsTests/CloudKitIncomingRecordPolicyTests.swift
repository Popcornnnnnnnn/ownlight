import XCTest
@testable import PrivateMoments

final class CloudKitIncomingRecordPolicyTests: XCTestCase {
    func testAppliesRemoteUpsertWhenThereIsNoLocalPendingChange() {
        let payload = momentPayload(id: "post-1", text: "Remote text")
        let context = CloudKitIncomingRecordContext(
            payload: payload,
            localRecordState: nil,
            hasPendingLocalChange: false
        )

        let decision = CloudKitIncomingRecordPolicy.decision(for: context)

        XCTAssertEqual(decision, .applyUpsert(payload))
    }

    func testDefersRemoteUpsertWhenLocalChangeIsPending() {
        let payload = momentPayload(id: "post-1", text: "Remote text")
        let context = CloudKitIncomingRecordContext(
            payload: payload,
            localRecordState: nil,
            hasPendingLocalChange: true
        )

        let decision = CloudKitIncomingRecordPolicy.decision(for: context)

        XCTAssertEqual(decision, .deferForLocalPendingChange)
    }

    func testAppliesRemoteDeleteWhenNoLocalChangeIsPending() {
        let deletedAt = Date(timeIntervalSince1970: 7_200)
        let context = CloudKitIncomingRecordContext(
            entityType: .moment,
            entityId: "post-1",
            cloudDeletedAt: deletedAt,
            localRecordState: nil,
            hasPendingLocalChange: false
        )

        let decision = CloudKitIncomingRecordPolicy.decision(for: context)

        XCTAssertEqual(
            decision,
            .applyDelete(entityType: .moment, entityId: "post-1", cloudDeletedAt: deletedAt)
        )
    }

    func testDefersRemoteDeleteWhenLocalChangeIsPending() {
        let context = CloudKitIncomingRecordContext(
            entityType: .moment,
            entityId: "post-1",
            cloudDeletedAt: Date(timeIntervalSince1970: 7_300),
            localRecordState: nil,
            hasPendingLocalChange: true
        )

        let decision = CloudKitIncomingRecordPolicy.decision(for: context)

        XCTAssertEqual(decision, .deferForLocalPendingChange)
    }

    func testPayloadDeletedAtIsTreatedAsRemoteDelete() {
        let deletedAt = Date(timeIntervalSince1970: 7_400)
        var payload = momentPayload(id: "post-1", text: "Deleted remotely")
        payload.fields["deletedAt"] = .date(deletedAt)
        let context = CloudKitIncomingRecordContext(
            payload: payload,
            localRecordState: nil,
            hasPendingLocalChange: false
        )

        let decision = CloudKitIncomingRecordPolicy.decision(for: context)

        XCTAssertEqual(
            decision,
            .applyDelete(entityType: .moment, entityId: "post-1", cloudDeletedAt: deletedAt)
        )
    }

    func testIgnoresPayloadThatDoesNotMatchIncomingIdentity() {
        let payload = momentPayload(id: "post-1", text: "Remote text")
        let context = CloudKitIncomingRecordContext(
            entityType: .comment,
            entityId: "comment-1",
            payload: payload,
            cloudDeletedAt: nil,
            localRecordState: nil,
            hasPendingLocalChange: false
        )

        let decision = CloudKitIncomingRecordPolicy.decision(for: context)

        XCTAssertEqual(decision, .ignoreInvalidIncomingRecord)
    }

    func testIgnoresPayloadThatMatchesLastKnownRecordSnapshot() throws {
        let payload = momentPayload(id: "post-1", text: "Already applied")
        let state = CloudKitRecordState(
            entityType: .moment,
            entityId: "post-1",
            lastKnownRecordJson: try snapshotJson(for: payload),
            lastMappedAt: Date(timeIntervalSince1970: 7_500)
        )
        let context = CloudKitIncomingRecordContext(
            payload: payload,
            localRecordState: state,
            hasPendingLocalChange: false
        )

        let decision = CloudKitIncomingRecordPolicy.decision(for: context)

        XCTAssertEqual(decision, .ignoreAlreadyApplied)
    }

    private func momentPayload(id: String, text: String) -> CloudKitRecordPayload {
        CloudKitRecordPayload(
            entityType: .moment,
            entityId: id,
            fields: [
                "text": .string(text),
                "localUpdatedAt": .date(Date(timeIntervalSince1970: 7_000))
            ]
        )
    }

    private func snapshotJson(for payload: CloudKitRecordPayload) throws -> String {
        let fields = payload.fields.reduce(into: [String: Any]()) { result, element in
            result[element.key] = jsonValue(from: element.value)
        }
        let snapshot: [String: Any] = [
            "recordType": payload.recordType,
            "recordName": payload.recordName,
            "zoneName": payload.zoneName,
            "fields": fields
        ]
        let data = try JSONSerialization.data(withJSONObject: snapshot, options: [.sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func jsonValue(from value: CloudKitRecordFieldValue) -> Any {
        switch value {
        case .string(let value):
            return value
        case .int(let value):
            return value
        case .double(let value):
            return value
        case .bool(let value):
            return value
        case .date(let value):
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            return formatter.string(from: value)
        case .stringList(let value):
            return value
        }
    }
}
