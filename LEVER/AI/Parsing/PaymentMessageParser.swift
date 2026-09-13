import Foundation

/// Understands the two most common records of everyday spending in UPI countries: payment-app receipts
/// (Google Pay / PhonePe / Paytm / BHIM screens) and bank debit SMS. Both are highly structured, so confidence is high.
struct PaymentMessage: Equatable {
    var app: String?              // "Google Pay", "PhonePe", …
    var merchant: String?
    var payeeAddress: String?     // VPA
    var amount: Decimal?
    var currencyCode: String
    var date: Date?
    var reference: String?        // UPI transaction ID / UTR
    var bankAccountHint: String?  // "XX1234"
    var isDebit: Bool
}

enum PaymentMessageParser {
    private static let appMarkers: [(String, [String])] = [
        ("Google Pay", ["google pay", "gpay", "g pay", "tez"]),
        ("PhonePe", ["phonepe", "phone pe"]),
        ("Paytm", ["paytm"]),
        ("BHIM", ["bhim"]),
        ("Amazon Pay", ["amazon pay", "amazonpay"]),
        ("CRED", ["cred upi", "cred pay"]),
        ("WhatsApp Pay", ["whatsapp pay", "whatsapp"]),
    ]
    private static let vpa = Pattern(#"\b([a-z0-9._-]{2,}@[a-z][a-z0-9]{1,})\b"#)
    // Terminators are word-bounded so "Roasters" isn't cut at "rs" (rupees).
    private static let paidTo = Pattern(#"\b(?:paid to|payment to|to:|sent to|transferred to|paid|to)\s*[:\-]?\s*([A-Z][A-Za-z0-9&.' \-]{2,48}?)(?:\s*(?:\n|₹|\brs\.?\s?\d|\binr\b|\bupi\b|\bvpa\b|\bon\b|\bvia\b|•|\||$))"#)
    private static let smsDebit = Pattern(#"(?:rs\.?|inr|₹)\s?([\d,]+(?:\.\d{1,2})?)\s*(?:has been |is |was )?(?:debited|deducted|paid|sent|spent)"#)
    private static let smsDebit2 = Pattern(#"(?:debited|deducted|paid|sent|spent)\s*(?:by|with|for|of)?\s*(?:rs\.?|inr|₹)\s?([\d,]+(?:\.\d{1,2})?)"#)
    private static let account = Pattern(#"(?:a/c|acct|account|card)\s*(?:no\.?)?\s*[:\-]?\s*(?:x+|\*+|ending(?: in)?)?\s*(\d{3,6})"#)
    private static let reference = Pattern(#"(?:upi(?: ref| txn| transaction)?(?: no| id| number)?|utr|txn(?: id| no)?|transaction id|ref(?:erence)? no|rrn)\s*[:\-#]?\s*([0-9]{9,22}|[A-Z0-9]{12,26})"#)
    private static let toVPA = Pattern(#"\b(?:to|vpa|payee)\b\s*[:\-]?\s*([a-z0-9._-]{2,}@[a-z][a-z0-9]{1,})"#)
    private static let successWords = ["paid successfully", "payment successful", "transaction successful", "completed", "success", "debited", "sent successfully", "paid to", "credited", "received from", "refunded"]

    /// Returns nil when the text doesn't look like a payment record at all.
    static func parse(_ text: String, defaultCurrency: String) -> PaymentMessage? {
        let lower = text.lowercased()
        let hasVPA = vpa.matches(lower)
        let hasUPIWord = lower.contains("upi") || lower.contains("utr") || lower.contains("vpa")
        let app = appMarkers.first { _, markers in markers.contains { lower.contains($0) } }?.0
        let looksLikePayment = (hasVPA || hasUPIWord || app != nil) && successWords.contains { lower.contains($0) }
        guard looksLikePayment else { return nil }

        // Amount: SMS phrasing first, then the largest currency figure in the text.
        var amount: Decimal?
        if let m = smsDebit.firstMatch(in: lower) ?? smsDebit2.firstMatch(in: lower), let raw = m[1] { amount = AmountParser.parseDecimal(raw) }
        let parsed = AmountParser().amounts(in: text.components(separatedBy: .newlines))
        if amount == nil { amount = parsed.max { $0.value < $1.value }?.value }
        let currency = parsed.compactMap(\.currencyCode).first ?? (hasUPIWord || app != nil ? "INR" : defaultCurrency)

        // Payee: VPA after "to", else any VPA that isn't the payer's own.
        var payee = toVPA.firstMatch(in: lower)?[1]
        if payee == nil, let m = vpa.firstMatch(in: lower) { payee = m[1] }
        // Merchant name: "Paid to Blue Tokai Coffee" or the VPA's handle when nothing better.
        var merchant: String?
        if let m = paidTo.firstMatch(in: text), let name = m[1]?.squashedWhitespace, name.count >= 3, !name.lowercased().contains("@") {
            merchant = name
        }
        if merchant == nil, let payee { merchant = Self.merchantName(fromVPA: payee) }
        if let name = merchant, let entry = MerchantDirectory().match(in: name) { merchant = entry.name }

        let date = DateParser().dates(in: text.components(separatedBy: .newlines)).first?.date
        let reference = reference.firstMatch(in: text)?[1]
        let accountHint = account.firstMatch(in: lower)?[1].map { "XX\($0)" }
        let isCredit = lower.contains("credited") || lower.contains("received from") || lower.contains("refund")
        return PaymentMessage(app: app, merchant: merchant, payeeAddress: payee, amount: amount, currencyCode: currency, date: date, reference: reference, bankAccountHint: accountHint, isDebit: !isCredit)
    }

    /// "netflix.upi@icici" → "Netflix"; "paytmqr2810…@paytm" → nil (opaque merchant ids aren't names).
    static func merchantName(fromVPA vpa: String) -> String? {
        let handle = vpa.split(separator: "@").first.map(String.init) ?? vpa
        let cleaned = handle.replacingOccurrences(of: #"[._-]?(upi|pay|payments|qr\d*|\d{4,})"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[._-]+"#, with: " ", options: .regularExpression).squashedWhitespace
        guard cleaned.count >= 3, cleaned.rangeOfCharacter(from: .letters) != nil, !cleaned.lowercased().hasPrefix("paytmqr") else { return nil }
        if let entry = MerchantDirectory().match(in: cleaned) { return entry.name }
        return cleaned.capitalized
    }
}
