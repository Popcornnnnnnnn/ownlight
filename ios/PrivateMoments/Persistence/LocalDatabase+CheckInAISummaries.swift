import Foundation
import SQLite3

extension LocalDatabase {
    func fetchCheckInAISummaries(includeDeleted: Bool = false) throws -> [CheckInAISummary] {
        let statement = try prepare(
            """
            SELECT id, entryId, mediaId, status, format, language, overview, keyPointsJson,
                   sectionsJson, summaryText, inputTranscriptLength, inputDurationSeconds,
                   inputTokenCount, outputTokenCount, totalTokenCount,
                   promptVersion, provider, model, errorCode, errorMessage, createdAt, updatedAt, deletedAt,
                   documentTitle, oneLiner, documentBlocksJson
            FROM local_checkin_ai_summaries
            WHERE (? = 1 OR deletedAt IS NULL)
            ORDER BY updatedAt DESC, createdAt DESC
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(includeDeleted ? 1 : 0, to: 1, in: statement)

        var summaries: [CheckInAISummary] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            summaries.append(try checkInAISummary(statement))
        }
        return summaries
    }

    func fetchCheckInAISummary(id: String) throws -> CheckInAISummary? {
        let statement = try prepare(
            """
            SELECT id, entryId, mediaId, status, format, language, overview, keyPointsJson,
                   sectionsJson, summaryText, inputTranscriptLength, inputDurationSeconds,
                   inputTokenCount, outputTokenCount, totalTokenCount,
                   promptVersion, provider, model, errorCode, errorMessage, createdAt, updatedAt, deletedAt,
                   documentTitle, oneLiner, documentBlocksJson
            FROM local_checkin_ai_summaries
            WHERE id = ?
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(id, to: 1, in: statement)
        if sqlite3_step(statement) == SQLITE_ROW {
            return try checkInAISummary(statement)
        }

        return nil
    }

    func fetchCheckInAISummary(mediaId: String) throws -> CheckInAISummary? {
        let statement = try prepare(
            """
            SELECT id, entryId, mediaId, status, format, language, overview, keyPointsJson,
                   sectionsJson, summaryText, inputTranscriptLength, inputDurationSeconds,
                   inputTokenCount, outputTokenCount, totalTokenCount,
                   promptVersion, provider, model, errorCode, errorMessage, createdAt, updatedAt, deletedAt,
                   documentTitle, oneLiner, documentBlocksJson
            FROM local_checkin_ai_summaries
            WHERE mediaId = ?
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(mediaId, to: 1, in: statement)
        if sqlite3_step(statement) == SQLITE_ROW {
            return try checkInAISummary(statement)
        }

        return nil
    }

    func upsertCheckInAISummary(_ summary: CheckInAISummary) throws {
        let statement = try prepare(
            """
            INSERT INTO local_checkin_ai_summaries
                (id, entryId, mediaId, status, format, language, overview, keyPointsJson,
                 sectionsJson, summaryText, inputTranscriptLength, inputDurationSeconds,
                 inputTokenCount, outputTokenCount, totalTokenCount,
                 promptVersion, provider, model, errorCode, errorMessage, createdAt, updatedAt, deletedAt,
                 documentTitle, oneLiner, documentBlocksJson)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(mediaId) DO UPDATE SET
                id = excluded.id,
                entryId = excluded.entryId,
                status = excluded.status,
                format = excluded.format,
                language = excluded.language,
                overview = excluded.overview,
                keyPointsJson = excluded.keyPointsJson,
                sectionsJson = excluded.sectionsJson,
                summaryText = excluded.summaryText,
                inputTranscriptLength = excluded.inputTranscriptLength,
                inputDurationSeconds = excluded.inputDurationSeconds,
                inputTokenCount = excluded.inputTokenCount,
                outputTokenCount = excluded.outputTokenCount,
                totalTokenCount = excluded.totalTokenCount,
                promptVersion = excluded.promptVersion,
                provider = excluded.provider,
                model = excluded.model,
                errorCode = excluded.errorCode,
                errorMessage = excluded.errorMessage,
                createdAt = excluded.createdAt,
                updatedAt = excluded.updatedAt,
                deletedAt = excluded.deletedAt,
                documentTitle = excluded.documentTitle,
                oneLiner = excluded.oneLiner,
                documentBlocksJson = excluded.documentBlocksJson
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(summary.id, to: 1, in: statement)
        try bind(summary.entryId, to: 2, in: statement)
        try bind(summary.mediaId, to: 3, in: statement)
        try bind(summary.status, to: 4, in: statement)
        try bind(summary.format, to: 5, in: statement)
        try bind(summary.language, to: 6, in: statement)
        try bind(summary.overview, to: 7, in: statement)
        try bind(checkInAISummaryJSONString(summary.keyPoints), to: 8, in: statement)
        try bind(checkInAISummaryJSONString(summary.sections), to: 9, in: statement)
        try bind(summary.summaryText, to: 10, in: statement)
        try bind(summary.inputTranscriptLength, to: 11, in: statement)
        try bind(summary.inputDurationSeconds, to: 12, in: statement)
        try bind(summary.inputTokenCount, to: 13, in: statement)
        try bind(summary.outputTokenCount, to: 14, in: statement)
        try bind(summary.totalTokenCount, to: 15, in: statement)
        try bind(summary.promptVersion, to: 16, in: statement)
        try bind(summary.provider, to: 17, in: statement)
        try bind(summary.model, to: 18, in: statement)
        try bind(summary.errorCode, to: 19, in: statement)
        try bind(summary.errorMessage, to: 20, in: statement)
        try bind(summary.createdAt, to: 21, in: statement)
        try bind(summary.updatedAt, to: 22, in: statement)
        try bind(summary.deletedAt, to: 23, in: statement)
        try bind(summary.documentTitle, to: 24, in: statement)
        try bind(summary.oneLiner, to: 25, in: statement)
        try bind(checkInAISummaryJSONString(summary.documentBlocks), to: 26, in: statement)
        try stepDone(statement)
    }

    func checkInAISummary(_ statement: OpaquePointer) throws -> CheckInAISummary {
        CheckInAISummary(
            id: try text(statement, 0),
            entryId: try text(statement, 1),
            mediaId: try text(statement, 2),
            status: try text(statement, 3),
            format: optionalText(statement, 4),
            language: optionalText(statement, 5),
            overview: optionalText(statement, 6),
            keyPoints: decodeJSONStringArray(optionalText(statement, 7)),
            sections: decodeSummarySections(optionalText(statement, 8)),
            summaryText: optionalText(statement, 9),
            documentTitle: optionalText(statement, 23),
            oneLiner: optionalText(statement, 24),
            documentBlocks: decodeSummaryBlocks(optionalText(statement, 25)),
            inputTranscriptLength: optionalInt(statement, 10),
            inputDurationSeconds: optionalDouble(statement, 11),
            inputTokenCount: optionalInt(statement, 12),
            outputTokenCount: optionalInt(statement, 13),
            totalTokenCount: optionalInt(statement, 14),
            promptVersion: optionalText(statement, 15) ?? "media-summary-v1",
            provider: optionalText(statement, 16),
            model: optionalText(statement, 17),
            errorCode: optionalText(statement, 18),
            errorMessage: optionalText(statement, 19),
            createdAt: try date(statement, 20),
            updatedAt: try date(statement, 21),
            deletedAt: try optionalDate(statement, 22)
        )
    }

    private func checkInAISummaryJSONString<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONEncoder().encode(value)
        return String(decoding: data, as: UTF8.self)
    }

    private func decodeJSONStringArray(_ value: String?) -> [String] {
        guard let value,
              let data = value.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }

        return decoded
    }

    private func decodeSummarySections(_ value: String?) -> [TimelineAISummarySection] {
        guard let value,
              let data = value.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([TimelineAISummarySection].self, from: data) else {
            return []
        }

        return decoded
    }

    private func decodeSummaryBlocks(_ value: String?) -> [TimelineAISummaryBlock] {
        guard let value,
              let data = value.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([TimelineAISummaryBlock].self, from: data) else {
            return []
        }

        return decoded
    }
}
