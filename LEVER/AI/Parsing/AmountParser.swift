import Foundation

struct ParsedAmount: Equatable {
    var value: Decimal
    var currencyCode: String?
    var line: String
    var lineIndex: Int
}

/// Finds currency amounts in text and picks the most plausible total.
struct AmountParser {
    // ₹1,49,990.00 | Rs. 1499 | INR 48,000 | $5.99 | €12,50 | 1,299.00 INR
    private static let symbolFirst = Pattern(#"(₹|Rs\.?|INR|\$|USD|US\$|€|EUR|£|GBP|AED|SGD|CAD|AUD)\s?(\d{1,3}(?:[,\s]\d{2,3})*(?:\.\d{1,2})?|\d+(?:\.\d{1,2})?)"#)
    private static let symbolLast = Pattern(#"(\d{1,3}(?:[,\s]\d{2,3})*(?:\.\d{1,2})?|\d+(?:\.\d{1,2})?)\s?(₹|Rs\.?|INR|USD|EUR|GBP|\$|€|£)(?![A-Za-z])"#)

    static let totalKeywords = ["grand total", "order total", "total amount", "amount paid", "amount due", "total paid", "you paid", "net payable", "total payable", "balance due", "amount payable", "total due", "invoice total", "total:", "total ", "paid ", "charged"]
    /// Lines that are never line items (fees and shipping *are* items — the fee rule needs them).
    static let nonItemWords = ["subtotal", "sub total", "sub-total", "tax", "gst", "cgst", "sgst", "igst", "vat", "discount", "you saved", "savings", "coupon", "cashback", "mrp", "previous", "was ", "old price", "refund", "balance"]
    static let excludeFromTotal = ["subtotal", "sub total", "sub-total", "tax", "gst", "cgst", "sgst", "igst", "vat", "discount", "you saved", "savings", "shipping", "delivery", "coupon", "cashback", "mrp", "previous", "was ", "old price", "per month", "/month", "/mo", "monthly", "unit price", "refund", "convenience fee", "platform fee", "handling"]

    static func currencyCode(forSymbol symbol: String) -> String? {
        switch symbol.lowercased().replacingOccurrences(of: ".", with: "") {
        case "₹", "rs", "inr": "INR"
        case "$", "usd", "us$": "USD"
        case "€", "eur": "EUR"
        case "£", "gbp": "GBP"
        case "aed": "AED"
        case "sgd": "SGD"
        case "cad": "CAD"
        case "aud": "AUD"
        default: nil
        }
    }

    static func parseDecimal(_ raw: String) -> Decimal? {
        let cleaned = raw.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: " ", with: "")
        guard !cleaned.isEmpty, let value = Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        return value
    }

    func amounts(in lines: [String]) -> [ParsedAmount] {
        var results: [ParsedAmount] = []
        for (index, line) in lines.enumerated() {
            for groups in Self.symbolFirst.allMatches(in: line) {
                guard groups.count >= 3, let symbol = groups[1], let number = groups[2], let value = Self.parseDecimal(number) else { continue }
                results.append(ParsedAmount(value: value, currencyCode: Self.currencyCode(forSymbol: symbol), line: line, lineIndex: index))
            }
            for groups in Self.symbolLast.allMatches(in: line) {
                guard groups.count >= 3, let number = groups[1], let symbol = groups[2], let value = Self.parseDecimal(number) else { continue }
                let candidate = ParsedAmount(value: value, currencyCode: Self.currencyCode(forSymbol: symbol), line: line, lineIndex: index)
                if !results.contains(where: { $0.lineIndex == index && $0.value == value }) {
                    results.append(candidate)
                }
            }
        }
        return results.filter { $0.value > 0 && $0.value < 100_000_000 }
    }

    /// Returns the best total and a 0...1 confidence in that choice.
    func total(from amounts: [ParsedAmount]) -> (ParsedAmount, Double)? {
        guard !amounts.isEmpty else { return nil }
        let labelled = amounts.filter { amount in
            let lower = amount.line.lowercased()
            return Self.totalKeywords.contains { lower.contains($0) } && !Self.excludeFromTotal.contains { lower.contains($0) }
        }
        if let best = labelled.max(by: { $0.value < $1.value }) {
            // "Grand total" beats plain "total" by preferring the largest labelled value.
            return (best, 0.92)
        }
        let unexcluded = amounts.filter { amount in
            let lower = amount.line.lowercased()
            return !Self.excludeFromTotal.contains { lower.contains($0) }
        }
        let pool = unexcluded.isEmpty ? amounts : unexcluded
        guard let largest = pool.max(by: { $0.value < $1.value }) else { return nil }
        return (largest, amounts.count == 1 ? 0.75 : 0.55)
    }

    func dominantCurrency(in amounts: [ParsedAmount], fallback: String) -> String {
        let codes = amounts.compactMap(\.currencyCode)
        guard !codes.isEmpty else { return fallback }
        var counts: [String: Int] = [:]
        codes.forEach { counts[$0, default: 0] += 1 }
        return counts.max(by: { $0.value < $1.value })?.key ?? fallback
    }
}
