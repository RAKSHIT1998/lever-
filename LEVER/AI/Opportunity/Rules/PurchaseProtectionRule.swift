import Foundation

/// High-value items paid by card may carry purchase protection or extended warranty from the card issuer.
/// Presented strictly as a possibility to check.
struct PurchaseProtectionRule: OpportunityRule {
    let name = "Purchase protection"
    let threshold: Decimal = 20_000

    func evaluate(_ context: OpportunityContext) -> [OpportunityDraft] {
        let p = context.purchase
        guard p.amount >= threshold, p.subscription == nil, p.documentType != .booking, p.documentType != .insurance, p.documentType != .bill else { return [] }
        guard let method = p.paymentMethod?.lowercased(), method.containsAny(["visa", "mastercard", "amex", "american express", "credit"]) else { return [] }
        guard !p.warranties.contains(where: { $0.type == .creditCard }) else { return [] }
        return [OpportunityDraft(
            type: .purchaseProtection,
            title: "Check card protection for your \(p.title)",
            detail: "You paid \(RuleSupport.amountText(p.amount, p.currencyCode)) with \(p.paymentMethod ?? "a card"). Many credit cards include purchase protection or an extended warranty on items like this. Worth a look at your card's benefits.",
            estimatedSavings: nil,
            currencyCode: p.currencyCode,
            confidence: .low,
            urgency: .low,
            deadline: p.purchaseDate.flatMap { DateMath.adding(days: 90, to: $0) },
            merchantName: p.merchantName,
            recommendedAction: "Look up your card's purchase protection terms. If covered, add it to this purchase in LEVER so claims are ready when needed.",
            evidence: [
                .init(kind: .fact, statement: "Paid with \(p.paymentMethod ?? "card").", source: "Your document"),
                .init(kind: .possibility, statement: "Card benefits vary by issuer and card tier. LEVER hasn't verified yours.", source: "LEVER"),
            ],
            dedupeKey: "protection:\(p.id.uuidString)"
        )]
    }
}
