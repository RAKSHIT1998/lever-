import Foundation

/// Keyword-scored document type classification. Cheap, transparent, offline.
struct DocumentClassifier {
    private static let signals: [DocumentType: [String]] = [
        .subscription: ["subscription", "/month", "per month", "/year", "per year", "billing cycle", "your plan", "membership", "renews", "auto-renew", "next billing", "monthly plan", "annual plan", "premium plan"],
        .renewalNotice: ["renewal notice", "will renew", "is renewing", "renews on", "renewal", "price change", "new price", "price increase", "your price is changing", "auto-renewal"],
        .booking: ["booking", "reservation", "check-in", "check in", "check-out", "itinerary", "pnr", "boarding", "flight", "hotel", "guest", "room", "nights", "departure", "confirmation number"],
        .warranty: ["warranty card", "warranty certificate", "coverage period", "warranty terms", "this warranty", "warranty period", "applecare", "extended warranty", "protection plan"],
        .insurance: ["policy number", "premium", "insured", "sum insured", "policy period", "insurer", "coverage", "policyholder", "claim"],
        .bill: ["bill", "due date", "amount due", "consumption", "units", "meter", "billing period", "electricity", "broadband", "postpaid", "usage charges", "late fee"],
        .invoice: ["invoice", "tax invoice", "gstin", "hsn", "bill to", "ship to", "invoice number", "invoice no", "igst", "cgst", "sgst"],
        .orderConfirmation: ["order confirmation", "order confirmed", "order placed", "order total", "order date", "your order", "order number", "order #", "order id", "estimated delivery", "arriving", "shipped", "order summary"],
        .receipt: ["receipt", "thank you for shopping", "cash", "change", "paid", "transaction", "pos", "card ending", "total"],
        .quote: ["quotation", "quote", "estimate", "valid for", "proposal", "quoted price"],
        .contract: ["agreement", "contract", "terms and conditions", "term of", "lock-in", "party", "hereby", "signed"],
        .financial: ["statement", "account number", "ifsc", "opening balance", "closing balance", "emi", "interest", "loan", "credit limit", "minimum due"],
    ]

    func classify(_ text: String) -> (DocumentType, Double) {
        let lower = text.lowercased()
        var scores: [DocumentType: Double] = [:]
        for (type, keywords) in Self.signals {
            var score = 0.0
            for keyword in keywords where lower.contains(keyword) {
                // Multi-word keywords are stronger evidence.
                score += keyword.contains(" ") || keyword.contains("/") ? 2.0 : 1.0
            }
            scores[type] = score
        }
        // Receipts are the default; damp their weak generic keywords so specific types win.
        scores[.receipt] = (scores[.receipt] ?? 0) * 0.6
        guard let best = scores.max(by: { $0.value < $1.value }), best.value > 0 else { return (.unknown, 0.3) }
        let total = scores.values.reduce(0, +)
        let share = total > 0 ? best.value / total : 0
        let confidence = min(0.95, 0.45 + share * 0.5 + min(best.value, 6) * 0.03)
        return (best.key, confidence)
    }
}
