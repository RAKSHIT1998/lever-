import Foundation

/// Insurance renews yearly and almost nobody re-shops it. Before a policy renews, prompt a comparison —
/// as a possibility, since LEVER has no quotes of its own.
struct InsuranceRenewalRule: OpportunityRule {
    let name = "Insurance renewal"
    let horizonDays = 45

    func evaluate(_ context: OpportunityContext) -> [OpportunityDraft] {
        let p = context.purchase
        guard p.documentType == .insurance || p.category == .insurance else { return [] }
        guard let sub = p.subscription, sub.status != .cancelled, let next = sub.nextBillingDate else { return [] }
        let days = DateMath.days(from: context.now, to: next)
        guard days >= 0, days <= horizonDays else { return [] }
        let premium = Money.format(sub.price, code: p.currencyCode)
        return [OpportunityDraft(
            type: .insuranceOpportunity,
            title: "\(p.merchantName) policy renews \(DateMath.relativePhrase(to: next, from: context.now))",
            detail: "Your premium is \(premium)\(sub.cycle.shortSuffix). Insurers often price renewals higher than new-customer quotes; comparing two or three quotes before \(next.leverShort) is usually worth an hour.",
            estimatedSavings: nil,
            currencyCode: p.currencyCode,
            confidence: sub.confidence,
            urgency: days <= 7 ? .high : .medium,
            deadline: next,
            merchantName: p.merchantName,
            recommendedAction: "Get 2–3 comparable quotes, then ask \(p.merchantName) to match the best one or switch before the renewal date.",
            evidence: [
                .init(kind: .fact, statement: "Policy renews \(next.leverShort) at \(premium).", source: "Your document"),
                .init(kind: .possibility, statement: "Savings depend on quotes you gather — LEVER hasn't compared insurers for you.", source: "LEVER"),
            ],
            dedupeKey: "insurance:\(p.id.uuidString)"
        )]
    }
}
