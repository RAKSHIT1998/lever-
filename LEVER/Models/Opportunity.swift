import Foundation
import SwiftData

@Model
final class Opportunity {
    @Attribute(.unique) var id: UUID
    var typeRaw: String
    var title: String
    var detail: String
    var estimatedSavings: Decimal?
    var currencyCode: String
    var confidenceRaw: String
    var urgencyRaw: String
    var deadline: Date?
    var merchantName: String
    var recommendedAction: String
    var statusRaw: String
    /// Stable key so re-running the engine updates instead of duplicating.
    var dedupeKey: String
    var createdAt: Date
    var lastCheckedAt: Date
    var resolvedAt: Date?
    var purchase: Purchase?

    @Relationship(deleteRule: .cascade, inverse: \Evidence.opportunity)
    var evidence: [Evidence] = []

    @Relationship(deleteRule: .cascade, inverse: \ActionPlan.opportunity)
    var actionPlan: ActionPlan?

    @Relationship(deleteRule: .nullify, inverse: \SavingsEvent.opportunity)
    var savingsEvents: [SavingsEvent] = []

    @Relationship(deleteRule: .cascade, inverse: \Negotiation.opportunity)
    var negotiations: [Negotiation] = []

    init(
        id: UUID = UUID(),
        type: OpportunityType,
        title: String,
        detail: String,
        estimatedSavings: Decimal?,
        currencyCode: String,
        confidence: Confidence,
        urgency: Urgency,
        deadline: Date?,
        merchantName: String,
        recommendedAction: String,
        dedupeKey: String
    ) {
        self.id = id
        self.typeRaw = type.rawValue
        self.title = title
        self.detail = detail
        self.estimatedSavings = estimatedSavings
        self.currencyCode = currencyCode
        self.confidenceRaw = confidence.rawValue
        self.urgencyRaw = urgency.rawValue
        self.deadline = deadline
        self.merchantName = merchantName
        self.recommendedAction = recommendedAction
        self.statusRaw = OpportunityStatus.open.rawValue
        self.dedupeKey = dedupeKey
        self.createdAt = .now
        self.lastCheckedAt = .now
    }

    var type: OpportunityType {
        get { OpportunityType(rawValue: typeRaw) ?? .unknown }
        set { typeRaw = newValue.rawValue }
    }

    var confidence: Confidence {
        get { Confidence(rawValue: confidenceRaw) ?? .low }
        set { confidenceRaw = newValue.rawValue }
    }

    var urgency: Urgency {
        get { Urgency(rawValue: urgencyRaw) ?? .medium }
        set { urgencyRaw = newValue.rawValue }
    }

    var status: OpportunityStatus {
        get { OpportunityStatus(rawValue: statusRaw) ?? .open }
        set { statusRaw = newValue.rawValue }
    }

    var lane: OpportunityLane { type.lane }

    var daysUntilDeadline: Int? {
        guard let deadline else { return nil }
        return DateMath.days(from: .now, to: deadline)
    }

    var isActionable: Bool { status == .open || status == .inProgress }

    /// The "Fight for me" button is only shown when LEVER is confident and the potential value is real.
    var qualifiesForFightForMe: Bool {
        confidence == .high && (estimatedSavings ?? 0) > 0 && isActionable
    }

    var priorityScore: Double {
        OpportunityRanker.score(
            estimatedSavings: estimatedSavings,
            urgency: urgency,
            confidence: confidence,
            daysUntilDeadline: daysUntilDeadline
        )
    }
}

@Model
final class Evidence {
    var kindRaw: String
    var statement: String
    var source: String
    var checkedAt: Date
    var opportunity: Opportunity?

    init(kind: EvidenceKind, statement: String, source: String, checkedAt: Date = .now) {
        self.kindRaw = kind.rawValue
        self.statement = statement
        self.source = source
        self.checkedAt = checkedAt
    }

    var kind: EvidenceKind { EvidenceKind(rawValue: kindRaw) ?? .unverified }
}

@Model
final class ActionPlan {
    var summary: String
    var whyItMatters: String
    var estimatedSavings: Decimal?
    var steps: [String]
    var messageDraft: String?
    var callScript: String?
    var deadline: Date?
    var confidenceRaw: String
    var generatedBy: String
    var createdAt: Date
    var opportunity: Opportunity?

    init(summary: String, whyItMatters: String, estimatedSavings: Decimal?, steps: [String], messageDraft: String?, callScript: String?, deadline: Date?, confidence: Confidence, generatedBy: String) {
        self.summary = summary
        self.whyItMatters = whyItMatters
        self.estimatedSavings = estimatedSavings
        self.steps = steps
        self.messageDraft = messageDraft
        self.callScript = callScript
        self.deadline = deadline
        self.confidenceRaw = confidence.rawValue
        self.generatedBy = generatedBy
        self.createdAt = .now
    }

    var confidence: Confidence { Confidence(rawValue: confidenceRaw) ?? .low }
}

@Model
final class Negotiation {
    var merchantName: String
    var currentPrice: Decimal
    var previousPrice: Decimal?
    var competitorPrice: Decimal?
    var tenureMonths: Int?
    var desiredOutcome: String
    var targetPrice: Decimal?
    var walkAwayPrice: Decimal?
    var bestArgument: String
    var fallbackArgument: String
    var emailDraft: String
    var chatDraft: String
    var phoneScript: String
    var createdAt: Date
    var opportunity: Opportunity?

    init(merchantName: String, currentPrice: Decimal, previousPrice: Decimal?, competitorPrice: Decimal?, tenureMonths: Int?, desiredOutcome: String, targetPrice: Decimal?, walkAwayPrice: Decimal?, bestArgument: String, fallbackArgument: String, emailDraft: String, chatDraft: String, phoneScript: String) {
        self.merchantName = merchantName
        self.currentPrice = currentPrice
        self.previousPrice = previousPrice
        self.competitorPrice = competitorPrice
        self.tenureMonths = tenureMonths
        self.desiredOutcome = desiredOutcome
        self.targetPrice = targetPrice
        self.walkAwayPrice = walkAwayPrice
        self.bestArgument = bestArgument
        self.fallbackArgument = fallbackArgument
        self.emailDraft = emailDraft
        self.chatDraft = chatDraft
        self.phoneScript = phoneScript
        self.createdAt = .now
    }
}
