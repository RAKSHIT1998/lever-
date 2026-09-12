import XCTest
@testable import LEVER

final class OpportunityEngineTests: XCTestCase {
    func testReturnDeadlineRuleFiresOnlyWithinWindow() {
        var p = TestFixtures.purchase()
        p.returnWindow = .init(deadline: DateMath.adding(days: 4, to: .now), source: "Typical Amazon policy — verify", confidence: .medium)
        let drafts = ReturnDeadlineRule().evaluate(OpportunityContext(purchase: p))
        XCTAssertEqual(drafts.count, 1)
        XCTAssertEqual(drafts.first?.type, .returnDeadline)
        XCTAssertEqual(drafts.first?.estimatedSavings, p.amount)
        XCTAssertEqual(drafts.first?.urgency, .high)
        XCTAssertTrue(drafts.first?.evidence.contains { $0.kind == .unverified } ?? false, "Policy-derived deadlines must carry an unverified note")

        p.returnWindow = .init(deadline: DateMath.adding(days: -1, to: .now), source: "Doc", confidence: .high)
        XCTAssertTrue(ReturnDeadlineRule().evaluate(OpportunityContext(purchase: p)).isEmpty)
    }

    func testSubscriptionIncreaseCreatesNegotiationWithCorrectAnnualSavings() {
        var p = TestFixtures.purchase(amount: 1_499, merchant: "Netflix")
        p.subscription = .init(price: 1_499, previousPrice: 1_199, cycle: .monthly, nextBillingDate: DateMath.adding(days: 1, to: .now), status: .active, confidence: .high)
        let drafts = SubscriptionRenewalRule().evaluate(OpportunityContext(purchase: p))
        let negotiation = drafts.first { $0.type == .negotiation }
        XCTAssertEqual(negotiation?.estimatedSavings, 3_600)
        XCTAssertTrue(negotiation?.title.contains("25%") ?? false)
        let renewal = drafts.first { $0.type == .subscriptionRenewal }
        XCTAssertEqual(renewal?.urgency, .critical)
    }

    func testMarkedUnusedSubscriptionIsHighConfidenceAvoidance() {
        var p = TestFixtures.purchase(amount: 119, merchant: "Spotify")
        p.subscription = .init(price: 119, previousPrice: nil, cycle: .monthly, nextBillingDate: DateMath.adding(days: 5, to: .now), status: .markedUnused, confidence: .medium)
        let renewal = SubscriptionRenewalRule().evaluate(OpportunityContext(purchase: p)).first { $0.type == .subscriptionRenewal }
        XCTAssertEqual(renewal?.confidence, .high)
        XCTAssertEqual(renewal?.estimatedSavings, 1_428)
        XCTAssertTrue(renewal?.evidence.contains { $0.kind == .userInput } ?? false)
    }

    func testCancelledSubscriptionProducesNothing() {
        var p = TestFixtures.purchase(amount: 119, merchant: "Spotify")
        p.subscription = .init(price: 119, previousPrice: 99, cycle: .monthly, nextBillingDate: DateMath.adding(days: 2, to: .now), status: .cancelled, confidence: .high)
        XCTAssertTrue(SubscriptionRenewalRule().evaluate(OpportunityContext(purchase: p)).isEmpty)
    }

    func testPriceDropRequiresRecordedObservation() {
        var p = TestFixtures.purchase(amount: 48_000, merchant: "Booking.com")
        p.documentType = .booking
        XCTAssertTrue(PriceDropRule().evaluate(OpportunityContext(purchase: p)).isEmpty)
        p.latestPrice = .init(price: 40_600, observedAt: .now, source: "Entered by you")
        let drafts = PriceDropRule().evaluate(OpportunityContext(purchase: p))
        XCTAssertEqual(drafts.first?.type, .travelPriceChange)
        XCTAssertEqual(drafts.first?.estimatedSavings, 7_400)
        XCTAssertEqual(drafts.first?.confidence, .high)
    }

    func testTinyPriceDropIsIgnored() {
        var p = TestFixtures.purchase(amount: 10_000)
        p.latestPrice = .init(price: 9_900, observedAt: .now, source: "Entered by you")
        XCTAssertTrue(PriceDropRule().evaluate(OpportunityContext(purchase: p)).isEmpty)
    }

    func testDuplicateChargeDetection() {
        let a = TestFixtures.purchase(amount: 2_499)
        var b = TestFixtures.purchase(amount: 2_499)
        b.purchaseDate = DateMath.adding(days: -5, to: .now)
        let drafts = DuplicateChargeRule().evaluate(OpportunityContext(purchase: a, otherPurchases: [b]))
        XCTAssertEqual(drafts.count, 1)
        XCTAssertEqual(drafts.first?.confidence, .medium, "Same order number → medium; never high")
        var c = b
        c.merchantName = "Flipkart"
        XCTAssertTrue(DuplicateChargeRule().evaluate(OpportunityContext(purchase: a, otherPurchases: [c])).isEmpty)
    }

    func testFeeDetection() {
        var p = TestFixtures.purchase(amount: 4_849, merchant: "MakeMyTrip")
        p.items = [.init(name: "Base fare", total: 4_500), .init(name: "Convenience fee", total: 349)]
        let drafts = FeeDetectionRule().evaluate(OpportunityContext(purchase: p))
        XCTAssertEqual(drafts.first?.estimatedSavings, 349)
        XCTAssertEqual(drafts.first?.confidence, .medium)
    }

    func testPurchaseProtectionIsLowConfidencePossibility() {
        let drafts = PurchaseProtectionRule().evaluate(OpportunityContext(purchase: TestFixtures.purchase()))
        XCTAssertEqual(drafts.count, 1)
        XCTAssertEqual(drafts.first?.confidence, .low)
        XCTAssertNil(drafts.first?.estimatedSavings, "Never claim a saving we can't support")
        var upi = TestFixtures.purchase()
        upi.paymentMethod = "UPI"
        XCTAssertTrue(PurchaseProtectionRule().evaluate(OpportunityContext(purchase: upi)).isEmpty)
    }

    func testEngineDedupesAndRanks() {
        var p = TestFixtures.purchase()
        p.returnWindow = .init(deadline: DateMath.adding(days: 1, to: .now), source: "Doc", confidence: .high)
        p.warranties = [.init(provider: "Apple", type: .manufacturer, endDate: DateMath.adding(days: 40, to: .now), confidence: .medium, source: "Doc")]
        let drafts = OpportunityEngine.standard.detect(OpportunityContext(purchase: p))
        XCTAssertEqual(drafts.first?.type, .returnDeadline, "Imminent high-value deadline must rank first")
        XCTAssertEqual(Set(drafts.map(\.dedupeKey)).count, drafts.count)
    }
}

final class RankingTests: XCTestCase {
    func testUrgentBeatsDistant() {
        let urgent = OpportunityRanker.score(estimatedSavings: 5_000, urgency: .critical, confidence: .high, daysUntilDeadline: 1)
        let distant = OpportunityRanker.score(estimatedSavings: 5_000, urgency: .low, confidence: .high, daysUntilDeadline: 60)
        XCTAssertGreaterThan(urgent, distant)
    }

    func testConfidenceMatters() {
        let high = OpportunityRanker.score(estimatedSavings: 5_000, urgency: .medium, confidence: .high, daysUntilDeadline: nil)
        let low = OpportunityRanker.score(estimatedSavings: 5_000, urgency: .medium, confidence: .low, daysUntilDeadline: nil)
        XCTAssertGreaterThan(high, low)
    }

    func testSavingsAreLogarithmicSoDeadlinesStillMatter() {
        let huge = OpportunityRanker.score(estimatedSavings: 1_000_000, urgency: .low, confidence: .medium, daysUntilDeadline: 90)
        let smallUrgent = OpportunityRanker.score(estimatedSavings: 2_000, urgency: .critical, confidence: .high, daysUntilDeadline: 0)
        XCTAssertGreaterThan(smallUrgent, huge)
    }

    func testExpiredDeadlinesSinkToBottom() {
        let expired = OpportunityRanker.score(estimatedSavings: 5_000, urgency: .low, confidence: .high, daysUntilDeadline: -2)
        let none = OpportunityRanker.score(estimatedSavings: 5_000, urgency: .low, confidence: .high, daysUntilDeadline: nil)
        XCTAssertLessThan(expired, none)
    }
}

final class GeneratorTests: XCTestCase {
    func testNegotiationUsesOnlyProvidedFacts() {
        let draft = NegotiationAssistant().prepare(NegotiationInput(merchantName: "Airtel", currencyCode: "INR", currentPrice: 1_499, previousPrice: 999, competitorPrice: nil, tenureMonths: nil, desiredOutcome: "Keep the plan."))
        XCTAssertTrue(draft.bestArgument.contains("50%"))
        XCTAssertFalse(draft.emailDraft.lowercased().contains("customer for"), "No tenure given → no tenure claim")
        XCTAssertFalse(draft.emailDraft.lowercased().contains("comparable plan"), "No competitor given → no competitor claim")
        XCTAssertEqual(draft.targetPrice, 999)
    }

    func testNegotiationWithoutHistoryFallsBackHonestly() {
        let draft = NegotiationAssistant().prepare(NegotiationInput(merchantName: "Jio", currencyCode: "INR", currentPrice: 1_000, previousPrice: nil, competitorPrice: nil, tenureMonths: nil, desiredOutcome: ""))
        XCTAssertEqual(draft.targetPrice, 800)
        XCTAssertEqual(draft.walkAwayPrice, 900)
        XCTAssertTrue(draft.bestArgument.contains("reviewing my spending"))
    }

    func testClaimGeneratorLeavesPlaceholdersForUnknowns() {
        let snapshot = OpportunitySnapshot(type: .warrantyExpiration, title: "t", detail: "d", estimatedSavings: nil, currencyCode: "INR", merchantName: "Apple", deadline: nil, confidence: .high, evidence: [], purchase: TestFixtures.purchase())
        let claim = ClaimGenerator().warrantyClaim(for: snapshot)
        XCTAssertTrue(claim.subject.contains("MacBook Pro"))
        XCTAssertTrue(claim.body.contains("[serial number]"))
        XCTAssertTrue(claim.body.contains("[describe the fault"))
    }

    func testActionPlanForEveryType() {
        for type in OpportunityType.allCases {
            let snapshot = OpportunitySnapshot(type: type, title: "t", detail: "d", estimatedSavings: 100, currencyCode: "INR", merchantName: "Shop", deadline: .now, confidence: .medium, evidence: ["e"], purchase: TestFixtures.purchase())
            let plan = ActionPlanGenerator().plan(for: snapshot)
            XCTAssertFalse(plan.summary.isEmpty, "\(type)")
            XCTAssertFalse(plan.steps.isEmpty, "\(type)")
        }
    }
}
