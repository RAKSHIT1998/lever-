import Foundation
import SwiftData

/// The long-lived centre of the purchase graph. Everything LEVER learns about a purchase hangs off this object.
@Model
final class Purchase {
    @Attribute(.unique) var id: UUID
    var title: String
    var merchantName: String
    var merchantCategoryRaw: String
    var documentTypeRaw: String
    var amount: Decimal
    var currencyCode: String
    var purchaseDate: Date?
    var serviceDate: Date?
    var bookingDate: Date?
    var orderNumber: String?
    var referenceNumber: String?
    var invoiceNumber: String?
    var serialNumber: String?
    var policyNumber: String?
    var paymentMethod: String?
    var productURL: String?
    var notes: String?
    var tags: [String]
    var householdID: UUID?
    /// Display name of the household member who shared this purchase (nil when it's your own).
    var sharedBy: String? = nil
    var createdAt: Date
    var updatedAt: Date

    var merchant: Merchant?

    @Relationship(deleteRule: .cascade, inverse: \PurchaseItem.purchase)
    var items: [PurchaseItem] = []

    @Relationship(deleteRule: .cascade, inverse: \StoredDocument.purchase)
    var documents: [StoredDocument] = []

    @Relationship(deleteRule: .cascade, inverse: \Warranty.purchase)
    var warranties: [Warranty] = []

    @Relationship(deleteRule: .cascade, inverse: \ReturnWindow.purchase)
    var returnWindow: ReturnWindow?

    @Relationship(deleteRule: .cascade, inverse: \Subscription.purchase)
    var subscription: Subscription?

    @Relationship(deleteRule: .cascade, inverse: \Opportunity.purchase)
    var opportunities: [Opportunity] = []

    @Relationship(deleteRule: .cascade, inverse: \PriceObservation.purchase)
    var priceObservations: [PriceObservation] = []

    @Relationship(deleteRule: .cascade, inverse: \AIAnalysis.purchase)
    var analyses: [AIAnalysis] = []

    @Relationship(deleteRule: .nullify, inverse: \SavingsEvent.purchase)
    var savingsEvents: [SavingsEvent] = []

    init(
        id: UUID = UUID(),
        title: String,
        merchantName: String,
        merchantCategory: MerchantCategory = .other,
        documentType: DocumentType = .receipt,
        amount: Decimal,
        currencyCode: String,
        purchaseDate: Date? = nil,
        tags: [String] = []
    ) {
        self.id = id
        self.title = title
        self.merchantName = merchantName
        self.merchantCategoryRaw = merchantCategory.rawValue
        self.documentTypeRaw = documentType.rawValue
        self.amount = amount
        self.currencyCode = currencyCode
        self.purchaseDate = purchaseDate
        self.tags = tags
        self.createdAt = .now
        self.updatedAt = .now
    }

    var merchantCategory: MerchantCategory {
        get { MerchantCategory(rawValue: merchantCategoryRaw) ?? .other }
        set { merchantCategoryRaw = newValue.rawValue }
    }

    var documentType: DocumentType {
        get { DocumentType(rawValue: documentTypeRaw) ?? .unknown }
        set { documentTypeRaw = newValue.rawValue }
    }

    var openOpportunities: [Opportunity] {
        opportunities.filter { $0.status == .open || $0.status == .inProgress }
    }

    /// Only genuine savings/recoveries — never the value of an item merely at stake.
    var potentialSavings: Decimal {
        openOpportunities.filter { $0.countsAsPotentialSaving && $0.confidence != .low }.compactMap(\.estimatedSavings).reduce(0, +)
    }

    var hasActiveProtection: Bool {
        warranties.contains(where: \.isActive) || (returnWindow?.isOpen ?? false)
    }

    var latestPriceObservation: PriceObservation? {
        priceObservations.max(by: { $0.observedAt < $1.observedAt })
    }

    var isTravel: Bool { documentType == .booking || merchantCategory == .travel }
    var isBill: Bool { documentType == .bill || merchantCategory == .utilities || merchantCategory == .telecom }
}

@Model
final class PurchaseItem {
    var name: String
    var quantity: Int
    var unitPrice: Decimal?
    var purchase: Purchase?

    init(name: String, quantity: Int = 1, unitPrice: Decimal? = nil) {
        self.name = name
        self.quantity = quantity
        self.unitPrice = unitPrice
    }

    var lineTotal: Decimal? {
        guard let unitPrice else { return nil }
        return unitPrice * Decimal(quantity)
    }
}

@Model
final class Merchant {
    @Attribute(.unique) var name: String
    var categoryRaw: String
    var domain: String?
    var supportURL: String?
    var typicalReturnDays: Int?
    var policySource: String?

    @Relationship(deleteRule: .nullify, inverse: \Purchase.merchant)
    var purchases: [Purchase] = []

    init(name: String, category: MerchantCategory = .other, domain: String? = nil, supportURL: String? = nil, typicalReturnDays: Int? = nil, policySource: String? = nil) {
        self.name = name
        self.categoryRaw = category.rawValue
        self.domain = domain
        self.supportURL = supportURL
        self.typicalReturnDays = typicalReturnDays
        self.policySource = policySource
    }

    var category: MerchantCategory {
        get { MerchantCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }
}
