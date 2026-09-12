import Foundation
import SwiftUI

// MARK: - Documents

enum DocumentType: String, Codable, CaseIterable, Identifiable {
    case receipt, invoice, subscription, bill, booking, warranty, insurance, quote
    case orderConfirmation, renewalNotice, contract, financial, unknown

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .receipt: "Receipt"
        case .invoice: "Invoice"
        case .subscription: "Subscription"
        case .bill: "Bill"
        case .booking: "Booking"
        case .warranty: "Warranty"
        case .insurance: "Insurance"
        case .quote: "Quote"
        case .orderConfirmation: "Order confirmation"
        case .renewalNotice: "Renewal notice"
        case .contract: "Contract"
        case .financial: "Financial document"
        case .unknown: "Document"
        }
    }

    var symbol: String {
        switch self {
        case .receipt: "receipt"
        case .invoice: "doc.text"
        case .subscription: "arrow.triangle.2.circlepath"
        case .bill: "bolt.fill"
        case .booking: "airplane"
        case .warranty: "shield.checkered"
        case .insurance: "umbrella.fill"
        case .quote: "quote.opening"
        case .orderConfirmation: "shippingbox.fill"
        case .renewalNotice: "bell.badge.fill"
        case .contract: "signature"
        case .financial: "building.columns.fill"
        case .unknown: "doc"
        }
    }
}

enum MerchantCategory: String, Codable, CaseIterable {
    case electronics, streaming, software, travel, insurance, utilities, telecom, retail, groceries, fashion, home, automotive, health, other

    var displayName: String { rawValue.capitalized }
}

// MARK: - Confidence & trust

enum Confidence: String, Codable, CaseIterable, Comparable {
    case low, medium, high

    private var rank: Int {
        switch self {
        case .low: 0
        case .medium: 1
        case .high: 2
        }
    }

    static func < (lhs: Confidence, rhs: Confidence) -> Bool { lhs.rank < rhs.rank }

    var displayName: String {
        switch self {
        case .low: "Low confidence"
        case .medium: "Medium confidence"
        case .high: "High confidence"
        }
    }

    var weight: Double {
        switch self {
        case .low: 0.55
        case .medium: 0.8
        case .high: 1.0
        }
    }

    init(score: Double) {
        if score >= 0.8 { self = .high } else if score >= 0.5 { self = .medium } else { self = .low }
    }
}

/// How a piece of evidence should be read. Displayed to the user — never blur these together.
enum EvidenceKind: String, Codable, CaseIterable {
    case fact, inference, possibility, userInput, unverified

    var displayName: String {
        switch self {
        case .fact: "Fact"
        case .inference: "Inference"
        case .possibility: "Possibility"
        case .userInput: "You told us"
        case .unverified: "Unverified"
        }
    }

    var symbol: String {
        switch self {
        case .fact: "checkmark.seal.fill"
        case .inference: "lightbulb.fill"
        case .possibility: "questionmark.circle.fill"
        case .userInput: "person.fill"
        case .unverified: "exclamationmark.triangle.fill"
        }
    }
}

// MARK: - Opportunities

enum OpportunityType: String, Codable, CaseIterable {
    case subscriptionRenewal, priceDrop, returnDeadline, refund, warrantyExpiration, negotiation
    case duplicateCharge, feeDetection, insuranceOpportunity, purchaseProtection, cheaperAlternative
    case travelPriceChange, claimOpportunity, maintenance, unknown

    var displayName: String {
        switch self {
        case .subscriptionRenewal: "Renewal"
        case .priceDrop: "Price drop"
        case .returnDeadline: "Return window"
        case .refund: "Refund"
        case .warrantyExpiration: "Warranty"
        case .negotiation: "Negotiation"
        case .duplicateCharge: "Duplicate charge"
        case .feeDetection: "Fee"
        case .insuranceOpportunity: "Insurance"
        case .purchaseProtection: "Purchase protection"
        case .cheaperAlternative: "Cheaper alternative"
        case .travelPriceChange: "Travel price"
        case .claimOpportunity: "Claim"
        case .maintenance: "Maintenance"
        case .unknown: "Opportunity"
        }
    }

    var symbol: String {
        switch self {
        case .subscriptionRenewal: "arrow.triangle.2.circlepath"
        case .priceDrop: "arrow.down.right.circle.fill"
        case .returnDeadline: "arrow.uturn.backward.circle.fill"
        case .refund: "banknote.fill"
        case .warrantyExpiration: "shield.checkered"
        case .negotiation: "bubble.left.and.text.bubble.right.fill"
        case .duplicateCharge: "doc.on.doc.fill"
        case .feeDetection: "exclamationmark.circle.fill"
        case .insuranceOpportunity: "umbrella.fill"
        case .purchaseProtection: "creditcard.and.123"
        case .cheaperAlternative: "tag.fill"
        case .travelPriceChange: "airplane.circle.fill"
        case .claimOpportunity: "doc.badge.plus"
        case .maintenance: "wrench.and.screwdriver.fill"
        case .unknown: "sparkles"
        }
    }

    /// Whether the opportunity is about money the user could lose (urgent) or gain (opportunity) or protect.
    var lane: OpportunityLane {
        switch self {
        case .returnDeadline, .subscriptionRenewal, .duplicateCharge, .feeDetection: .urgent
        case .priceDrop, .refund, .negotiation, .cheaperAlternative, .travelPriceChange, .claimOpportunity: .opportunity
        case .warrantyExpiration, .insuranceOpportunity, .purchaseProtection, .maintenance, .unknown: .protection
        }
    }
}

extension OpportunityType {
    /// Whether an estimated amount for this type is a saving/recovery (true) or the value at stake / protected (false).
    var representsSaving: Bool {
        switch self {
        case .subscriptionRenewal, .priceDrop, .refund, .negotiation, .duplicateCharge, .feeDetection, .cheaperAlternative, .travelPriceChange, .claimOpportunity: true
        case .returnDeadline, .warrantyExpiration, .insuranceOpportunity, .purchaseProtection, .maintenance, .unknown: false
        }
    }
}

enum OpportunityLane: String, Codable {
    case urgent, opportunity, protection

    var displayName: String {
        switch self {
        case .urgent: "Urgent"
        case .opportunity: "Opportunity"
        case .protection: "Protection"
        }
    }
}

enum Urgency: String, Codable, CaseIterable, Comparable {
    case low, medium, high, critical

    private var rank: Int {
        switch self {
        case .low: 0
        case .medium: 1
        case .high: 2
        case .critical: 3
        }
    }

    static func < (lhs: Urgency, rhs: Urgency) -> Bool { lhs.rank < rhs.rank }

    var weight: Double {
        switch self {
        case .low: 0.6
        case .medium: 0.85
        case .high: 1.1
        case .critical: 1.4
        }
    }

    /// Derives urgency from how many days remain before a deadline.
    init(daysUntilDeadline days: Int?) {
        guard let days else { self = .medium; return }
        switch days {
        case ..<0: self = .low
        case 0...2: self = .critical
        case 3...7: self = .high
        case 8...30: self = .medium
        default: self = .low
        }
    }
}

enum OpportunityStatus: String, Codable, CaseIterable {
    case open, inProgress, resolved, dismissed, expired

    var displayName: String {
        switch self {
        case .open: "Open"
        case .inProgress: "In progress"
        case .resolved: "Resolved"
        case .dismissed: "Dismissed"
        case .expired: "Expired"
        }
    }
}

// MARK: - Savings

enum SavingsKind: String, Codable, CaseIterable {
    case saved, recovered, avoided, protected, negotiated

    var displayName: String { rawValue.capitalized }

    var symbol: String {
        switch self {
        case .saved: "arrow.down.circle.fill"
        case .recovered: "arrow.uturn.backward.circle.fill"
        case .avoided: "hand.raised.fill"
        case .protected: "shield.fill"
        case .negotiated: "bubble.left.and.bubble.right.fill"
        }
    }
}

enum SavingsStatus: String, Codable, CaseIterable {
    case pending, confirmed, rejected
}

// MARK: - Subscriptions & warranties

enum BillingCycle: String, Codable, CaseIterable {
    case weekly, monthly, quarterly, yearly, unknown

    var displayName: String {
        switch self {
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        case .quarterly: "Quarterly"
        case .yearly: "Yearly"
        case .unknown: "Unknown cycle"
        }
    }

    var shortSuffix: String {
        switch self {
        case .weekly: "/wk"
        case .monthly: "/mo"
        case .quarterly: "/qtr"
        case .yearly: "/yr"
        case .unknown: ""
        }
    }

    var periodsPerYear: Decimal? {
        switch self {
        case .weekly: 52
        case .monthly: 12
        case .quarterly: 4
        case .yearly: 1
        case .unknown: nil
        }
    }

    var calendarComponent: (Calendar.Component, Int)? {
        switch self {
        case .weekly: (.weekOfYear, 1)
        case .monthly: (.month, 1)
        case .quarterly: (.month, 3)
        case .yearly: (.year, 1)
        case .unknown: nil
        }
    }
}

enum SubscriptionStatus: String, Codable, CaseIterable {
    case active, markedUnused, cancelled, unknown

    var displayName: String {
        switch self {
        case .active: "Active"
        case .markedUnused: "Marked unused by you"
        case .cancelled: "Cancelled"
        case .unknown: "Unknown"
        }
    }
}

enum WarrantyType: String, Codable, CaseIterable {
    case manufacturer, extended, retailer, creditCard, insurance

    var displayName: String {
        switch self {
        case .manufacturer: "Manufacturer warranty"
        case .extended: "Extended coverage"
        case .retailer: "Retailer guarantee"
        case .creditCard: "Card purchase protection"
        case .insurance: "Insurance"
        }
    }
}

enum VaultCategory: String, CaseIterable, Identifiable {
    case all, purchases, subscriptions, bills, warranties, travel, insurance, documents

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}
