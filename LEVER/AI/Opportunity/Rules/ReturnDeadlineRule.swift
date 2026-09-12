import Foundation

/// Surfaces open return windows so the user never misses one. Only fires when a deadline actually exists.
struct ReturnDeadlineRule: OpportunityRule {
    let name = "Return deadline"

    func evaluate(_ context: OpportunityContext) -> [OpportunityDraft] {
        let p = context.purchase
        guard let window = p.returnWindow, let deadline = window.deadline else { return [] }
        let days = DateMath.days(from: context.now, to: deadline)
        guard days >= 0, days <= 45 else { return [] }

        let money = RuleSupport.amountText(p.amount, p.currencyCode)
        let when = DateMath.relativePhrase(to: deadline, from: context.now)
        let title = days <= 1 ? "\(p.title) return window closes \(when)" : "Return window for \(p.title) closes \(when)"
        let detail: String
        if window.confidence == .high {
            detail = "Your document states returns are accepted until \(deadline.leverShort). After that, \(money) is locked in."
        } else {
            detail = "Based on the \(window.source.prefix(1).lowercased() + window.source.dropFirst()), you may be able to return this until \(deadline.leverShort). Check the merchant's policy to confirm."
        }
        var evidence: [OpportunityDraft.EvidenceDraft] = [
            .init(kind: .fact, statement: "Purchase of \(money) from \(p.merchantName)\(p.purchaseDate.map { " on \($0.leverShort)" } ?? "").", source: "Your document"),
        ]
        evidence.append(.init(kind: window.confidence == .high ? .fact : .inference, statement: "Return deadline \(deadline.leverShort).", source: window.source))
        if window.confidence != .high {
            evidence.append(.init(kind: .unverified, statement: "Merchant policies vary by category and can change. Verify before relying on this date.", source: "LEVER"))
        }

        return [OpportunityDraft(
            type: .returnDeadline,
            title: title,
            detail: detail,
            estimatedSavings: p.amount,
            currencyCode: p.currencyCode,
            confidence: window.confidence,
            urgency: RuleSupport.urgency(deadline: deadline, now: context.now),
            deadline: deadline,
            merchantName: p.merchantName,
            recommendedAction: "Decide whether to keep it before \(deadline.leverShort). If you're unsure about the purchase, start the return now.",
            evidence: evidence,
            dedupeKey: "return:\(p.id.uuidString)"
        )]
    }
}
