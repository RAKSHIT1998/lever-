import Foundation

struct ParsedDate: Equatable {
    var date: Date
    var label: String?
    var line: String
    var lineIndex: Int
    /// True when the date was written in a fully explicit format (day, month and year present).
    var explicit: Bool
}

/// Extracts explicit dates and the label preceding them ("Order date", "Renews on", "Return by").
struct DateParser {
    private static let numeric = Pattern(#"\b(\d{1,2})[\/\-.](\d{1,2})[\/\-.](\d{2,4})\b"#)
    private static let iso = Pattern(#"\b(\d{4})-(\d{1,2})-(\d{1,2})\b"#)
    private static let dayMonthYear = Pattern(#"\b(\d{1,2})(?:st|nd|rd|th)?\s+(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Sept|Oct|Nov|Dec)[a-z]*\.?,?\s+(\d{4})\b"#)
    private static let monthDayYear = Pattern(#"\b(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Sept|Oct|Nov|Dec)[a-z]*\.?\s+(\d{1,2})(?:st|nd|rd|th)?,?\s+(\d{4})\b"#)

    static let labels: [(key: String, aliases: [String])] = [
        ("purchase", ["order date", "ordered on", "order placed", "invoice date", "date of purchase", "purchase date", "purchased on", "transaction date", "payment date", "paid on", "date of issue", "bill date", "billing date", "date:", "dated"]),
        ("renewal", ["renews on", "renewal date", "next billing date", "next billing", "next payment", "next charge", "renews", "auto-renew", "auto renew", "will renew", "your next bill", "due date", "pay by", "payment due"]),
        ("returnDeadline", ["return by", "return window", "eligible for return until", "return or replace by", "returns accepted until", "return deadline", "last date for return", "replacement by"]),
        ("warrantyEnd", ["warranty until", "warranty valid till", "warranty valid until", "warranty expires", "warranty ends", "coverage until", "coverage ends", "valid till", "valid until", "expiry date", "expires on", "policy end", "policy expiry"]),
        ("warrantyStart", ["warranty start", "coverage start", "policy start", "valid from", "effective from"]),
        ("service", ["check-in", "check in", "checkin", "travel date", "departure", "journey date", "date of travel", "service date", "appointment", "check-out", "check out"]),
        ("booking", ["booked on", "booking date", "reservation date"]),
    ]

    func dates(in lines: [String], reference: Date = .now) -> [ParsedDate] {
        var results: [ParsedDate] = []
        for (index, line) in lines.enumerated() {
            let label = Self.label(for: line, previous: index > 0 ? lines[index - 1] : nil)
            for date in Self.explicitDates(in: line) {
                results.append(ParsedDate(date: date, label: label, line: line, lineIndex: index, explicit: true))
            }
            if results.last?.lineIndex != index {
                // Fall back to Foundation's detector for formats we don't model, but mark them non-explicit.
                for date in Self.detectorDates(in: line) where !results.contains(where: { $0.lineIndex == index && Calendar.current.isDate($0.date, inSameDayAs: date) }) {
                    results.append(ParsedDate(date: date, label: label, line: line, lineIndex: index, explicit: false))
                }
            }
        }
        return results
    }

    static func label(for line: String, previous: String?) -> String? {
        let lower = line.lowercased()
        for entry in labels where entry.aliases.contains(where: { lower.contains($0) }) {
            return entry.key
        }
        // A label on the previous line ("Order date" / "12 Sep 2026") is common in receipts.
        if let previous {
            let prevLower = previous.lowercased()
            if prevLower.count < 40 {
                for entry in labels where entry.aliases.contains(where: { prevLower.contains($0) }) {
                    return entry.key
                }
            }
        }
        return nil
    }

    static func explicitDates(in line: String) -> [Date] {
        var dates: [Date] = []
        for groups in dayMonthYear.allMatches(in: line) {
            if let d = groups[1], let m = groups[2], let y = groups[3], let date = make(day: d, monthName: m, year: y) { dates.append(date) }
        }
        for groups in monthDayYear.allMatches(in: line) {
            if let m = groups[1], let d = groups[2], let y = groups[3], let date = make(day: d, monthName: m, year: y) { dates.append(date) }
        }
        for groups in iso.allMatches(in: line) {
            if let y = groups[1], let m = groups[2], let d = groups[3], let date = make(day: Int(d), month: Int(m), year: Int(y)) { dates.append(date) }
        }
        for groups in numeric.allMatches(in: line) {
            guard let a = groups[1], let b = groups[2], let y = groups[3] else { continue }
            var year = Int(y) ?? 0
            if y.count == 2 { year += 2000 }
            // Prefer day/month (India, EU); swap when the first number can't be a day.
            var day = Int(a), month = Int(b)
            if let d = day, d > 12, let m = month, m <= 12 { day = d; month = m }
            else if let d = day, d <= 12, let m = month, m > 12 { day = m; month = d }
            if let date = make(day: day, month: month, year: year) { dates.append(date) }
        }
        return dates
    }

    static func detectorDates(in line: String) -> [Date] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return [] }
        let range = NSRange(line.startIndex..., in: line)
        return detector.matches(in: line, range: range).compactMap { match in
            guard let date = match.date else { return nil }
            // Reject detector output when the line contains no year and no month name — too easy to hallucinate.
            let hasYear = Pattern(#"\b(19|20)\d{2}\b"#).matches(line)
            let hasMonth = Pattern(#"\b(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)"#).matches(line)
            return (hasYear || hasMonth) ? date : nil
        }
    }

    private static func make(day: String, monthName: String, year: String) -> Date? {
        let months = ["jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6, "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12]
        let key = String(monthName.lowercased().prefix(3))
        return make(day: Int(day), month: months[key], year: Int(year))
    }

    private static func make(day: Int?, month: Int?, year: Int?) -> Date? {
        guard let day, let month, let year, (1...31).contains(day), (1...12).contains(month), (2000...2100).contains(year) else { return nil }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return Calendar.current.date(from: components)
    }
}
