import Foundation

/// Warns before coverage ends — the last chance to claim on a fault. One draft per expiring coverage.
struct WarrantyExpirationRule: OpportunityRule {
    let name = "Warranty expiration"
    let horizonDays = 45

    func evaluate(_ context: OpportunityContext) -> [OpportunityDraft] {
        let p = context.purchase
        return p.warranties.compactMap { warranty in
            guard let end = warranty.endDate else { return nil }
            let days = DateMath.days(from: context.now, to: end)
            guard days >= 0, days <= horizonDays else { return nil }
            let when = days == 0 ? "today" : "in \(days) day\(days == 1 ? "" : "s")"
            return OpportunityDraft(
                type: .warrantyExpiration,
                title: "\(p.title) \(warranty.type == .manufacturer ? "warranty" : warranty.type.displayName.lowercased()) expires \(when)",
                detail: "\(warranty.provider) coverage ends \(end.leverShort). If anything is wrong with it, now is the time to check and claim.",
                estimatedSavings: p.amount,
                currencyCode: p.currencyCode,
                confidence: warranty.confidence,
                urgency: days <= 7 ? .high : .medium,
                deadline: end,
                merchantName: p.merchantName,
                recommendedAction: "Test the product thoroughly before \(end.leverShort). Report any fault to \(warranty.provider) while coverage is active.",
                evidence: [
                    .init(kind: warranty.confidence == .high ? .fact : .inference, statement: "\(warranty.provider) coverage until \(end.leverShort).", source: warranty.source),
                    .init(kind: .fact, statement: "Purchase value \(RuleSupport.amountText(p.amount, p.currencyCode)).", source: "Your document"),
                ],
                dedupeKey: "warranty:\(p.id.uuidString):\(warranty.provider):\(warranty.type.rawValue)"
            )
        }
    }
}
