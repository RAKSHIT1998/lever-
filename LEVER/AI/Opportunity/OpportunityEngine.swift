import Foundation

/// A rule inspects one purchase (with context) and proposes zero or more opportunities.
protocol OpportunityRule: Sendable {
    var name: String { get }
    func evaluate(_ context: OpportunityContext) -> [OpportunityDraft]
}

/// Modular money-leak detection. Add a rule, get a new kind of opportunity everywhere.
struct OpportunityEngine: Sendable {
    let rules: [OpportunityRule]

    static let standard = OpportunityEngine(rules: [
        ReturnDeadlineRule(),
        WarrantyExpirationRule(),
        SubscriptionRenewalRule(),
        PriceDropRule(),
        DuplicateChargeRule(),
        FeeDetectionRule(),
        PurchaseProtectionRule(),
        InsuranceRenewalRule(),
    ])

    func detect(_ context: OpportunityContext) -> [OpportunityDraft] {
        var drafts = rules.flatMap { $0.evaluate(context) }
        // Same dedupe key from two rules → keep the higher-confidence one.
        var seen: [String: OpportunityDraft] = [:]
        for draft in drafts {
            if let existing = seen[draft.dedupeKey], existing.confidence >= draft.confidence { continue }
            seen[draft.dedupeKey] = draft
        }
        drafts = Array(seen.values)
        return OpportunityRanker.rank(drafts) { $0.priorityScore }
    }
}

/// Small helpers shared by rules.
enum RuleSupport {
    static func amountText(_ value: Decimal, _ code: String) -> String { Money.format(value, code: code) }

    static func urgency(deadline: Date?, now: Date) -> Urgency {
        Urgency(daysUntilDeadline: deadline.map { DateMath.days(from: now, to: $0) })
    }
}
