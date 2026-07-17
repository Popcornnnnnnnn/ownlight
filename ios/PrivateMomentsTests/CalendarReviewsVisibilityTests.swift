import XCTest
@testable import PrivateMoments

final class CalendarReviewsVisibilityTests: XCTestCase {
    func testHidesReviewsButtonWhenAIIsOffAndThereAreNoReviews() {
        XCTAssertFalse(CalendarReviewsVisibility.shouldShowReviewsButton(
            aiAnalysisEnabled: false,
            hasWeeklyReviews: false
        ))
    }

    func testShowsReviewsButtonWhenAIIsOnOrHistoryExists() {
        XCTAssertTrue(CalendarReviewsVisibility.shouldShowReviewsButton(
            aiAnalysisEnabled: true,
            hasWeeklyReviews: false
        ))
        XCTAssertTrue(CalendarReviewsVisibility.shouldShowReviewsButton(
            aiAnalysisEnabled: false,
            hasWeeklyReviews: true
        ))
    }
}
