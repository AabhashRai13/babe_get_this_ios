import Foundation

/// Groups a timestamp into a human-readable period, like a messaging app groups
/// messages by date (Android `core/util/DateGrouping.kt`).
enum TimePeriod: CaseIterable, Sendable {
    case today
    case yesterday
    case lastWeek
    case thisMonth
    case older

    /// `now` is a parameter so tests can pin it: the yesterday, 7-day and same-month
    /// boundaries otherwise mean something different on the 1st than on the 20th.
    static func of(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> TimePeriod {
        if calendar.isDate(date, inSameDayAs: now) { return .today }

        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return .yesterday
        }

        // Exclusive, like Android's `date.after(sevenDaysAgo)`.
        if let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: now), date > sevenDaysAgo {
            return .lastWeek
        }

        if calendar.component(.year, from: now) == calendar.component(.year, from: date),
           calendar.component(.month, from: now) == calendar.component(.month, from: date) {
            return .thisMonth
        }

        return .older
    }

    var displayName: String {
        switch self {
        case .today: "Today"
        case .yesterday: "Yesterday"
        case .lastWeek: "Last 7 Days"
        case .thisMonth: "This Month"
        case .older: "Older"
        }
    }
}
