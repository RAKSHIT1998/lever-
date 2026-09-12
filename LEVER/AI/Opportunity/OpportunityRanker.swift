import Foundation

/// Priority = savings weight × urgency × confidence × deadline proximity.
/// Pure and deterministic so the feed ordering is testable.
enum OpportunityRanker {
    static func score(estimatedSavings: Decimal?, urgency: Urgency, confidence: Confidence, daysUntilDeadline: Int?) -> Double {
        let savings = NSDecimalNumber(decimal: estimatedSavings ?? 0).doubleValue
        // Logarithmic so a ₹1,00,000 opportunity doesn't drown every deadline.
        let savingsWeight = savings > 0 ? 1.0 + log10(savings + 1) : 0.6
        let deadlineWeight: Double
        switch daysUntilDeadline {
        case .some(let d) where d < 0: deadlineWeight = 0.3
        case .some(let d) where d <= 1: deadlineWeight = 1.6
        case .some(let d) where d <= 3: deadlineWeight = 1.4
        case .some(let d) where d <= 7: deadlineWeight = 1.2
        case .some(let d) where d <= 30: deadlineWeight = 1.0
        case .some: deadlineWeight = 0.85
        case .none: deadlineWeight = 0.9
        }
        return savingsWeight * urgency.weight * confidence.weight * deadlineWeight
    }

    static func rank<T>(_ items: [T], score: (T) -> Double) -> [T] {
        items.sorted { score($0) > score($1) }
    }
}
