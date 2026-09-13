import XCTest
@testable import LEVER

final class InsightEngineTests: XCTestCase {
    private func sub(_ m: String, _ price: Decimal, cycle: BillingCycle = .monthly, cat: MerchantCategory = .streaming, prev: Decimal? = nil, status: SubscriptionStatus = .active, nextInDays: Int? = 20) -> VaultSummary.Sub {
        .init(purchaseID: UUID(), merchant: m, category: cat, price: price, cycle: cycle, next: nextInDays.flatMap { DateMath.adding(days: $0, to: .now) }, previous: prev, status: status)
    }
    private func item(_ t: String, _ amt: Decimal, cat: MerchantCategory = .electronics, daysAgo: Int = 5, warranty: Bool = false, ret: Bool = false, url: Bool = false, type: DocumentType = .receipt) -> VaultSummary.Item {
        .init(id: UUID(), title: t, merchant: "Shop", category: cat, amount: amt, date: DateMath.adding(days: -daysAgo, to: .now), hasWarranty: warranty, hasReturnWindow: ret, hasProductURL: url, documentType: type)
    }

    func testStreamingOverlapCreepAndUnused() {
        let v = VaultSummary(currencyCode: "INR", subscriptions: [
            sub("Netflix", 1_499, prev: 1_199), sub("JioHotstar", 299), sub("Prime Video", 299), sub("Spotify", 119, status: .markedUnused),
        ], items: [])
        let ids = InsightEngine.generate(v).map(\.id)
        XCTAssertEqual(ids.first, "unused", "Money already being wasted ranks first")
        XCTAssertTrue(ids.contains("streaming-overlap"))
        XCTAssertTrue(ids.contains("creep"))
        XCTAssertTrue(ids.contains("recurring-total"))
        XCTAssertTrue(ids.contains("cash-30"))
    }

    func testCoverageAndTrackingHygiene() {
        let v = VaultSummary(currencyCode: "INR", subscriptions: [], items: [
            item("MacBook Pro", 149_990), item("Kettle", 1_500, cat: .home), item("Old TV", 60_000, daysAgo: 400),
        ])
        let insights = InsightEngine.generate(v)
        XCTAssertTrue(insights.contains { $0.id == "no-warranty" && $0.title.contains("2 devices") })
        XCTAssertTrue(insights.contains { $0.id == "track-price" && $0.title.contains("MacBook") }, "Only recent electronics")
        XCTAssertTrue(insights.contains { $0.id == "return-unknown" && $0.title.contains("MacBook") })
        XCTAssertTrue(insights.contains { $0.id == "no-subs" })
    }

    func testQuietVaultProducesNoNoise() {
        let v = VaultSummary(currencyCode: "INR", subscriptions: [sub("Netflix", 649)], items: [item("Phone", 30_000, warranty: true, ret: true, url: true)])
        XCTAssertTrue(InsightEngine.generate(v).isEmpty)
    }
}

final class ReturnDecisionTests: XCTestCase {
    func testFaultyAlwaysReturns() {
        XCTAssertFalse(ReturnDecision.recommend(useIt: true, faulty: true, paid: 10_000, cheaper: nil, daysLeft: 3).keep)
    }
    func testUnusedReturns() {
        XCTAssertFalse(ReturnDecision.recommend(useIt: false, faulty: false, paid: 10_000, cheaper: nil, daysLeft: 3).keep)
    }
    func testUsedAndCheaperKeepsButPriceMatches() {
        let r = ReturnDecision.recommend(useIt: true, faulty: false, paid: 10_000, cheaper: 8_500, daysLeft: 3)
        XCTAssertTrue(r.keep); XCTAssertTrue(r.title.contains("difference"))
    }
    func testTrivialPriceDifferenceIgnored() {
        XCTAssertTrue(ReturnDecision.recommend(useIt: true, faulty: false, paid: 10_000, cheaper: 9_800, daysLeft: 3).keep)
    }
}

@MainActor
final class VaultAnswererTests: XCTestCase {
    func testAnswersCommonQuestionsFromVault() async throws {
        let env = AppEnvironment.preview(seeded: false)
        let doc = try await env.intelligence.extractDocument(from: .text("Netflix\nrenews on \(DateMath.adding(days: 10, to: .now)!.leverShort)\n₹1,499/month"), currencyCode: "INR")
        _ = try await env.repository.save(document: doc, files: [])
        let totals = SavingsTotals(currencyCode: "INR")
        let purchases = env.repository.allPurchases()
        XCTAssertTrue(VaultAnswerer.answer("What renews next month?", purchases: purchases, totals: totals, currencyCode: "INR")!.contains("Netflix"))
        XCTAssertTrue(VaultAnswerer.answer("How much do I spend on subscriptions?", purchases: purchases, totals: totals, currencyCode: "INR")!.contains("a month"))
        XCTAssertTrue(VaultAnswerer.answer("Which warranties expire this year?", purchases: purchases, totals: totals, currencyCode: "INR")!.contains("No warranties"))
        XCTAssertTrue(VaultAnswerer.answer("What can I return?", purchases: purchases, totals: totals, currencyCode: "INR")!.contains("No open return"))
        XCTAssertNil(VaultAnswerer.answer("Write me a poem", purchases: purchases, totals: totals, currencyCode: "INR"), "Free-form falls through to cloud or a helpful refusal")
    }
}
