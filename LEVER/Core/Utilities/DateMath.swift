import Foundation

enum DateMath {
    static var calendar: Calendar { Calendar.current }

    /// Whole calendar days between two dates (negative when `to` is in the past).
    static func days(from: Date, to: Date, calendar: Calendar = .current) -> Int {
        let start = calendar.startOfDay(for: from)
        let end = calendar.startOfDay(for: to)
        return calendar.dateComponents([.day], from: start, to: end).day ?? 0
    }

    static func adding(days: Int, to date: Date, calendar: Calendar = .current) -> Date? {
        calendar.date(byAdding: .day, value: days, to: date)
    }

    static func adding(months: Int, to date: Date, calendar: Calendar = .current) -> Date? {
        calendar.date(byAdding: .month, value: months, to: date)
    }

    static func isWithin(days: Int, of date: Date, from now: Date = .now) -> Bool {
        let remaining = self.days(from: now, to: date)
        return remaining >= 0 && remaining <= days
    }

    static func startOfMonth(for date: Date = .now, calendar: Calendar = .current) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? date
    }

    /// Human phrasing like "tomorrow", "in 4 days", "today", "3 days ago".
    static func relativePhrase(to date: Date, from now: Date = .now) -> String {
        let d = days(from: now, to: date)
        switch d {
        case 0: return "today"
        case 1: return "tomorrow"
        case -1: return "yesterday"
        case 2...: return "in \(d) days"
        default: return "\(abs(d)) days ago"
        }
    }

    static func monthTitle(for date: Date) -> String {
        date.formatted(.dateTime.month(.wide).year())
    }
}

extension Date {
    var leverShort: String { formatted(.dateTime.day().month(.abbreviated).year()) }
    var leverMedium: String { formatted(.dateTime.day().month(.wide).year()) }
}
