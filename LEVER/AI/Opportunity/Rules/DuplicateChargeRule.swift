import Foundation

/// Two purchases from the same merchant, same amount, within three days look like a double charge. Flagged, never asserted.
struct DuplicateChargeRule: OpportunityRule {
    let name = "Duplicate charge"

    func evaluate(_ context: OpportunityContext) -> [OpportunityDraft] {
        let p = context.purchase
        guard let date = p.purchaseDate, p.amount > 0, p.subscription == nil else { return [] }
        let candidates = context.otherPurchases.filter { other in
            other.id != p.id
                && other.merchantName.lowercased() == p.merchantName.lowercased()
                && other.amount == p.amount
                && other.currencyCode == p.currencyCode
                && other.subscription == nil
                && (other.purchaseDate.map { abs(DateMath.days(from: $0, to: date)) <= 3 } ?? false)
                && (other.orderNumber == nil || p.orderNumber == nil || other.orderNumber == p.orderNumber)
        }
        guard let twin = candidates.first else { return [] }
        let sameOrder = twin.orderNumber != nil && twin.orderNumber == p.orderNumber
        return [OpportunityDraft(
            type: .duplicateCharge,
            title: "Two \(RuleSupport.amountText(p.amount, p.currencyCode)) charges from \(p.merchantName)",
            detail: sameOrder
                ? "Both documents carry order \(p.orderNumber ?? ""). This looks like the same order captured twice — or a genuine double charge."
                : "Two identical amounts within a few days. If you didn't buy twice, this may be worth a refund request.",
            estimatedSavings: p.amount,
            currencyCode: p.currencyCode,
            confidence: sameOrder ? .medium : .low,
            urgency: .medium,
            deadline: nil,
            merchantName: p.merchantName,
            recommendedAction: "Check your card or bank statement for two debits. If both exist, ask \(p.merchantName) to refund the duplicate.",
            evidence: [
                .init(kind: .fact, statement: "\(RuleSupport.amountText(p.amount, p.currencyCode)) on \(date.leverShort).", source: "Your document"),
                .init(kind: .fact, statement: "\(RuleSupport.amountText(twin.amount, twin.currencyCode))\(twin.purchaseDate.map { " on \($0.leverShort)" } ?? "").", source: "Another document in your vault"),
                .init(kind: .possibility, statement: "Could be a legitimate repeat purchase.", source: "LEVER"),
            ],
            dedupeKey: "duplicate:\([p.id.uuidString, twin.id.uuidString].sorted().joined(separator: ":"))"
        )]
    }
}
