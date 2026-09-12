import Foundation

/// Immutable view of a purchase for the rule engine. Rules never touch SwiftData directly — keeps them pure and testable.
struct PurchaseSnapshot: Equatable, Sendable, Identifiable {
    struct WarrantySnapshot: Equatable, Sendable {
        var provider: String
        var type: WarrantyType
        var endDate: Date?
        var confidence: Confidence
        var source: String
    }

    struct SubscriptionSnapshot: Equatable, Sendable {
        var price: Decimal
        var previousPrice: Decimal?
        var cycle: BillingCycle
        var nextBillingDate: Date?
        var status: SubscriptionStatus
        var confidence: Confidence
    }

    struct ReturnSnapshot: Equatable, Sendable {
        var deadline: Date?
        var source: String
        var confidence: Confidence
    }

    struct PriceSnapshot: Equatable, Sendable {
        var price: Decimal
        var observedAt: Date
        var source: String
    }

    struct ItemSnapshot: Equatable, Sendable {
        var name: String
        var total: Decimal?
    }

    var id: UUID
    var title: String
    var merchantName: String
    var category: MerchantCategory
    var documentType: DocumentType
    var amount: Decimal
    var currencyCode: String
    var purchaseDate: Date?
    var paymentMethod: String?
    var orderNumber: String?
    var serialNumber: String?
    var items: [ItemSnapshot] = []
    var returnWindow: ReturnSnapshot?
    var warranties: [WarrantySnapshot] = []
    var subscription: SubscriptionSnapshot?
    var latestPrice: PriceSnapshot?
    var productURL: String?
}

struct OpportunityContext: Sendable {
    var purchase: PurchaseSnapshot
    var otherPurchases: [PurchaseSnapshot] = []
    var now: Date = .now
}

/// What the action-plan generator needs — again a plain value, so it works for previews, tests and remote providers alike.
struct OpportunitySnapshot: Sendable {
    var type: OpportunityType
    var title: String
    var detail: String
    var estimatedSavings: Decimal?
    var currencyCode: String
    var merchantName: String
    var deadline: Date?
    var confidence: Confidence
    var evidence: [String]
    var purchase: PurchaseSnapshot?
}

extension PurchaseSnapshot {
    @MainActor
    init(_ purchase: Purchase) {
        id = purchase.id
        title = purchase.title
        merchantName = purchase.merchantName
        category = purchase.merchantCategory
        documentType = purchase.documentType
        amount = purchase.amount
        currencyCode = purchase.currencyCode
        purchaseDate = purchase.purchaseDate
        paymentMethod = purchase.paymentMethod
        orderNumber = purchase.orderNumber
        serialNumber = purchase.serialNumber
        items = purchase.items.map { ItemSnapshot(name: $0.name, total: $0.lineTotal) }
        if let rw = purchase.returnWindow {
            returnWindow = ReturnSnapshot(deadline: rw.deadline, source: rw.policySource, confidence: rw.confidence)
        }
        warranties = purchase.warranties.map {
            WarrantySnapshot(provider: $0.provider, type: $0.type, endDate: $0.endDate, confidence: $0.confidence, source: $0.source)
        }
        if let sub = purchase.subscription {
            subscription = SubscriptionSnapshot(price: sub.price, previousPrice: sub.previousPrice, cycle: sub.billingCycle, nextBillingDate: sub.nextBillingDate, status: sub.status, confidence: sub.confidence)
        }
        if let obs = purchase.latestPriceObservation {
            latestPrice = PriceSnapshot(price: obs.observedPrice, observedAt: obs.observedAt, source: obs.source)
        }
        productURL = purchase.productURL
    }
}

extension OpportunitySnapshot {
    @MainActor
    init(_ opportunity: Opportunity) {
        type = opportunity.type
        title = opportunity.title
        detail = opportunity.detail
        estimatedSavings = opportunity.estimatedSavings
        currencyCode = opportunity.currencyCode
        merchantName = opportunity.merchantName
        deadline = opportunity.deadline
        confidence = opportunity.confidence
        evidence = opportunity.evidence.map(\.statement)
        purchase = opportunity.purchase.map(PurchaseSnapshot.init)
    }
}
