import Foundation

/// Professional claim drafts. Only facts from the purchase go in; unknowns become bracketed placeholders for the user.
struct ClaimGenerator: Sendable {
    func warrantyClaim(for o: OpportunitySnapshot, issue: String? = nil) -> ClaimDraft {
        let p = o.purchase
        let product = p?.title ?? "my product"
        let order = p?.orderNumber ?? "[order number]"
        let subject = "Warranty Claim — \(product) — Order #\(order)"
        var lines: [String] = []
        lines.append("Dear \(o.merchantName) Support,")
        lines.append("")
        lines.append("I am writing regarding \(product), purchased\(p?.purchaseDate.map { " on \($0.leverShort)" } ?? "")\(p.map { " for \(Money.format($0.amount, code: $0.currencyCode))" } ?? "")\(p?.orderNumber.map { " (order #\($0))" } ?? "").")
        lines.append("")
        lines.append("Issue: \(issue ?? "[describe the fault, when it started, and what you've tried]")")
        lines.append("")
        if let coverage = p?.warranties.first {
            lines.append("The product is covered by \(coverage.provider) \(coverage.type.displayName.lowercased())\(coverage.endDate.map { " until \($0.leverShort)" } ?? ""). I am requesting a repair, replacement or refund under this coverage.")
        } else {
            lines.append("I understand the product is still within its warranty period and am requesting a repair, replacement or refund under that coverage.")
        }
        lines.append("")
        lines.append("Proof of purchase is attached. Serial number: \(p?.serialNumber ?? "[serial number]")")
        lines.append("")
        lines.append("Please let me know the next steps and a reference number for this claim.")
        lines.append("")
        lines.append("Kind regards,")
        lines.append("[Your name]")
        return ClaimDraft(subject: subject, body: lines.joined(separator: "\n"))
    }

    func returnRequest(for o: OpportunitySnapshot) -> ClaimDraft {
        let p = o.purchase
        let product = p?.title ?? "my order"
        let subject = "Return Request — \(product)\(p?.orderNumber.map { " — Order #\($0)" } ?? "")"
        let body = """
        Dear \(o.merchantName) Support,

        I would like to return \(product)\(p?.orderNumber.map { " (order #\($0))" } ?? ""), purchased\(p?.purchaseDate.map { " on \($0.leverShort)" } ?? "")\(p.map { " for \(Money.format($0.amount, code: $0.currencyCode))" } ?? "").

        Reason: [reason for return]

        The request is within the return window\(o.deadline.map { " (until \($0.leverShort))" } ?? ""). Please confirm the return process and the refund to my original payment method.

        Kind regards,
        [Your name]
        """
        return ClaimDraft(subject: subject, body: body)
    }

    func refundRequest(for o: OpportunitySnapshot) -> ClaimDraft {
        let p = o.purchase
        let subject = "Refund Request — \(p?.title ?? o.merchantName)\(p?.orderNumber.map { " — Order #\($0)" } ?? "")"
        let body = """
        Dear \(o.merchantName) Support,

        I am requesting a refund of \(o.estimatedSavings.map { Money.format($0, code: o.currencyCode) } ?? "[amount]") relating to \(p?.title ?? "my purchase")\(p?.orderNumber.map { " (order #\($0))" } ?? "").

        Details: \(o.detail)

        Please confirm the refund and expected timeline.

        Kind regards,
        [Your name]
        """
        return ClaimDraft(subject: subject, body: body)
    }
}
