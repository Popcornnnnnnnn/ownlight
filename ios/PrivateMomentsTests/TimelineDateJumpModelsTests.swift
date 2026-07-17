import XCTest
@testable import PrivateMoments

final class TimelineDateJumpModelsTests: XCTestCase {
    private var calendar: Calendar!
    private var now: Date!

    override func setUp() {
        super.setUp()
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        self.calendar = calendar
        self.now = date(year: 2026, month: 4, day: 30, hour: 12)
    }

    func testEmptyItemsReturnNoGroups() {
        let groups = TimelineDateJumpBuilder.groups(from: [], now: now, calendar: calendar)

        XCTAssertTrue(groups.isEmpty)
    }

    func testGroupsVisibleItemsByMonthAndDayNewestFirst() {
        let newestApril = item(id: "april-newest", occurredAt: date(year: 2026, month: 4, day: 29, hour: 18))
        let olderSameDay = item(id: "april-older-same-day", occurredAt: date(year: 2026, month: 4, day: 29, hour: 9))
        let olderApril = item(id: "april-older-day", occurredAt: date(year: 2026, month: 4, day: 2, hour: 7))
        let march = item(id: "march-visible", occurredAt: date(year: 2026, month: 3, day: 31, hour: 22))

        let groups = TimelineDateJumpBuilder.groups(
            from: [olderApril, march, olderSameDay, newestApril],
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(groups.map(\.title), ["April 2026", "March 2026"])
        XCTAssertEqual(groups.map(\.anchorItemID), ["april-newest", "march-visible"])
        XCTAssertEqual(groups[0].items.map(\.rawItemID), ["april-newest", "april-older-same-day", "april-older-day"])
        XCTAssertEqual(groups[0].days.map(\.targetItemID), ["april-newest", "april-older-day"])
        XCTAssertEqual(groups[0].days[0].items.map(\.rawItemID), ["april-newest", "april-older-same-day"])
        XCTAssertEqual(groups[1].days.map(\.targetItemID), ["march-visible"])
    }

    func testBuilderReadsOnlyItemsPassedByCaller() {
        let visible = item(id: "visible-favorite", occurredAt: date(year: 2026, month: 4, day: 20, hour: 12), isFavorite: true)
        let hiddenByCaller = item(id: "hidden-non-favorite", occurredAt: date(year: 2026, month: 5, day: 2, hour: 12), isFavorite: false)
        let filteredItems = [visible, hiddenByCaller].filter { $0.moment?.post.isFavorite == true }

        let groups = TimelineDateJumpBuilder.groups(from: filteredItems, now: now, calendar: calendar)

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.title, "April 2026")
        XCTAssertEqual(groups.first?.anchorItemID, "visible-favorite")
        XCTAssertFalse(groups.flatMap(\.items).contains { $0.rawItemID == hiddenByCaller.rawItemID })
    }

    func testDayJumpLabelsAreDateLanguageOnly() {
        let dates = [
            date(year: 2026, month: 4, day: 30, hour: 8),
            date(year: 2026, month: 4, day: 29, hour: 8),
            date(year: 2026, month: 5, day: 1, hour: 8),
            date(year: 2026, month: 4, day: 27, hour: 8),
            date(year: 2026, month: 4, day: 10, hour: 8),
            date(year: 2025, month: 12, day: 31, hour: 8),
        ]

        let labels = dates.map { MomentDateFormatter.dayJumpTitle(for: $0, now: now, calendar: calendar) }

        XCTAssertEqual(labels, ["Today", "Yesterday", "Tomorrow", "Monday", "Apr 10", "Dec 31, 2025"])
        labels.forEach { assertCountFreeLabel($0) }
    }

    func testGroupedDayLabelsAreCountFree() {
        let groups = TimelineDateJumpBuilder.groups(
            from: [
                item(id: "today-a", occurredAt: date(year: 2026, month: 4, day: 30, hour: 9)),
                item(id: "today-b", occurredAt: date(year: 2026, month: 4, day: 30, hour: 8)),
            ],
            now: now,
            calendar: calendar
        )

        let labels = groups.flatMap(\.days).map(\.title)
        XCTAssertEqual(labels, ["Today"])
        labels.forEach { assertCountFreeLabel($0) }
    }

    func testTimelineFeedBuilderFiltersAndSortsOnceForRendering() {
        let newestMoment = timelineItem(id: "moment-new", occurredAt: date(year: 2026, month: 4, day: 30, hour: 13))
        let olderMoment = timelineItem(id: "moment-old", occurredAt: date(year: 2026, month: 4, day: 29, hour: 9))
        let deletedMoment = timelineItem(
            id: "moment-deleted",
            occurredAt: date(year: 2026, month: 4, day: 30, hour: 14),
            deletedAt: date(year: 2026, month: 4, day: 30, hour: 15)
        )
        let visibleCheckIn = checkInFeedEntry(
            id: "checkin-visible",
            occurredAt: date(year: 2026, month: 4, day: 30, hour: 12),
            showInTimeline: true
        )
        let hiddenCheckIn = checkInFeedEntry(
            id: "checkin-hidden",
            occurredAt: date(year: 2026, month: 4, day: 30, hour: 11),
            showInTimeline: false
        )

        let feedItems = TimelineFeedBuilder.timelineFeedItems(
            moments: [olderMoment, deletedMoment, newestMoment],
            checkIns: [hiddenCheckIn, visibleCheckIn]
        )

        XCTAssertEqual(feedItems.map(\.id), [
            "moment-moment-new",
            "checkin-checkin-visible",
            "moment-moment-old",
        ])
    }

    private func assertCountFreeLabel(_ label: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(label.localizedCaseInsensitiveContains("moment"), "Label includes moment wording: \(label)", file: file, line: line)
        XCTAssertNil(label.range(of: #"\b\d+\s+moments?\b"#, options: [.regularExpression, .caseInsensitive]), "Label includes count wording: \(label)", file: file, line: line)
        XCTAssertNil(label.range(of: #"\(\s*\d+\s*\)$"#, options: .regularExpression), "Label ends with a parenthesized count: \(label)", file: file, line: line)
    }

    private func item(
        id: String,
        occurredAt: Date,
        isFavorite: Bool = false,
        media: [TimelineMedia] = []
    ) -> MomentFeedItem {
        .moment(timelineItem(id: id, occurredAt: occurredAt, isFavorite: isFavorite, media: media))
    }

    private func timelineItem(
        id: String,
        occurredAt: Date,
        isFavorite: Bool = false,
        media: [TimelineMedia] = [],
        deletedAt: Date? = nil
    ) -> TimelineItem {
        TimelineItem(
            post: TimelinePost(
                id: id,
                text: "Fixture \(id)",
                isFavorite: isFavorite,
                isPinned: false,
                pinnedAt: nil,
                aiTagProcessedAt: nil,
                tagsUserEditedAt: nil,
                occurredAt: occurredAt,
                localCreatedAt: occurredAt,
                localUpdatedAt: occurredAt,
                localEditedAt: nil,
                serverVersion: nil,
                syncStatus: "synced",
                deletedAt: deletedAt
            ),
            media: media,
            comments: [],
            aiSummaries: [],
            tags: []
        )
    }

    private func checkInFeedEntry(id: String, occurredAt: Date, showInTimeline: Bool) -> CheckInFeedEntry {
        let item = CheckInItem(
            id: "item-\(id)",
            name: "Check-in \(id)",
            symbolName: "checkmark",
            colorHex: "#4477AA",
            recordMode: .oncePerDay,
            timeVisualization: .none,
            dayStartHour: 0,
            activeWeekdays: [1, 2, 3, 4, 5, 6, 7],
            sortOrder: 0,
            defaultShowInTimeline: showInTimeline,
            tagId: nil,
            createdAt: occurredAt,
            updatedAt: occurredAt,
            archivedAt: nil,
            deletedAt: nil,
            syncStatus: "synced"
        )
        let entry = CheckInEntry(
            id: id,
            itemId: item.id,
            occurredAt: occurredAt,
            note: "",
            showInTimeline: showInTimeline,
            createdAt: occurredAt,
            updatedAt: occurredAt,
            deletedAt: nil,
            syncStatus: "synced"
        )
        return CheckInFeedEntry(entry: entry, item: item, tag: nil, media: [])
    }

    private func date(year: Int, month: Int, day: Int, hour: Int) -> Date {
        let components = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour
        )
        return components.date!
    }
}
