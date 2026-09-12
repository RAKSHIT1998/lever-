import Foundation

/// Upcoming renewals, with price increases and user-marked-unused subscriptions given real teeth.
struct SubscriptionRenewalRule: OpportunityRule {
    let name = "Subscription renewal"

    func evaluate(_ context: OpportunityContext) -> [OpportunityDraft] {
        let p = context.purchase
        guard let sub = p.subscription, sub.status != .cancelled else { return [] }
        var drafts: [OpportunityDraft] = []
        let cycleCost = RuleSupport.amountText(sub.price, p.currencyCode) + sub.cycle.shortSuffix
        let annual = SubscriptionMath.annualCost(price: sub.price, cycle: sub.cycle)

        // 1. Price increase → negotiate or switch.
        if let previous = sub.previousPrice, let increase = SubscriptionMath.annualIncrease(current: sub.price, previous: previous, cycle: sub.cycle), let pct = SubscriptionMath.increasePercent(current: sub.price, previous: previous) {
            drafts.append(OpportunityDraft(
                type: .negotiation,
                title: "\(p.merchantName) price went up \(pct)%",
                detail: "Your plan is now \(cycleCost), up from \(RuleSupport.amountText(previous, p.currencyCode))\(sub.cycle.shortSuffix). Asking for retention pricing or switching could save up to \(RuleSupport.amountText(increase, p.currencyCode)) a year.",
                estimatedSavings: increase,
                currencyCode: p.currencyCode,
                confidence: sub.confidence,
                urgency: RuleSupport.urgency(deadline: sub.nextBillingDate, now: context.now),
                deadline: sub.nextBillingDate,
                merchantName: p.merchantName,
                recommendedAction: "Contact \(p.merchantName) before the renewal and ask for the previous price or a retention offer.",
                evidence: [
                    .init(kind: .fact, statement: "Current price \(cycleCost).", source: "Your document"),
                    .init(kind: .fact, statement: "Previous price \(RuleSupport.amountText(previous, p.currencyCode))\(sub.cycle.shortSuffix).", source: "Your document"),
                    .init(kind: .inference, statement: "Difference over 12 months: \(RuleSupport.amountText(increase, p.currencyCode)).", source: "LEVER calculation"),
                ],
                dedupeKey: "increase:\(p.id.uuidString)"
            ))
        }

        // 2. Upcoming renewal within 14 days.
        if let next = sub.nextBillingDate {
            let days = DateMath.days(from: context.now, to: next)
            if days >= 0, days <= 14 {
                let unused = sub.status == .markedUnused
                let when = DateMath.relativePhrase(to: next, from: context.now)
                let savings: Decimal? = unused ? annual : nil
                var evidence: [OpportunityDraft.EvidenceDraft] = [
                    .init(kind: .fact, statement: "Renews \(next.leverShort) at \(cycleCost).", source: "Your document"),
                ]
                if unused { evidence.append(.init(kind: .userInput, statement: "You marked this subscription as unused.", source: "You")) }
                if let annual { evidence.append(.init(kind: .inference, statement: "Annual cost \(RuleSupport.amountText(annual, p.currencyCode)).", source: "LEVER calculation")) }
                drafts.append(OpportunityDraft(
                    type: .subscriptionRenewal,
                    title: "\(p.merchantName) renews \(when)",
                    detail: unused
                        ? "You've marked this as unused. Cancelling before \(next.leverShort) avoids \(RuleSupport.amountText(annual ?? sub.price, p.currencyCode)) over the next year."
                        : "\(cycleCost) will be charged \(when). A good moment to decide whether it's still worth it.",
                    estimatedSavings: savings ?? (drafts.isEmpty ? annual : nil),
                    currencyCode: p.currencyCode,
                    confidence: unused ? .high : sub.confidence,
                    urgency: Urgency(daysUntilDeadline: days),
                    deadline: next,
                    merchantName: p.merchantName,
                    recommendedAction: unused ? "Cancel before \(next.leverShort) to avoid the charge." : "Review whether you still use \(p.merchantName). Cancel or downgrade before \(next.leverShort) if not.",
                    evidence: evidence,
                    dedupeKey: "renewal:\(p.id.uuidString)"
                ))
            }
        }
        return drafts
    }
}
