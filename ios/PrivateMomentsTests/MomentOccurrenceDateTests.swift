import XCTest
@testable import PrivateMoments

final class MomentOccurrenceDateTests: XCTestCase {
    func testClampsFutureDatesToNow() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let future = now.addingTimeInterval(3_600)

        XCTAssertEqual(MomentOccurrenceDate.clampedToNow(future, now: now), now)
    }

    func testLeavesPastAndCurrentDatesUnchanged() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let past = now.addingTimeInterval(-3_600)

        XCTAssertEqual(MomentOccurrenceDate.clampedToNow(past, now: now), past)
        XCTAssertEqual(MomentOccurrenceDate.clampedToNow(now, now: now), now)
    }

    func testLocalDatabaseDateDecoderAcceptsFractionalSeconds() {
        XCTAssertNotNil(LocalDatabase.decodeDate("2026-06-02T17:55:55Z"))
        XCTAssertNotNil(LocalDatabase.decodeDate("2026-06-02T17:55:55.344Z"))
    }
}
