import Foundation
import NaturalLanguage

/// Turns recognised text into a `PurchaseDocument`. Every field carries a confidence so the review screen can
/// show the user exactly what to double-check. Nothing here invents data: missing means missing.
struct DocumentParser {
    let directory = MerchantDirectory()
    let amounts = AmountParser()
    let dates = DateParser()
    let classifier = DocumentClassifier()

    private static let orderNumber = Pattern(#"(?:order\s*(?:id|no\.?|number|#)?|order)\s*[:#\-]?\s*([A-Z0-9][A-Z0-9\-]{5,})"#)
    private static let invoiceNumber = Pattern(#"(?:invoice|inv\.?)\s*(?:no\.?|number|#)?\s*[:#\-]?\s*([A-Z0-9][A-Z0-9\/\-]{3,})"#)
    private static let serialNumber = Pattern(#"(?:serial\s*(?:no\.?|number|#)?|s\/n|imei)\s*[:#\-]?\s*([A-Z0-9][A-Z0-9\-]{7,})"#)
    private static let policyNumber = Pattern(#"policy\s*(?:no\.?|number|#)?\s*[:#\-]?\s*([A-Z0-9][A-Z0-9\/\-]{4,})"#)
    private static let bookingRef = Pattern(#"(?:pnr|booking\s*(?:id|ref(?:erence)?|no\.?|number)|confirmation\s*(?:no\.?|number|#|code)|reference\s*(?:no\.?|number|#))\s*[:#\-]?\s*([A-Z0-9][A-Z0-9\-]{4,})"#)
    private static let warrantyDuration = Pattern(#"(\d{1,2})\s*[- ]?\s*(year|yr|month|mo)s?\s+(?:[A-Za-z'\-]+\s+){0,3}?(?:warranty|guarantee|coverage)"#)
    private static let warrantyDurationAfter = Pattern(#"(?:warranty|guarantee|coverage)\s*(?:period|of|:)?\s*(\d{1,2})\s*[- ]?\s*(year|yr|month|mo)s?"#)
    private static let cardEnding = Pattern(#"(visa|mastercard|master card|amex|american express|rupay|debit card|credit card|upi|paypal|apple pay|google pay|gpay|phonepe|paytm|net ?banking|cash on delivery|cod\b|emi)(?:.*?(?:ending|ending in|xx|\*{2,})\s*(\d{4}))?"#)
    private static let previousPrice = Pattern(#"(?:previous(?:ly)?|old price|was|from|current price|currently)\s*[:\-]?\s*(₹|Rs\.?|INR|\$|€|£)\s?(\d{1,3}(?:[,\s]\d{2,3})*(?:\.\d{1,2})?|\d+(?:\.\d{1,2})?)"#)
    private static let quantity = Pattern(#"(?:qty|quantity)\s*[:\-]?\s*(\d{1,3})|(?:^|\s)(\d{1,3})\s*[x×]\s|\s[x×]\s*(\d{1,3})(?:\s|$)"#)
    private static let productKeywords = ["macbook", "iphone", "ipad", "airpods", "apple watch", "galaxy", "pixel", "laptop", "tv", "television", "refrigerator", "washing machine", "camera", "headphones", "monitor", "playstation", "xbox", "nintendo", "oneplus", "dyson", "kindle", "speaker", "tablet", "printer", "sofa", "mattress", "watch", "shoes", "jacket"]

    func parse(_ recognized: RecognizedText, currencyCode fallbackCurrency: String, sourceURL: URL? = nil) -> PurchaseDocument {
        let lines = recognized.lines.map { $0.squashedWhitespace }.filter { !$0.isEmpty }
        let text = lines.joined(separator: "\n")
        let ocr = max(0.35, min(1.0, recognized.averageConfidence == 0 ? 0.9 : recognized.averageConfidence))

        var doc = PurchaseDocument(rawText: text, currencyCode: fallbackCurrency)
        var fc: [String: Double] = [:]

        // 1. Document type
        let (type, typeConfidence) = classifier.classify(text)
        doc.documentType = type
        fc["documentType"] = typeConfidence * ocr

        // 2. Merchant
        if let entry = directory.match(in: text) {
            doc.merchant = entry.name
            doc.merchantCategory = entry.category
            fc["merchant"] = 0.95 * ocr
        } else if let (name, confidence) = inferMerchant(from: lines, sourceURL: sourceURL) {
            doc.merchant = name
            doc.merchantCategory = inferCategory(text: text, type: type)
            fc["merchant"] = confidence * ocr
        } else {
            doc.merchantCategory = inferCategory(text: text, type: type)
        }

        // 3. Amounts
        let found = amounts.amounts(in: lines)
        doc.currencyCode = amounts.dominantCurrency(in: found, fallback: fallbackCurrency)
        if let (total, confidence) = amounts.total(from: found) {
            doc.amount = total.value
            fc["amount"] = confidence * ocr
        }

        // 4. Dates
        let parsedDates = dates.dates(in: lines)
        assignDates(parsedDates, to: &doc, confidences: &fc, ocr: ocr)

        // 5. Subscription
        if let sub = subscriptionInfo(text: text, lines: lines, doc: doc) {
            doc.subscription = sub
            if doc.documentType == .receipt || doc.documentType == .unknown || doc.documentType == .orderConfirmation {
                doc.documentType = .subscription
            }
            fc["subscription"] = (sub.nextBillingDate != nil ? 0.85 : 0.7) * ocr
        }

        // 6. Warranty
        doc.warranties = warranties(text: text, doc: doc, ocr: ocr)
        if !doc.warranties.isEmpty { fc["warranty"] = Double(doc.warranties.first?.confidence.weight ?? 0.5) * ocr }

        // 7. Identifiers
        if let v = Self.identifier(Self.orderNumber, in: text) { doc.orderNumber = v; fc["orderNumber"] = 0.85 * ocr }
        if let v = Self.identifier(Self.invoiceNumber, in: text) { doc.invoiceNumber = v; fc["invoiceNumber"] = 0.85 * ocr }
        if let v = Self.identifier(Self.serialNumber, in: text) { doc.serialNumber = v; fc["serialNumber"] = 0.85 * ocr }
        if let v = Self.identifier(Self.policyNumber, in: text) { doc.policyNumber = v; fc["policyNumber"] = 0.85 * ocr }
        if let v = Self.identifier(Self.bookingRef, in: text) { doc.referenceNumber = v; fc["referenceNumber"] = 0.85 * ocr }

        // 8. Payment method
        if let m = Self.cardEnding.firstMatch(in: text), let method = m[1] {
            var label = method.capitalized
            if label.lowercased() == "upi" { label = "UPI" }
            if let last4 = m.count > 2 ? m[2] : nil { label += " ending \(last4)" }
            doc.paymentMethod = label
            fc["paymentMethod"] = 0.8 * ocr
        }

        // 9. Line items
        doc.items = lineItems(lines: lines, found: found, total: doc.amount)

        // 10. Title
        let (title, titleConfidence) = productTitle(lines: lines, doc: doc)
        doc.productTitle = title
        if title != nil { fc["productTitle"] = titleConfidence * ocr }

        if let sourceURL { doc.productURL = sourceURL.absoluteString }

        // 10b. UPI receipts and bank debit SMS are highly structured — let them override the generic read.
        if let payment = PaymentMessageParser.parse(text, defaultCurrency: fallbackCurrency), payment.isDebit, payment.amount != nil {
            if let merchant = payment.merchant, doc.merchant == nil || (fc["merchant"] ?? 0) < 0.95 {
                doc.merchant = merchant
                doc.merchantCategory = directory.entry(named: merchant)?.category ?? doc.merchantCategory
                fc["merchant"] = 0.9 * ocr
            }
            doc.amount = payment.amount
            doc.currencyCode = payment.currencyCode
            fc["amount"] = 0.95 * ocr
            if let date = payment.date { doc.purchaseDate = date; fc["purchaseDate"] = 0.9 * ocr }
            doc.paymentMethod = payment.app.map { "UPI · \($0)" } ?? (payment.bankAccountHint.map { "UPI · \($0)" } ?? "UPI")
            fc["paymentMethod"] = 0.9 * ocr
            if doc.referenceNumber == nil { doc.referenceNumber = payment.reference }
            if doc.documentType == .unknown || doc.documentType == .financial { doc.documentType = .receipt }
            doc.tags.append("upi")
            if doc.productTitle == nil || doc.productTitle == doc.merchant { doc.productTitle = doc.merchant.map { "Payment to \($0)" } }
        }

        // 11. Overall confidence: the fields that matter most, weighted.
        let core: [Double] = [fc["merchant"] ?? 0.0, fc["amount"] ?? 0.0, fc["purchaseDate"] ?? 0.4]
        let overall = core.reduce(0, +) / Double(core.count)
        doc.fieldConfidences = fc
        doc.overallConfidence = Confidence(score: overall)
        doc.tags = tags(for: doc)
        return doc
    }

    // MARK: - Helpers

    private func inferMerchant(from lines: [String], sourceURL: URL?) -> (String, Double)? {
        if let host = sourceURL?.host?.replacingOccurrences(of: "www.", with: "") {
            let name = host.split(separator: ".").first.map(String.init)?.capitalized ?? host
            return (name, 0.7)
        }
        // Email sender domain: "orders@zomato.com"
        if let m = Pattern(#"@([a-z0-9\-]+)\.(?:com|in|co|io|net|org)"#).firstMatch(in: lines.joined(separator: " ")), let domain = m[1], domain.count > 2, !["gmail", "yahoo", "outlook", "icloud", "hotmail"].contains(domain) {
            return (domain.capitalized, 0.7)
        }
        // Named organisations via NaturalLanguage.
        let tagger = NLTagger(tagSchemes: [.nameType])
        let head = lines.prefix(12).joined(separator: "\n")
        tagger.string = head
        var org: String?
        tagger.enumerateTags(in: head.startIndex..<head.endIndex, unit: .word, scheme: .nameType, options: [.omitPunctuation, .omitWhitespace, .joinNames]) { tag, range in
            if tag == .organizationName {
                org = String(head[range])
                return false
            }
            return true
        }
        if let org, org.count > 2 { return (org, 0.6) }
        // First short, mostly-alphabetic line — classic receipt header.
        for line in lines.prefix(4) {
            let letters = line.filter(\.isLetter).count
            if line.count <= 32, letters >= 3, Double(letters) / Double(line.count) > 0.6, !line.lowercased().containsAny(["receipt", "invoice", "tax", "total", "order", "thank", "date"]) {
                return (line.capitalized, 0.45)
            }
        }
        return nil
    }

    private func inferCategory(text: String, type: DocumentType) -> MerchantCategory {
        let lower = text.lowercased()
        if lower.containsAny(["hotel", "flight", "pnr", "check-in", "airline", "resort", "trip"]) { return .travel }
        if lower.containsAny(["insurance", "policy", "insured", "premium"]) { return .insurance }
        if lower.containsAny(["broadband", "fiber", "postpaid", "prepaid", "mobile plan", "data plan"]) { return .telecom }
        if lower.containsAny(["electricity", "water bill", "gas bill", "units consumed", "meter"]) { return .utilities }
        if lower.containsAny(Self.productKeywords.filter { !["shoes", "jacket", "sofa", "mattress", "watch"].contains($0) }) { return .electronics }
        if lower.containsAny(["stream", "premium plan", "membership", "cloud storage", "software", "license"]) { return type == .subscription ? .streaming : .software }
        if lower.containsAny(["shoes", "jacket", "t-shirt", "dress", "apparel"]) { return .fashion }
        if lower.containsAny(["grocery", "vegetables", "milk", "restaurant", "food"]) { return .groceries }
        return .other
    }

    private func assignDates(_ parsed: [ParsedDate], to doc: inout PurchaseDocument, confidences fc: inout [String: Double], ocr: Double) {
        let now = Date.now
        func pick(_ label: String) -> ParsedDate? {
            parsed.first { $0.label == label && $0.explicit } ?? parsed.first { $0.label == label }
        }
        if let d = pick("purchase") { doc.purchaseDate = d.date; fc["purchaseDate"] = (d.explicit ? 0.9 : 0.7) * ocr }
        if let d = pick("renewal") { doc.renewalDate = d.date; fc["renewalDate"] = (d.explicit ? 0.9 : 0.7) * ocr }
        if let d = pick("returnDeadline") { doc.returnDeadline = d.date; fc["returnDeadline"] = (d.explicit ? 0.9 : 0.7) * ocr }
        if let d = pick("service") { doc.serviceDate = d.date; fc["serviceDate"] = (d.explicit ? 0.85 : 0.65) * ocr }
        if let d = pick("booking") { doc.bookingDate = d.date; fc["bookingDate"] = 0.85 * ocr }

        // Unlabelled fallback: the earliest past-or-today date is very likely the transaction date.
        if doc.purchaseDate == nil {
            let unlabelled = parsed.filter { $0.label == nil && $0.date <= now }
            if let earliest = unlabelled.min(by: { $0.date < $1.date }) {
                doc.purchaseDate = earliest.date
                fc["purchaseDate"] = (unlabelled.count == 1 ? 0.7 : 0.5) * ocr
            }
        }
        // A future unlabelled date on a subscription-ish document is probably the renewal.
        if doc.renewalDate == nil, doc.documentType == .subscription || doc.documentType == .renewalNotice {
            if let future = parsed.filter({ $0.label == nil && $0.date > now }).min(by: { $0.date < $1.date }) {
                doc.renewalDate = future.date
                fc["renewalDate"] = 0.55 * ocr
            }
        }
    }

    private func subscriptionInfo(text: String, lines: [String], doc: PurchaseDocument) -> PurchaseDocument.SubscriptionInfo? {
        let lower = text.lowercased()
        var cycle: BillingCycle?
        if lower.containsAny(["/month", "per month", "monthly", "/mo", "every month", "a month"]) { cycle = .monthly }
        else if lower.containsAny(["/year", "per year", "annually", "yearly", "/yr", "annual plan", "every year"]) { cycle = .yearly }
        else if lower.containsAny(["quarterly", "every 3 months", "/quarter"]) { cycle = .quarterly }
        else if lower.containsAny(["/week", "weekly", "per week"]) { cycle = .weekly }

        let isSubscriptionLike = doc.documentType == .subscription || doc.documentType == .renewalNotice || lower.containsAny(["subscription", "renew", "membership", "your plan"])
        guard isSubscriptionLike, let cycle else { return nil }

        var previous: Decimal?
        if let m = Self.previousPrice.firstMatch(in: text), let number = m[2], let value = AmountParser.parseDecimal(number), let current = doc.amount, value != current {
            previous = value
        }
        return PurchaseDocument.SubscriptionInfo(billingCycle: cycle, nextBillingDate: doc.renewalDate, previousPrice: previous)
    }

    private func warranties(text: String, doc: PurchaseDocument, ocr: Double) -> [PurchaseDocument.WarrantyInfo] {
        var months: Int?
        if let m = Self.warrantyDuration.firstMatch(in: text) ?? Self.warrantyDurationAfter.firstMatch(in: text), let n = m[1], let unit = m[2], let value = Int(n) {
            months = unit.lowercased().hasPrefix("y") ? value * 12 : value
        }
        let explicitEnd = DateParser().dates(in: text.components(separatedBy: "\n")).first { $0.label == "warrantyEnd" }?.date
        guard months != nil || explicitEnd != nil else { return [] }

        let provider = text.lowercased().contains("applecare") ? "AppleCare" : (doc.merchant ?? "Manufacturer")
        let type: WarrantyType = text.lowercased().containsAny(["applecare", "extended", "protection plan"]) ? .extended : .manufacturer
        var end = explicitEnd
        if end == nil, let months, let start = doc.purchaseDate { end = DateMath.adding(months: months, to: start) }
        let confidence: Confidence = explicitEnd != nil ? .high : (doc.purchaseDate != nil ? .medium : .low)
        return [PurchaseDocument.WarrantyInfo(provider: provider, type: type, months: months, endDate: end, source: explicitEnd != nil ? "Stated in document" : "Duration stated in document", confidence: confidence)]
    }

    private func lineItems(lines: [String], found: [ParsedAmount], total: Decimal?) -> [PurchaseDocument.LineItem] {
        var items: [PurchaseDocument.LineItem] = []
        for amount in found where amount.value != total {
            let lower = amount.line.lowercased()
            if AmountParser.totalKeywords.contains(where: { lower.contains($0) }) || AmountParser.nonItemWords.contains(where: { lower.contains($0) }) { continue }
            var name = amount.line
            // Strip the price and currency from the line to leave the description.
            for token in ["₹", "Rs.", "Rs", "INR", "$", "USD", "€", "EUR", "£", "GBP"] { name = name.replacingOccurrences(of: token, with: " ") }
            name = name.replacingOccurrences(of: #"[\d,]+(\.\d{1,2})?"#, with: " ", options: .regularExpression).squashedWhitespace
            name = name.trimmingCharacters(in: CharacterSet(charactersIn: " -:xX×@"))
            guard name.count >= 3, name.filter(\.isLetter).count >= 3 else { continue }
            var qty = 1
            if let m = Self.quantity.firstMatch(in: amount.line) {
                qty = m.dropFirst().compactMap { $0 }.compactMap(Int.init).first ?? 1
            }
            items.append(PurchaseDocument.LineItem(name: name, quantity: max(1, qty), unitPrice: amount.value))
            if items.count >= 12 { break }
        }
        return items
    }

    private func productTitle(lines: [String], doc: PurchaseDocument) -> (String?, Double) {
        let lower = lines.map { $0.lowercased() }
        if let index = lower.firstIndex(where: { line in Self.productKeywords.contains { line.contains($0) } }) {
            let candidate = lines[index]
                .replacingOccurrences(of: #"(₹|Rs\.?|INR|\$|€|£)\s?[\d,]+(\.\d{1,2})?"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"(?i)\b(qty|quantity)\b.*$"#, with: "", options: .regularExpression)
                .squashedWhitespace
            if candidate.count >= 4 && candidate.count <= 70 { return (candidate, 0.75) }
        }
        if let first = doc.items.first, first.name.count <= 70 { return (first.name, 0.6) }
        switch doc.documentType {
        case .subscription, .renewalNotice: return (doc.merchant.map { "\($0) subscription" }, 0.7)
        case .booking:
            if let hotel = lines.first(where: { $0.lowercased().containsAny(["hotel", "resort", "villa", "inn", "suites"]) && $0.count < 60 }) { return (hotel, 0.65) }
            return (doc.merchant.map { "\($0) booking" }, 0.6)
        case .insurance: return (doc.merchant.map { "\($0) policy" }, 0.6)
        case .bill: return (doc.merchant.map { "\($0) bill" }, 0.6)
        default: return (doc.merchant, 0.5)
        }
    }

    private func tags(for doc: PurchaseDocument) -> [String] {
        var tags: [String] = [doc.documentType.displayName.lowercased()]
        if doc.subscription != nil { tags.append("subscription") }
        if !doc.warranties.isEmpty { tags.append("warranty") }
        if doc.paymentMethod?.uppercased().contains("UPI") == true { tags.append("upi") }
        if doc.merchantCategory != .other { tags.append(doc.merchantCategory.rawValue) }
        return Array(Set(tags)).sorted()
    }

    /// First capture that actually looks like an identifier (so "Order Confirmation" never wins over "Order # 405-…").
    private static func identifier(_ pattern: Pattern, in text: String) -> String? {
        for groups in pattern.allMatches(in: text) {
            if let value = groups.count > 1 ? groups[1] : nil, looksLikeIdentifier(value) { return value }
        }
        return nil
    }

    private static func looksLikeIdentifier(_ value: String) -> Bool {
        let hasDigit = value.contains { $0.isNumber }
        return hasDigit && value.count >= 4 && value.count <= 40
    }
}
