import XCTest
@testable import LEVER

final class SubscriptionMathTests: XCTestCase {
    func testAnnualCost() {
        XCTAssertEqual(SubscriptionMath.annualCost(price: 1_499, cycle: .monthly), 17_988)
        XCTAssertEqual(SubscriptionMath.annualCost(price: 18_000, cycle: .yearly), 18_000)
        XCTAssertEqual(SubscriptionMath.annualCost(price: 100, cycle: .weekly), 5_200)
        XCTAssertNil(SubscriptionMath.annualCost(price: 100, cycle: .unknown))
    }

    func testAnnualIncreaseAndPercent() {
        XCTAssertEqual(SubscriptionMath.annualIncrease(current: 1_499, previous: 1_199, cycle: .monthly), 3_600)
        XCTAssertEqual(SubscriptionMath.increasePercent(current: 1_499, previous: 999), 50)
        XCTAssertNil(SubscriptionMath.annualIncrease(current: 999, previous: 1_499, cycle: .monthly), "Decreases are not increases")
    }

    func testNextBillingDateRollsForward() {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 15))!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 12))!
        let next = SubscriptionMath.nextBillingDate(after: start, cycle: .monthly, calendar: calendar, now: now)!
        XCTAssertEqual(calendar.component(.month, from: next), 9)
        XCTAssertEqual(calendar.component(.day, from: next), 15)
    }
}

final class DeadlineTests: XCTestCase {
    func testDaysBetweenIgnoresTimeOfDay() {
        let calendar = Calendar.current
        let morning = calendar.date(from: DateComponents(year: 2026, month: 9, day: 12, hour: 8))!
        let laterEvening = calendar.date(from: DateComponents(year: 2026, month: 9, day: 16, hour: 23))!
        XCTAssertEqual(DateMath.days(from: morning, to: laterEvening), 4)
        XCTAssertEqual(DateMath.days(from: laterEvening, to: morning), -4)
    }

    func testUrgencyFromDeadline() {
        XCTAssertEqual(Urgency(daysUntilDeadline: 0), .critical)
        XCTAssertEqual(Urgency(daysUntilDeadline: 5), .high)
        XCTAssertEqual(Urgency(daysUntilDeadline: 20), .medium)
        XCTAssertEqual(Urgency(daysUntilDeadline: 90), .low)
        XCTAssertEqual(Urgency(daysUntilDeadline: nil), .medium)
    }

    func testRelativePhrase() {
        let now = Date.now
        XCTAssertEqual(DateMath.relativePhrase(to: now, from: now), "today")
        XCTAssertEqual(DateMath.relativePhrase(to: DateMath.adding(days: 1, to: now)!, from: now), "tomorrow")
        XCTAssertEqual(DateMath.relativePhrase(to: DateMath.adding(days: 4, to: now)!, from: now), "in 4 days")
    }

    @MainActor
    func testReturnWindowUsesStatedDeadlineWithHighConfidence() {
        let stated = DateMath.adding(days: 10, to: .now)!
        let window = ReturnWindowCalculator.calculate(statedDeadline: stated, purchaseDate: .now, merchant: "Unknown Shop", category: .other, documentType: .receipt, policies: MerchantDirectory())
        XCTAssertEqual(window?.deadline, stated)
        XCTAssertEqual(window?.confidence, .high)
    }

    @MainActor
    func testReturnWindowFromKnownPolicyIsMediumConfidence() {
        let purchase = Date.now
        let window = ReturnWindowCalculator.calculate(statedDeadline: nil, purchaseDate: purchase, merchant: "Apple", category: .electronics, documentType: .receipt, policies: MerchantDirectory())
        XCTAssertEqual(window?.daysAllowed, 14)
        XCTAssertEqual(window?.confidence, .medium)
        XCTAssertTrue(window?.policySource.lowercased().contains("verify") ?? false)
    }

    @MainActor
    func testUnknownMerchantGetsNoInventedDeadline() {
        let window = ReturnWindowCalculator.calculate(statedDeadline: nil, purchaseDate: .now, merchant: "Corner Shop", category: .other, documentType: .receipt, policies: MerchantDirectory())
        XCTAssertNil(window)
    }

    @MainActor
    func testSubscriptionsDoNotGetReturnWindows() {
        let window = ReturnWindowCalculator.calculate(statedDeadline: nil, purchaseDate: .now, merchant: "Apple", category: .software, documentType: .subscription, policies: MerchantDirectory())
        XCTAssertNil(window)
    }
}

final class WarrantyTests: XCTestCase {
    @MainActor
    func testDaysRemainingAndActive() {
        let warranty = Warranty(provider: "Apple", type: .manufacturer, startDate: .now, endDate: DateMath.adding(days: 21, to: .now), source: "Test", confidence: .high)
        XCTAssertEqual(warranty.daysRemaining(), 21)
        XCTAssertTrue(warranty.isActive)
        let expired = Warranty(provider: "Apple", type: .manufacturer, startDate: nil, endDate: DateMath.adding(days: -1, to: .now), source: "Test", confidence: .high)
        XCTAssertFalse(expired.isActive)
    }

    func testMultipleCoveragesProduceMultipleOpportunities() {
        let end = DateMath.adding(days: 10, to: .now)
        var snapshot = TestFixtures.purchase()
        snapshot.warranties = [
            .init(provider: "Apple", type: .manufacturer, endDate: end, confidence: .high, source: "Doc"),
            .init(provider: "HDFC Card", type: .creditCard, endDate: end, confidence: .medium, source: "You"),
        ]
        let drafts = WarrantyExpirationRule().evaluate(OpportunityContext(purchase: snapshot))
        XCTAssertEqual(drafts.count, 2)
        XCTAssertEqual(Set(drafts.map(\.dedupeKey)).count, 2)
    }
}

final class ConfidenceTests: XCTestCase {
    func testScoreMapping() {
        XCTAssertEqual(Confidence(score: 0.95), .high)
        XCTAssertEqual(Confidence(score: 0.6), .medium)
        XCTAssertEqual(Confidence(score: 0.2), .low)
        XCTAssertTrue(Confidence.low < Confidence.high)
    }

    @MainActor
    func testFightForMeRequiresHighConfidenceAndValue() {
        let high = TestFixtures.opportunity(confidence: .high, savings: 1000)
        let medium = TestFixtures.opportunity(confidence: .medium, savings: 1000)
        let noValue = TestFixtures.opportunity(confidence: .high, savings: nil)
        XCTAssertTrue(high.qualifiesForFightForMe)
        XCTAssertFalse(medium.qualifiesForFightForMe)
        XCTAssertFalse(noValue.qualifiesForFightForMe)
    }
}

enum TestFixtures {
    static func purchase(amount: Decimal = 149_990, merchant: String = "Amazon") -> PurchaseSnapshot {
        PurchaseSnapshot(id: UUID(), title: "MacBook Pro", merchantName: merchant, category: .electronics, documentType: .orderConfirmation, amount: amount, currencyCode: "INR", purchaseDate: DateMath.adding(days: -6, to: .now), paymentMethod: "Visa ending 4421", orderNumber: "405-1")
    }

    @MainActor
    static func opportunity(confidence: Confidence, savings: Decimal?) -> Opportunity {
        Opportunity(type: .subscriptionRenewal, title: "Test", detail: "Detail", estimatedSavings: savings, currencyCode: "INR", confidence: confidence, urgency: .high, deadline: DateMath.adding(days: 1, to: .now), merchantName: "Netflix", recommendedAction: "Cancel", dedupeKey: "test")
    }
}
