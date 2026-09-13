import Foundation

/// What a merchant-presented payment QR says. Parsed, never guessed — missing fields stay nil.
struct PaymentRequest: Equatable, Sendable {
    var rail: String                 // "UPI", "PIX", …
    var merchantName: String?
    var payeeAddress: String?        // UPI VPA, PIX key, PayNow proxy…
    var amount: Decimal?
    var currencyCode: String
    var note: String?
    var reference: String?
    var countryCode: String?
    var rawPayload: String

    var isPayable: Bool { payeeAddress != nil || merchantName != nil }
}

enum PaymentQRParser {
    /// Accepts a UPI URL, an EMVCo TLV string, or a payment-app share link. Returns nil for unrelated QR content.
    static func parse(_ payload: String, defaultCurrency: String) -> PaymentRequest? {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        if let upi = parseUPI(trimmed) { return upi }
        if let emv = parseEMVCo(trimmed, defaultCurrency: defaultCurrency) { return emv }
        return nil
    }

    // MARK: UPI (India) — upi://pay?pa=merchant@bank&pn=Name&am=100.00&cu=INR&tn=Note&tr=Ref

    static func parseUPI(_ payload: String) -> PaymentRequest? {
        let lower = payload.lowercased()
        guard lower.hasPrefix("upi://pay") || lower.contains("://upi/pay") || lower.hasPrefix("phonepe://pay") || lower.hasPrefix("paytmmp://pay") else { return nil }
        guard let components = URLComponents(string: payload) else { return nil }
        var params: [String: String] = [:]
        for item in components.queryItems ?? [] { params[item.name.lowercased()] = item.value?.removingPercentEncoding ?? item.value }
        guard let pa = params["pa"], pa.contains("@") else { return nil }
        return PaymentRequest(
            rail: "UPI",
            merchantName: params["pn"]?.replacingOccurrences(of: "+", with: " ").squashedWhitespace,
            payeeAddress: pa,
            amount: params["am"].flatMap(AmountParser.parseDecimal).flatMap { $0 > 0 ? $0 : nil },
            currencyCode: params["cu"]?.uppercased() ?? "INR",
            note: params["tn"],
            reference: params["tr"] ?? params["tid"],
            countryCode: "IN",
            rawPayload: payload
        )
    }

    /// Builds a UPI pay URL for a given app template, carrying the (possibly user-entered) amount.
    static func upiURL(for request: PaymentRequest, template: String, amount: Decimal?) -> URL? {
        guard let pa = request.payeeAddress else { return nil }
        var items: [URLQueryItem] = [URLQueryItem(name: "pa", value: pa)]
        if let pn = request.merchantName { items.append(URLQueryItem(name: "pn", value: pn)) }
        if let amount, amount > 0 { items.append(URLQueryItem(name: "am", value: "\(amount)")) }
        items.append(URLQueryItem(name: "cu", value: request.currencyCode))
        if let note = request.note { items.append(URLQueryItem(name: "tn", value: note)) }
        if let ref = request.reference { items.append(URLQueryItem(name: "tr", value: ref)) }
        var components = URLComponents()
        components.queryItems = items
        guard let query = components.percentEncodedQuery else { return nil }
        return URL(string: template + query)
    }

    // MARK: EMVCo merchant-presented QR (PIX, PayNow, PromptPay, DuitNow, QRIS, …)
    // TLV: 2-digit tag, 2-digit length, value. Tag 59 = merchant name, 54 = amount, 53 = currency (ISO numeric), 58 = country, 60 = city.

    static func parseEMVCo(_ payload: String, defaultCurrency: String) -> PaymentRequest? {
        guard payload.hasPrefix("000201"), payload.count >= 20 else { return nil }
        let tlv = parseTLV(payload)
        guard !tlv.isEmpty, tlv["59"] != nil || (26...51).contains(where: { tlv[String(format: "%02d", $0)] != nil }) else { return nil }
        let country = tlv["58"]?.uppercased()
        let currency = tlv["53"].flatMap(currencyCode(numeric:)) ?? defaultCurrency
        let rail: String
        switch country {
        case "BR": rail = "PIX"
        case "SG": rail = "PayNow"
        case "TH": rail = "PromptPay"
        case "MY": rail = "DuitNow"
        case "ID": rail = "QRIS"
        case "IN": rail = "UPI"
        default: rail = "QR payment"
        }
        // Payee proxy lives inside the merchant-account template (tags 26–51), sub-tag 01 typically.
        var payee: String?
        for tag in 26...51 {
            if let nested = tlv[String(format: "%02d", tag)] {
                let sub = parseTLV(nested)
                payee = sub["01"] ?? sub["02"] ?? sub["25"] ?? payee
                if payee != nil { break }
            }
        }
        let additional = tlv["62"].map(parseTLV)
        return PaymentRequest(
            rail: rail,
            merchantName: tlv["59"]?.squashedWhitespace,
            payeeAddress: payee,
            amount: tlv["54"].flatMap(AmountParser.parseDecimal),
            currencyCode: currency,
            note: additional?["08"] ?? additional?["02"],
            reference: additional?["05"] ?? additional?["01"],
            countryCode: country,
            rawPayload: payload
        )
    }

    static func parseTLV(_ s: String) -> [String: String] {
        var result: [String: String] = [:]
        var index = s.startIndex
        while s.distance(from: index, to: s.endIndex) >= 4 {
            let tag = String(s[index..<s.index(index, offsetBy: 2)])
            guard let length = Int(s[s.index(index, offsetBy: 2)..<s.index(index, offsetBy: 4)]) else { break }
            let valueStart = s.index(index, offsetBy: 4)
            guard s.distance(from: valueStart, to: s.endIndex) >= length else { break }
            let valueEnd = s.index(valueStart, offsetBy: length)
            result[tag] = String(s[valueStart..<valueEnd])
            index = valueEnd
        }
        return result
    }

    static func currencyCode(numeric: String) -> String? {
        ["356": "INR", "986": "BRL", "702": "SGD", "764": "THB", "458": "MYR", "360": "IDR", "840": "USD", "978": "EUR", "826": "GBP", "784": "AED", "036": "AUD", "124": "CAD", "392": "JPY", "156": "CNY", "608": "PHP", "704": "VND"][numeric]
    }
}
