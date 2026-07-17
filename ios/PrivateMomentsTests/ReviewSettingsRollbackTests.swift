import XCTest
@testable import PrivateMoments

@MainActor
final class ReviewSettingsRollbackTests: XCTestCase {
    private var savedAutoWeeklyReviewEnabled = false
    private var savedPublishWeeklyReviewToMoments = false

    override func setUp() {
        super.setUp()
        savedAutoWeeklyReviewEnabled = AppSettings.autoWeeklyReviewEnabled
        savedPublishWeeklyReviewToMoments = AppSettings.publishWeeklyReviewToMoments
    }

    override func tearDown() {
        AppSettings.autoWeeklyReviewEnabled = savedAutoWeeklyReviewEnabled
        AppSettings.publishWeeklyReviewToMoments = savedPublishWeeklyReviewToMoments
        super.tearDown()
    }

    func testAutoWeeklyTogglePersistsLocallyWithoutServerRollback() {
        AppSettings.autoWeeklyReviewEnabled = false
        AppSettings.publishWeeklyReviewToMoments = true

        let store = TimelineStore()

        store.setAutoWeeklyReviewEnabled(true)

        XCTAssertTrue(store.autoWeeklyReviewEnabled)
        XCTAssertTrue(store.publishWeeklyReviewToMoments)
        XCTAssertTrue(AppSettings.autoWeeklyReviewEnabled)
        XCTAssertTrue(AppSettings.publishWeeklyReviewToMoments)
        XCTAssertNil(store.errorMessage)
    }

    func testPublishWeeklyTogglePersistsLocallyWithoutServerRollback() {
        AppSettings.autoWeeklyReviewEnabled = true
        AppSettings.publishWeeklyReviewToMoments = false

        let store = TimelineStore()

        store.setPublishWeeklyReviewToMoments(true)

        XCTAssertTrue(store.autoWeeklyReviewEnabled)
        XCTAssertTrue(store.publishWeeklyReviewToMoments)
        XCTAssertTrue(AppSettings.autoWeeklyReviewEnabled)
        XCTAssertTrue(AppSettings.publishWeeklyReviewToMoments)
        XCTAssertNil(store.errorMessage)
    }

    func testDisablingAutoWeeklyReviewAlsoDisablesPublishToTimeline() {
        AppSettings.autoWeeklyReviewEnabled = true
        AppSettings.publishWeeklyReviewToMoments = true

        let store = TimelineStore()

        store.setAutoWeeklyReviewEnabled(false)

        XCTAssertFalse(store.autoWeeklyReviewEnabled)
        XCTAssertFalse(store.publishWeeklyReviewToMoments)
        XCTAssertFalse(AppSettings.autoWeeklyReviewEnabled)
        XCTAssertFalse(AppSettings.publishWeeklyReviewToMoments)
        XCTAssertNil(store.errorMessage)
    }
}
