import XCTest
@testable import LEVER

@MainActor
final class DailyUseTests: XCTestCase {
    private func env(withNetflix: Bool = true) async throws -> (AppEnvironment, Purchase) {
        let env = AppEnvironment.preview(seeded: false)
        let doc = try await env.intelligence.extractDocument(from: .text("Netflix\nrenews on \(DateMath.adding(days: 6, to: .now)!.leverShort)\n₹1,499/month\nPreviously ₹1,199/month"), currencyCode: "INR")
        let p = try await env.repository.save(document: doc, files: [])
        return (env, p)
    }

    func testSnoozeHidesFromFeedAndClampsToDeadline() async throws {
        let (env, p) = try await env()
        let renewal = p.openOpportunities.first { $0.type == .subscriptionRenewal }!
        XCTAssertTrue(env.repository.openOpportunities().contains { $0.id == renewal.id })
        env.repository.snooze(renewal, days: 30)
        XCTAssertTrue(renewal.isSnoozed)
        XCTAssertTrue(renewal.isActionable, "Snoozed is not dismissed")
        XCTAssertFalse(env.repository.openOpportunities().contains { $0.id == renewal.id })
        // Deadline in 6 days → snooze wakes no later than the day before (5 days), not 30.
        XCTAssertLessThanOrEqual(DateMath.days(from: .now, to: renewal.snoozedUntil!), 5)
        XCTAssertEqual(WidgetSnapshot.load().openOpportunities, env.repository.openOpportunities().count)
    }

    func testEditsRerunRulesAndTrustUserInput() async throws {
        let env = AppEnvironment.preview(seeded: false)
        let doc = try await env.intelligence.extractDocument(from: .text("Corner Shop\nTotal ₹40,000\nDate \(DateMath.adding(days: -2, to: .now)!.leverShort)"), currencyCode: "INR")
        let p = try await env.repository.save(document: doc, files: [])
        XCTAssertNil(p.returnWindow, "Unknown merchant → no invented deadline")
        let deadline = DateMath.adding(days: 5, to: .now)!
        await env.repository.apply(.init(title: "Sony TV", merchantName: "Corner Shop", amount: 42_000, purchaseDate: p.purchaseDate, returnDeadline: deadline, orderNumber: "CS-1", serialNumber: nil, notes: "Gift"), to: p)
        XCTAssertEqual(p.title, "Sony TV")
        XCTAssertEqual(p.amount, 42_000)
        XCTAssertEqual(p.returnWindow?.confidence, .high)
        XCTAssertEqual(p.returnWindow?.policySource, "Entered by you")
        XCTAssertTrue(p.openOpportunities.contains { $0.type == .returnDeadline && $0.estimatedSavings == 42_000 })
        await env.repository.apply(.init(title: "Sony TV", merchantName: "Corner Shop", amount: 42_000, purchaseDate: p.purchaseDate, returnDeadline: nil, orderNumber: "CS-1", serialNumber: nil, notes: nil), to: p)
        XCTAssertNil(p.returnWindow)
        XCTAssertFalse(p.openOpportunities.contains { $0.type == .returnDeadline })
    }

    func testSnapshotIgnoresOtherCurrencies() async throws {
        let (env, _) = try await env()
        let usd = try await env.intelligence.extractDocument(from: .text("Spotify\nrenews on \(DateMath.adding(days: 3, to: .now)!.leverShort)\n$9.99/month\nPreviously $7.99/month"), currencyCode: "INR")
        XCTAssertEqual(usd.currencyCode, "USD")
        _ = try await env.repository.save(document: usd, files: [])
        let snapshot = WidgetSnapshot.load()
        XCTAssertEqual(snapshot.currencyCode, "INR")
        XCTAssertEqual(snapshot.potentialSavings, 3_600, "Only INR opportunities are summed")
    }

    func testSpotlightIdentifiersRoundTrip() {
        let id = UUID()
        XCTAssertEqual(SpotlightIndexer.purchaseID(from: SpotlightIndexer.identifier(for: id)), id)
        XCTAssertNil(SpotlightIndexer.purchaseID(from: "opportunity:\(id)"))
    }

    func testOCRCustomWordsIncludeMerchants() {
        XCTAssertTrue(OCRService.customWords.contains("Netflix"))
        XCTAssertTrue(OCRService.customWords.contains("MacBook"))
    }
}
