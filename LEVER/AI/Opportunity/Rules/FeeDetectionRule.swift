import Foundation

/// Highlights fee-like line items. Fees aren't always avoidable — this is a prompt to check, not a claim of wrongdoing.
struct FeeDetectionRule: OpportunityRule {
    let name = "Fee detection"
    static let feeWords = ["convenience fee", "platform fee", "service fee", "processing fee", "handling fee", "surcharge", "late fee", "penalty", "resort fee", "cleaning fee", "booking fee", "payment fee", "delivery fee", "packaging"]

    func evaluate(_ context: OpportunityContext) -> [OpportunityDraft] {
        let p = context.purchase
        let fees = p.items.filter { item in
            let lower = item.name.lowercased()
            return Self.feeWords.contains { lower.contains($0) } && (item.total ?? 0) > 0
        }
        guard !fees.isEmpty else { return [] }
        let total = fees.compactMap(\.total).reduce(0, +)
        guard total > 0, total / max(p.amount, 1) >= Decimal(string: "0.02") ?? 0 else { return [] }
        let names = fees.map(\.name).joined(separator: ", ")
        return [OpportunityDraft(
            type: .feeDetection,
            title: "\(RuleSupport.amountText(total, p.currencyCode)) in fees on your \(p.merchantName) purchase",
            detail: "Charges labelled \(names). Some fees can be waived, disputed or avoided with a different payment method.",
            estimatedSavings: total,
            currencyCode: p.currencyCode,
            confidence: .medium,
            urgency: .low,
            deadline: nil,
            merchantName: p.merchantName,
            recommendedAction: "Ask \(p.merchantName) whether these fees can be waived, and check whether another payment option avoids them next time.",
            evidence: fees.map { .init(kind: .fact, statement: "\($0.name): \(RuleSupport.amountText($0.total ?? 0, p.currencyCode)).", source: "Your document") } + [
                .init(kind: .possibility, statement: "Not every fee is negotiable.", source: "LEVER"),
            ],
            dedupeKey: "fees:\(p.id.uuidString)"
        )]
    }
}
