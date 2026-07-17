import Foundation

enum CloudKitRecordPayloadSnapshot {
    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    static func json(from payload: CloudKitRecordPayload) throws -> String {
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

    private static func jsonValue(from value: CloudKitRecordFieldValue) -> Any {
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
            return dateFormatter.string(from: value)
        case .stringList(let value):
            return value
        }
    }
}
