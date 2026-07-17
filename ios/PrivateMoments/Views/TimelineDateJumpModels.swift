import Foundation

struct TimelineDateJumpMonthGroup: Identifiable {
    let id: String
    let title: String
    let monthStart: Date
    let anchorItemID: String
    let days: [TimelineDateJumpDayGroup]
    let items: [MomentFeedItem]
}

struct TimelineDateJumpDayGroup: Identifiable {
    let id: String
    let title: String
    let dayStart: Date
    let targetItemID: String
    let items: [MomentFeedItem]
}

enum TimelineDateJumpBuilder {
    static func groups(
        from items: [MomentFeedItem],
        now: Date = Date(),
        calendar: Calendar = .current,
        language: AppResolvedLanguage = .english
    ) -> [TimelineDateJumpMonthGroup] {
        let sortedItems = items.sorted { lhs, rhs in
            if lhs.occurredAt == rhs.occurredAt {
                return lhs.sortKey > rhs.sortKey
            }

            return lhs.occurredAt > rhs.occurredAt
        }

        return groupsFromPresortedItems(from: sortedItems, now: now, calendar: calendar, language: language)
    }

    static func groupsFromPresortedItems(
        from sortedItems: [MomentFeedItem],
        now: Date = Date(),
        calendar: Calendar = .current,
        language: AppResolvedLanguage = .english
    ) -> [TimelineDateJumpMonthGroup] {
        let groupedByMonth = Dictionary(grouping: sortedItems) { item in
            monthStart(for: item.occurredAt, calendar: calendar)
        }

        return groupedByMonth
            .compactMap { monthStart, monthItems -> TimelineDateJumpMonthGroup? in
                guard let anchorItem = monthItems.first else {
                    return nil
                }

                let days = dayGroups(from: monthItems, now: now, calendar: calendar, language: language)
                return TimelineDateJumpMonthGroup(
                    id: monthID(for: monthStart, calendar: calendar),
                    title: MomentDateFormatter.monthTitle(for: monthStart, calendar: calendar, language: language),
                    monthStart: monthStart,
                    anchorItemID: anchorItem.rawItemID,
                    days: days,
                    items: monthItems
                )
            }
            .sorted { lhs, rhs in
                lhs.monthStart > rhs.monthStart
            }
    }

    private static func dayGroups(
        from items: [MomentFeedItem],
        now: Date,
        calendar: Calendar,
        language: AppResolvedLanguage
    ) -> [TimelineDateJumpDayGroup] {
        let groupedByDay = Dictionary(grouping: items) { item in
            calendar.startOfDay(for: item.occurredAt)
        }

        return groupedByDay
            .compactMap { dayStart, dayItems -> TimelineDateJumpDayGroup? in
                guard let targetItem = dayItems.first else {
                    return nil
                }

                return TimelineDateJumpDayGroup(
                    id: dayID(for: dayStart, calendar: calendar),
                    title: MomentDateFormatter.dayJumpTitle(for: dayStart, now: now, calendar: calendar, language: language),
                    dayStart: dayStart,
                    targetItemID: targetItem.rawItemID,
                    items: dayItems
                )
            }
            .sorted { lhs, rhs in
                lhs.dayStart > rhs.dayStart
            }
    }

    private static func monthStart(for date: Date, calendar: Calendar) -> Date {
        let components = calendar.dateComponents([.era, .year, .month], from: date)
        return calendar.date(from: components) ?? calendar.startOfDay(for: date)
    }

    private static func monthID(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.era, .year, .month], from: date)
        let era = components.era ?? 1
        let year = components.year ?? 0
        let month = components.month ?? 0
        return String(format: "date-jump-month-%04d-%04d-%02d", era, year, month)
    }

    private static func dayID(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.era, .year, .month, .day], from: date)
        let era = components.era ?? 1
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "date-jump-day-%04d-%04d-%02d-%02d", era, year, month, day)
    }
}

enum TimelineFeedBuilder {
    static func checkInFeedEntries(
        items: [CheckInItem],
        entries: [CheckInEntry],
        media: [CheckInMedia],
        tags: [TimelineTag]
    ) -> [CheckInFeedEntry] {
        let itemById = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        let tagById = Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0) })
        let mediaByEntryId = Dictionary(grouping: media.filter { $0.deletedAt == nil }, by: \.entryId)

        return entries.compactMap { entry in
            guard let item = itemById[entry.itemId],
                  entry.deletedAt == nil,
                  item.deletedAt == nil else {
                return nil
            }

            return CheckInFeedEntry(
                entry: entry,
                item: item,
                tag: item.tagId.flatMap { tagById[$0] },
                media: mediaByEntryId[entry.id] ?? []
            )
        }
    }

    static func timelineFeedItems(
        moments: [TimelineItem],
        checkIns: [CheckInFeedEntry]
    ) -> [MomentFeedItem] {
        let momentItems = moments
            .filter { $0.post.deletedAt == nil }
            .map(MomentFeedItem.moment)
        let checkInItems = checkIns
            .filter { $0.entry.showInTimeline }
            .map(MomentFeedItem.checkIn)

        return (momentItems + checkInItems).sorted { lhs, rhs in
            if lhs.occurredAt == rhs.occurredAt {
                return lhs.sortKey > rhs.sortKey
            }

            return lhs.occurredAt > rhs.occurredAt
        }
    }
}
