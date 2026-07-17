import XCTest
@testable import PrivateMoments

final class MomentDateFormatterTests: XCTestCase {
    func testTimelineAndDateTimeLabelsUseTwentyFourHourClock() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let now = date(year: 2026, month: 6, day: 3, hour: 14, minute: 0, calendar: calendar)
        let momentTime = date(year: 2026, month: 6, day: 3, hour: 12, minute: 5, calendar: calendar)

        XCTAssertEqual(
            MomentDateFormatter.timelineLabel(
                for: momentTime,
                now: now,
                calendar: calendar,
                language: .english
            ),
            "Today 12:05"
        )
        XCTAssertEqual(
            MomentDateFormatter.clockTimeTitle(for: momentTime, calendar: calendar),
            "12:05"
        )
        XCTAssertFalse(
            MomentDateFormatter.mediumDateTimeTitle(for: momentTime, calendar: calendar, language: .english)
                .localizedCaseInsensitiveContains("PM")
        )
    }

    private func date(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
        calendar: Calendar
    ) -> Date {
        calendar.date(
            from: DateComponents(
                timeZone: calendar.timeZone,
                year: year,
                month: month,
                day: day,
                hour: hour,
                minute: minute
            )
        )!
    }
}
