import XCTest
@testable import PrivateMoments

final class TimelineAISummaryControlStateTests: XCTestCase {
    func testFirstInFlightSummaryRequestShowsGeneratingState() {
        let state = TimelineAISummaryControlState.resolve(
            summary: nil,
            isRequestInFlight: true
        )

        XCTAssertEqual(state, .summarizing)
        XCTAssertEqual(state?.title(language: .english), "Generating")
        XCTAssertEqual(state?.title(language: .simplifiedChinese), "正在生成")
    }

    func testInFlightSummaryRequestWithExistingContentShowsRegeneratingState() {
        let summary = TimelineAISummary(
            id: "summary-1",
            postId: "post-1",
            mediaId: "media-1",
            status: "ready",
            format: nil,
            language: nil,
            overview: "Existing summary",
            keyPoints: [],
            sections: [],
            summaryText: nil,
            documentTitle: nil,
            oneLiner: nil,
            documentBlocks: [],
            inputTranscriptLength: nil,
            inputDurationSeconds: nil,
            inputTokenCount: nil,
            outputTokenCount: nil,
            totalTokenCount: nil,
            promptVersion: "media-summary-v4",
            provider: nil,
            model: nil,
            errorCode: nil,
            errorMessage: nil,
            createdAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 1_010),
            deletedAt: nil
        )

        let state = TimelineAISummaryControlState.resolve(
            summary: summary,
            isRequestInFlight: true
        )

        XCTAssertEqual(state, .regenerating)
    }
}
