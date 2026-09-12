import Foundation

/// Builds a negotiation position from verified inputs only. Nothing about the user's history or competitors is
/// invented — if the user didn't supply it, the script doesn't mention it.
struct NegotiationAssistant: Sendable {
    func prepare(_ input: NegotiationInput) -> NegotiationDraft {
        let code = input.currencyCode
        let suffix = input.billingCycle.shortSuffix
        let current = Money.format(input.currentPrice, code: code) + suffix

        var arguments: [String] = []
        if let previous = input.previousPrice, previous < input.currentPrice, let pct = SubscriptionMath.increasePercent(current: input.currentPrice, previous: previous) {
            arguments.append("My price went up \(pct)% — from \(Money.format(previous, code: code))\(suffix) to \(current) — without a change in what I get.")
        }
        if let competitor = input.competitorPrice, competitor < input.currentPrice {
            arguments.append("A comparable plan is available elsewhere for \(Money.format(competitor, code: code))\(suffix).")
        }
        if let tenure = input.tenureMonths, tenure >= 12 {
            arguments.append("I've been a customer for \(tenure / 12) year\(tenure >= 24 ? "s" : "") and would prefer to stay.")
        }
        if arguments.isEmpty {
            arguments.append("I'm reviewing my spending and this is one of the plans I'm considering cancelling unless the price improves.")
        }

        // Target: previous price, else competitor, else 20% off. Walk-away: what they'd pay to stay (10% off or competitor).
        var target: Decimal? = input.previousPrice ?? input.competitorPrice
        if target == nil { target = (input.currentPrice * Decimal(sign: .plus, exponent: -1, significand: 8)).rounded(scale: 0) }
        var walkAway: Decimal? = input.competitorPrice
        if walkAway == nil { walkAway = (input.currentPrice * Decimal(sign: .plus, exponent: -1, significand: 9)).rounded(scale: 0) }

        let best = arguments[0]
        let fallback = arguments.count > 1 ? arguments[1] : "If you can't lower the price, is there a smaller plan or a promotional rate I can move to?"
        let targetText = target.map { Money.format($0, code: code) + suffix } ?? "a lower price"

        let email = """
        Hi \(input.merchantName) team,

        \(best) \(arguments.count > 1 ? arguments[1] : "")

        I'd like to continue, but \(current) isn't working for me. Could you offer \(targetText), a retention discount or a lower-priced plan? \(input.desiredOutcome)

        If that isn't possible, please let me know how to cancel before my next renewal.

        Thanks,
        [Your name]
        """

        let chat = "Hi! \(best) I'd like to stay, but not at \(current). Can you offer \(targetText) or a retention discount? Otherwise I'll need to cancel before renewal."

        let phone = """
        1. "Hi, I'm calling about my \(input.merchantName) plan, currently \(current)."
        2. "\(best)"
        3. "I'd like to stay, but I need the price to come down. Can you offer \(targetText)?"
        4. If they hesitate: "\(fallback)"
        5. If nothing is offered: "OK — please walk me through cancelling before the next renewal."
        Target: \(targetText). Walk-away: \(walkAway.map { Money.format($0, code: code) + suffix } ?? "your call").
        """

        return NegotiationDraft(
            bestArgument: best,
            fallbackArgument: fallback,
            targetPrice: target,
            walkAwayPrice: walkAway,
            emailDraft: email.replacingOccurrences(of: "  ", with: " "),
            chatDraft: chat,
            phoneScript: phone
        )
    }
}
