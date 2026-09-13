import Foundation

/// Real-time "scan and pay" rails by country. LEVER never moves money — it parses the merchant's QR, hands off to
/// the user's own payment app, and logs the spend when they come back.
enum PaymentRegion: String, CaseIterable, Codable, Identifiable {
    case india, brazil, singapore, thailand, malaysia, indonesia, other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .india: "India · UPI"
        case .brazil: "Brazil · PIX"
        case .singapore: "Singapore · PayNow"
        case .thailand: "Thailand · PromptPay"
        case .malaysia: "Malaysia · DuitNow"
        case .indonesia: "Indonesia · QRIS"
        case .other: "Other · EMVCo QR"
        }
    }

    var railName: String {
        switch self {
        case .india: "UPI"
        case .brazil: "PIX"
        case .singapore: "PayNow"
        case .thailand: "PromptPay"
        case .malaysia: "DuitNow"
        case .indonesia: "QRIS"
        case .other: "QR payment"
        }
    }

    var currencyCode: String {
        switch self {
        case .india: "INR"
        case .brazil: "BRL"
        case .singapore: "SGD"
        case .thailand: "THB"
        case .malaysia: "MYR"
        case .indonesia: "IDR"
        case .other: Money.defaultCurrencyCode
        }
    }

    /// Picks a region from the device locale; the user can override in Settings.
    static func detect(locale: Locale = .current) -> PaymentRegion {
        switch locale.region?.identifier {
        case "IN": .india
        case "BR": .brazil
        case "SG": .singapore
        case "TH": .thailand
        case "MY": .malaysia
        case "ID": .indonesia
        default: .other
        }
    }

    /// Payment apps LEVER can hand off to. Only UPI has an interoperable URL scheme; other rails use "copy code".
    var apps: [PaymentApp] {
        switch self {
        case .india:
            return [
                PaymentApp(name: "Google Pay", scheme: "gpay", template: "gpay://upi/pay?"),
                PaymentApp(name: "PhonePe", scheme: "phonepe", template: "phonepe://pay?"),
                PaymentApp(name: "Paytm", scheme: "paytmmp", template: "paytmmp://pay?"),
                PaymentApp(name: "BHIM", scheme: "bhim", template: "bhim://pay?"),
                PaymentApp(name: "CRED", scheme: "cred", template: "cred://upi/pay?"),
                PaymentApp(name: "Any UPI app", scheme: "upi", template: "upi://pay?"),
            ]
        case .brazil: return [PaymentApp(name: "Nubank", scheme: "nubank", template: nil), PaymentApp(name: "Your bank app", scheme: nil, template: nil)]
        case .singapore: return [PaymentApp(name: "DBS PayLah!", scheme: "paylah", template: nil), PaymentApp(name: "Your bank app", scheme: nil, template: nil)]
        case .thailand, .malaysia, .indonesia, .other: return [PaymentApp(name: "Your bank / wallet app", scheme: nil, template: nil)]
        }
    }

    /// Whether QR payloads here are UPI URLs (India) or EMVCo merchant-presented TLV (everyone else).
    var usesUPIURL: Bool { self == .india }
}

struct PaymentApp: Identifiable, Equatable {
    var id: String { name }
    let name: String
    /// URL scheme to test with canOpenURL (declared in LSApplicationQueriesSchemes). nil = no deep link.
    let scheme: String?
    /// Prefix for a UPI pay URL; the UPI query string is appended verbatim.
    let template: String?
}
