import Foundation

/// Normalised output of document understanding. Every field is optional — LEVER never invents data.
struct PurchaseDocument: Codable, Equatable, Identifiable {
    struct LineItem: Codable, Equatable, Hashable {
        var name: String
        var quantity: Int
        var unitPrice: Decimal?
    }

    struct SubscriptionInfo: Codable, Equatable {
        var billingCycle: BillingCycle
        var nextBillingDate: Date?
        var previousPrice: Decimal?
    }

    struct WarrantyInfo: Codable, Equatable {
        var provider: String
        var type: WarrantyType
        var months: Int?
        var endDate: Date?
        var source: String
        var confidence: Confidence
    }

    var id: UUID = UUID()
    var documentType: DocumentType = .unknown
    var merchant: String?
    var merchantCategory: MerchantCategory = .other
    var productTitle: String?
    var purchaseDate: Date?
    var amount: Decimal?
    var currencyCode: String
    var items: [LineItem] = []
    var renewalDate: Date?
    var returnDeadline: Date?
    var warranties: [WarrantyInfo] = []
    var subscription: SubscriptionInfo?
    var contractMonths: Int?
    var bookingDate: Date?
    var serviceDate: Date?
    var referenceNumber: String?
    var orderNumber: String?
    var invoiceNumber: String?
    var serialNumber: String?
    var policyNumber: String?
    var paymentMethod: String?
    var productURL: String?
    var rawText: String
    /// 0...1 per field name, used to highlight what needs verification.
    var fieldConfidences: [String: Double] = [:]
    var overallConfidence: Confidence = .low
    var providerName: String = "On-device"
    var processedOnDevice: Bool = true
    var createdAt: Date = .now
    var tags: [String] = []

    init(rawText: String, currencyCode: String) {
        self.rawText = rawText
        self.currencyCode = currencyCode
    }

    func confidence(for field: String) -> Confidence {
        Confidence(score: fieldConfidences[field] ?? 0)
    }

    /// Fields the review screen should flag for the user to check.
    var fieldsNeedingVerification: [String] {
        fieldConfidences.filter { $0.value < 0.8 }.map(\.key).sorted()
    }

    var hasUsableCore: Bool {
        merchant != nil || amount != nil || purchaseDate != nil
    }

    var displayTitle: String {
        productTitle ?? merchant ?? documentType.displayName
    }
}

/// An opportunity proposed by a rule before it is persisted.
struct OpportunityDraft: Equatable, Identifiable {
    struct EvidenceDraft: Equatable {
        var kind: EvidenceKind
        var statement: String
        var source: String
    }

    var id: UUID = UUID()
    var type: OpportunityType
    var title: String
    var detail: String
    var estimatedSavings: Decimal?
    var currencyCode: String
    var confidence: Confidence
    var urgency: Urgency
    var deadline: Date?
    var merchantName: String
    var recommendedAction: String
    var evidence: [EvidenceDraft]
    var dedupeKey: String

    var priorityScore: Double {
        OpportunityRanker.score(
            estimatedSavings: estimatedSavings,
            urgency: urgency,
            confidence: confidence,
            daysUntilDeadline: deadline.map { DateMath.days(from: .now, to: $0) }
        )
    }
}

struct ActionPlanDraft: Equatable {
    var summary: String
    var whyItMatters: String
    var estimatedSavings: Decimal?
    var steps: [String]
    var messageDraft: String?
    var callScript: String?
    var deadline: Date?
    var confidence: Confidence
    var generatedBy: String
}

struct ClaimDraft: Equatable {
    var subject: String
    var body: String
}

struct NegotiationInput: Equatable {
    var merchantName: String
    var currencyCode: String
    var currentPrice: Decimal
    var previousPrice: Decimal?
    var competitorPrice: Decimal?
    var tenureMonths: Int?
    var desiredOutcome: String
    var billingCycle: BillingCycle = .monthly
}

struct NegotiationDraft: Equatable {
    var bestArgument: String
    var fallbackArgument: String
    var targetPrice: Decimal?
    var walkAwayPrice: Decimal?
    var emailDraft: String
    var chatDraft: String
    var phoneScript: String
}
