import Foundation

/// Fires when a *recorded* observation shows a lower price than paid. Observations come from the user or approved sources.
struct PriceDropRule: OpportunityRule {
    let name = "Price drop"
    /// Ignore trivial movements.
    let minimumDropFraction: Decimal = 0.03

    func evaluate(_ context: OpportunityContext) -> [OpportunityDraft] {
        let p = context.purchase
        guard let latest = p.latestPrice, latest.price < p.amount, p.amount > 0 else { return [] }
        let drop = p.amount - latest.price
        guard drop / p.amount >= minimumDropFraction else { return [] }

        let isTravel = p.documentType == .booking || p.category == .travel
        let title = isTravel ? "Your \(p.title) price dropped" : "\(p.title) is cheaper now"
        let detail = "You paid \(RuleSupport.amountText(p.amount, p.currencyCode)). The price recorded on \(latest.observedAt.leverShort) is \(RuleSupport.amountText(latest.price, p.currencyCode)). Some merchants offer price adjustments or free rebooking — check whether yours does."
        let deadline = p.returnWindow?.deadline
        return [OpportunityDraft(
            type: isTravel ? .travelPriceChange : .priceDrop,
            title: title,
            detail: detail,
            estimatedSavings: drop,
            currencyCode: p.currencyCode,
            confidence: latest.source.lowercased().contains("you") ? .high : .medium,
            urgency: deadline != nil ? RuleSupport.urgency(deadline: deadline, now: context.now) : .medium,
            deadline: deadline,
            merchantName: p.merchantName,
            recommendedAction: isTravel ? "Check whether the booking allows free cancellation or rebooking at the lower rate." : "Ask \(p.merchantName) for a price adjustment, or return and repurchase if the return window is open.",
            evidence: [
                .init(kind: .fact, statement: "Paid \(RuleSupport.amountText(p.amount, p.currencyCode)).", source: "Your document"),
                .init(kind: latest.source.lowercased().contains("you") ? .userInput : .fact, statement: "Price \(RuleSupport.amountText(latest.price, p.currencyCode)) observed \(latest.observedAt.leverShort).", source: latest.source),
                .init(kind: .possibility, statement: "Price-match and rebooking policies differ by merchant.", source: "LEVER"),
            ],
            dedupeKey: "pricedrop:\(p.id.uuidString)"
        )]
    }
}
