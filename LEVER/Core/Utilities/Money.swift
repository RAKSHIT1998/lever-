import Foundation

enum Money {
    static var defaultCurrencyCode: String {
        Locale.current.currency?.identifier ?? "INR"
    }

    static func format(_ amount: Decimal, code: String, compact: Bool = false) -> String {
        if compact, abs(amount) >= 100_000 {
            return compactString(amount, code: code)
        }
        return amount.currencyString(code: code)
    }

    static func symbol(for code: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        return formatter.currencySymbol ?? code
    }

    private static func compactString(_ amount: Decimal, code: String) -> String {
        let symbol = symbol(for: code)
        let value = NSDecimalNumber(decimal: amount).doubleValue
        if code == "INR" {
            if value >= 10_000_000 { return "\(symbol)\(String(format: "%.1f", value / 10_000_000))Cr" }
            if value >= 100_000 { return "\(symbol)\(String(format: "%.1f", value / 100_000))L" }
        }
        if value >= 1_000_000 { return "\(symbol)\(String(format: "%.1f", value / 1_000_000))M" }
        return "\(symbol)\(String(format: "%.0f", value / 1_000))K"
    }
}
