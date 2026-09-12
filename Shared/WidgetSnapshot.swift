import Foundation

/// Lightweight, non-sensitive summary the app publishes for widgets, App Intents and Live Activities.
/// Contains only aggregate numbers and short titles — never document contents.
struct WidgetSnapshot: Codable, Equatable {
    struct Deadline: Codable, Equatable, Identifiable {
        var id: UUID
        var title: String
        var date: Date
        var amount: Decimal?
    }

    var currencyCode: String
    var potentialSavings: Decimal
    var openOpportunities: Int
    var moneyAtRisk: Decimal
    var deadlinesThisWeek: [Deadline]
    var savedThisMonth: Decimal
    var lifetimeSaved: Decimal
    var expiringWarranties: [Deadline]
    var upcomingRenewals: [Deadline]
    var updatedAt: Date

    static let empty = WidgetSnapshot(
        currencyCode: Locale.current.currency?.identifier ?? "INR",
        potentialSavings: 0,
        openOpportunities: 0,
        moneyAtRisk: 0,
        deadlinesThisWeek: [],
        savedThisMonth: 0,
        lifetimeSaved: 0,
        expiringWarranties: [],
        upcomingRenewals: [],
        updatedAt: .now
    )

    private static let key = "lever.widgetSnapshot"

    static func load() -> WidgetSnapshot {
        guard let data = AppGroup.sharedDefaults.data(forKey: key),
              let snapshot = try? JSONDecoder.lever.decode(WidgetSnapshot.self, from: data) else {
            return .empty
        }
        return snapshot
    }

    func save() {
        guard let data = try? JSONEncoder.lever.encode(self) else { return }
        AppGroup.sharedDefaults.set(data, forKey: WidgetSnapshot.key)
    }

    static func clear() {
        AppGroup.sharedDefaults.removeObject(forKey: key)
    }
}

extension Decimal {
    /// Currency string without relying on Foundation's newer FormatStyle in extension contexts.
    func currencyString(code: String, fractionDigits: Int? = nil) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        formatter.locale = Locale.current
        if let fractionDigits {
            formatter.maximumFractionDigits = fractionDigits
            formatter.minimumFractionDigits = fractionDigits
        } else {
            let isWhole = self == self.rounded(scale: 0)
            formatter.maximumFractionDigits = isWhole ? 0 : 2
            formatter.minimumFractionDigits = isWhole ? 0 : 2
        }
        return formatter.string(from: self as NSDecimalNumber) ?? "\(self)"
    }

    func rounded(scale: Int, mode: NSDecimalNumber.RoundingMode = .plain) -> Decimal {
        var value = self
        var result = Decimal()
        NSDecimalRound(&result, &value, scale, mode)
        return result
    }
}
