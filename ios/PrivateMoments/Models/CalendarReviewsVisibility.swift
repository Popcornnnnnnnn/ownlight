import Foundation

enum CalendarReviewsVisibility {
    static func shouldShowReviewsButton(
        aiAnalysisEnabled: Bool,
        hasWeeklyReviews: Bool
    ) -> Bool {
        aiAnalysisEnabled || hasWeeklyReviews
    }
}
