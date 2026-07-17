import XCTest
@testable import PrivateMoments

final class AIReviewMomentDocumentTests: XCTestCase {
    func testTimelinePreviewUsesTitleAndFirstBodyParagraphWithoutMetadata() {
        let document = AIReviewMomentDocument.parse(
            """
            # 把“想做什么”往里再问一层

            5 moments · 0 comments

            这一周记录不多，但线索很集中：身体、休息、注意力，以及一个想法从形式回到真正想达到什么。

            ## Keywords
            - 注意力
            - 休息

            Range: 2026-05-17 to 2026-05-24
            """
        )

        XCTAssertEqual(document.title, "把“想做什么”往里再问一层")
        XCTAssertEqual(document.timelinePreview, "这一周记录不多，但线索很集中：身体、休息、注意力，以及一个想法从形式回到真正想达到什么。")
        XCTAssertFalse(document.timelinePreview.contains("5 moments"))
        XCTAssertFalse(document.timelinePreview.contains("Range:"))
        XCTAssertFalse(document.timelinePreview.contains("## Keywords"))
    }

    func testParsesBodySectionsKeywordsAndRangeForDetail() {
        let document = AIReviewMomentDocument.parse(
            """
            # Weekly Review

            3 moments · 2 comments

            A quiet week with one clear thread.

            ## Rhythm
            Most entries clustered at night.

            ## Direction
            - Keep the capture surface small.
            - Move metadata out of the main reading flow.

            ## Keywords
            - Capture
            - Recovery

            Range: 2026-05-17 to 2026-05-24
            """
        )

        XCTAssertEqual(document.metadataSummary, "3 moments · 2 comments")
        XCTAssertEqual(document.rangeText, "2026-05-17 to 2026-05-24")
        XCTAssertEqual(document.keywords, ["Capture", "Recovery"])
        XCTAssertEqual(document.sections.map(\.title), ["Overview", "Rhythm", "Direction"])
        XCTAssertEqual(document.sections[0].lines, ["A quiet week with one clear thread."])
        XCTAssertEqual(document.sections[2].lines, ["Keep the capture surface small.", "Move metadata out of the main reading flow."])
    }
}
