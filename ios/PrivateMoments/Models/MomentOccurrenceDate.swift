import Foundation

enum MomentOccurrenceDate {
    static func clampedToNow(_ date: Date, now: Date = Date()) -> Date {
        min(date, now)
    }
}
