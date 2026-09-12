import Foundation

/// Template-driven plans built strictly from known facts. No invented policies, prices or history.
struct ActionPlanGenerator: Sendable {
    let generatedBy: String

    init(generatedBy: String = "LEVER on-device") {
        self.generatedBy = generatedBy
    }

    func plan(for o: OpportunitySnapshot) -> ActionPlanDraft {
        let money = o.estimatedSavings.map { Money.format($0, code: o.currencyCode) }
        let product = o.purchase?.title ?? o.merchantName
        let merchant = o.merchantName
        let order = o.purchase?.orderNumber.map { " (order \($0))" } ?? ""
        let deadlineText = o.deadline.map { $0.leverShort }
        let why = o.evidence.isEmpty ? o.detail : o.evidence.joined(separator: " ")

        switch o.type {
        case .subscriptionRenewal:
            return ActionPlanDraft(
                summary: "Decide on \(merchant) before it renews\(deadlineText.map { " on \($0)" } ?? "").",
                whyItMatters: why,
                estimatedSavings: o.estimatedSavings,
                steps: [
                    "Open your \(merchant) account or the App Store subscriptions page.",
                    "If you don't use it enough, cancel before \(deadlineText ?? "the renewal date").",
                    "If you want to keep it, check for a cheaper tier or an annual discount.",
                    "Mark the outcome in LEVER so your savings are tracked.",
                ],
                messageDraft: "Hi \(merchant) team, I'd like to cancel my subscription before the next renewal\(deadlineText.map { " on \($0)" } ?? ""). Please confirm the cancellation and that no further charges will be made. Thank you.",
                callScript: "Hello, I'm calling about my \(merchant) subscription. I'd like to cancel before it renews\(deadlineText.map { " on \($0)" } ?? ""). Could you confirm the cancellation and send a confirmation email?",
                deadline: o.deadline,
                confidence: o.confidence,
                generatedBy: generatedBy
            )

        case .negotiation:
            let sub = o.purchase?.subscription
            let current = sub.map { Money.format($0.price, code: o.currencyCode) + $0.cycle.shortSuffix }
            let previous = sub?.previousPrice.map { Money.format($0, code: o.currencyCode) + (sub?.cycle.shortSuffix ?? "") }
            return ActionPlanDraft(
                summary: "Ask \(merchant) for retention pricing.",
                whyItMatters: why,
                estimatedSavings: o.estimatedSavings,
                steps: [
                    "Contact \(merchant) support (chat or phone) before the renewal.",
                    "Say you've noticed the price increase and are considering cancelling.",
                    "Ask for the previous price, a retention offer or a cheaper plan.",
                    "If nothing is offered, compare alternatives and cancel before renewal if it's not worth it.",
                ],
                messageDraft: "Hi, I've noticed my plan is renewing at \(current ?? "a higher price")\(previous.map { ", up from \($0)" } ?? ""). I'd like to stay a customer, but not at this price. Are there any retention offers or a lower-priced plan available? Otherwise I'll need to cancel before the renewal. Thanks.",
                callScript: "Hi, I'm calling about my \(merchant) plan. It's renewing at \(current ?? "a higher price")\(previous.map { " and I was previously paying \($0)" } ?? ""). I'd prefer to stay, but I'm considering cancelling because of the increase. Is there a retention offer or a lower-priced plan you can move me to?",
                deadline: o.deadline,
                confidence: o.confidence,
                generatedBy: generatedBy
            )

        case .returnDeadline:
            return ActionPlanDraft(
                summary: "Decide whether to keep \(product) before \(deadlineText ?? "the return window closes").",
                whyItMatters: why,
                estimatedSavings: o.estimatedSavings,
                steps: [
                    "Check the product carefully for faults, fit or regret.",
                    "Confirm the exact return policy on the \(merchant) order page.",
                    "If returning, start the return online or with the message below before \(deadlineText ?? "the deadline").",
                    "Keep the packaging and proof of purchase until the refund lands.",
                ],
                messageDraft: "Hi \(merchant), I'd like to return \(product)\(order) purchased\(o.purchase?.purchaseDate.map { " on \($0.leverShort)" } ?? ""). It is within the return window. Please let me know the return process and confirm the refund amount of \(money ?? "the purchase price"). Thank you.",
                callScript: "Hi, I'm calling about \(product)\(order). I'd like to arrange a return within the return window. What's the process, and when can I expect the refund?",
                deadline: o.deadline,
                confidence: o.confidence,
                generatedBy: generatedBy
            )

        case .warrantyExpiration, .claimOpportunity:
            return ActionPlanDraft(
                summary: "Use your coverage on \(product) while it's still active.",
                whyItMatters: why,
                estimatedSavings: o.estimatedSavings,
                steps: [
                    "Test \(product) thoroughly — battery, buttons, ports, screen, noise.",
                    "If anything is off, gather proof of purchase and the serial number.",
                    "Contact the provider before \(deadlineText ?? "coverage ends") and reference the coverage.",
                    "Log the claim in LEVER so the outcome is tracked.",
                ],
                messageDraft: ClaimGenerator().warrantyClaim(for: o).body,
                callScript: "Hi, I'm calling about \(product)\(order), which is still under warranty until \(deadlineText ?? "later this month"). I've noticed an issue and would like to raise a claim. What information do you need from me?",
                deadline: o.deadline,
                confidence: o.confidence,
                generatedBy: generatedBy
            )

        case .priceDrop, .travelPriceChange, .cheaperAlternative:
            let paid = o.purchase.map { Money.format($0.amount, code: $0.currencyCode) }
            let observed = o.purchase?.latestPrice.map { Money.format($0.price, code: o.currencyCode) }
            return ActionPlanDraft(
                summary: "Ask \(merchant) about a price adjustment.",
                whyItMatters: why,
                estimatedSavings: o.estimatedSavings,
                steps: [
                    "Check whether \(merchant) offers price adjustments or free rebooking.",
                    "Screenshot the lower price with the date visible.",
                    "Contact support with your order details and the message below.",
                    "If no adjustment is offered and the return window is open, consider returning and repurchasing.",
                ],
                messageDraft: "Hi \(merchant), I purchased \(product)\(order) for \(paid ?? "the listed price")\(o.purchase?.purchaseDate.map { " on \($0.leverShort)" } ?? ""). The same item is now listed at \(observed ?? "a lower price"). Could you please adjust my price to match, or advise on your price-adjustment policy? Thank you.",
                callScript: "Hi, I bought \(product)\(order) for \(paid ?? "the listed price") and it's now \(observed ?? "cheaper"). Do you offer a price adjustment? If not, what are my options?",
                deadline: o.deadline,
                confidence: o.confidence,
                generatedBy: generatedBy
            )

        case .duplicateCharge, .refund:
            return ActionPlanDraft(
                summary: "Confirm the charge and request a refund if it's duplicated.",
                whyItMatters: why,
                estimatedSavings: o.estimatedSavings,
                steps: [
                    "Check your bank or card statement for two debits of \(money ?? "the amount").",
                    "If both exist, contact \(merchant) with both dates and order numbers.",
                    "If the merchant doesn't respond, ask your bank about a chargeback.",
                    "Mark resolved in LEVER once the refund lands.",
                ],
                messageDraft: "Hi \(merchant), I appear to have been charged twice for \(product)\(order) — \(money ?? "the amount") on two occasions. Please investigate and refund the duplicate charge. I can share statement details if needed. Thank you.",
                callScript: "Hi, I think I've been charged twice for \(product)\(order). Can you check and refund the duplicate?",
                deadline: nil,
                confidence: o.confidence,
                generatedBy: generatedBy
            )

        case .feeDetection:
            return ActionPlanDraft(
                summary: "Ask about the fees on this purchase.",
                whyItMatters: why,
                estimatedSavings: o.estimatedSavings,
                steps: [
                    "Note which fees were charged (listed in the evidence).",
                    "Ask \(merchant) whether any can be waived or refunded.",
                    "Next time, check whether another payment method or plan avoids them.",
                ],
                messageDraft: "Hi \(merchant), my recent purchase\(order) included fees totalling \(money ?? "an amount") that I wasn't expecting. Could you explain what they cover and whether any can be waived? Thank you.",
                callScript: "Hi, my recent order\(order) had fees I didn't expect. Can you explain them and let me know if any can be waived?",
                deadline: nil,
                confidence: o.confidence,
                generatedBy: generatedBy
            )

        case .purchaseProtection, .insuranceOpportunity:
            return ActionPlanDraft(
                summary: "Check whether \(product) is covered by your card or insurance.",
                whyItMatters: why,
                estimatedSavings: nil,
                steps: [
                    "Open your card's benefits guide and search for 'purchase protection' or 'extended warranty'.",
                    "Note the coverage window, cap and how to claim.",
                    "Add the coverage to this purchase in LEVER so it's tracked.",
                ],
                messageDraft: nil,
                callScript: "Hi, I recently bought \(product) with this card. Does it include purchase protection or extended warranty, and how would I make a claim?",
                deadline: o.deadline,
                confidence: o.confidence,
                generatedBy: generatedBy
            )

        case .maintenance, .unknown:
            return ActionPlanDraft(
                summary: o.title,
                whyItMatters: why,
                estimatedSavings: o.estimatedSavings,
                steps: ["Review the details.", "Decide whether action is needed.", "Mark resolved in LEVER."],
                messageDraft: nil,
                callScript: nil,
                deadline: o.deadline,
                confidence: o.confidence,
                generatedBy: generatedBy
            )
        }
    }
}
