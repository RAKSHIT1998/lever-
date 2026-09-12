import XCTest
import SwiftData
@testable import LEVER

@MainActor
final class PersistenceTests: XCTestCase {
    private var env: AppEnvironment!

    override func setUp() async throws {
        env = AppEnvironment.preview(seeded: false)
    }

    private func doc(_ text: String) async throws -> PurchaseDocument {
        try await env.intelligence.extractDocument(from: .text(text), currencyCode: "INR")
    }

    func testSavingDocumentBuildsPurchaseGraphAndOpportunities() async throws {
        let document = try await doc("""
        Amazon.in Order Confirmation
        Order # 405-7781234-9921107
        Apple MacBook Pro 14-inch
        Order Total ₹1,49,990.00
        Order date: \(DateMath.adding(days: -2, to: .now)!.leverShort)
        Paid with Visa ending 4421
        12 months Apple Limited Warranty
        """)
        let purchase = try await env.repository.save(document: document, files: [])
        XCTAssertEqual(purchase.merchantName, "Amazon")
        XCTAssertEqual(purchase.amount, 149_990)
        XCTAssertNotNil(purchase.returnWindow?.deadline, "Known merchant + purchase date → policy-based window")
        XCTAssertEqual(purchase.returnWindow?.confidence, .medium)
        XCTAssertEqual(purchase.warranties.count, 1)
        XCTAssertEqual(purchase.documents.count, 1)
        XCTAssertEqual(purchase.analyses.count, 1)
        XCTAssertTrue(purchase.openOpportunities.contains { $0.type == .returnDeadline })
        XCTAssertTrue(purchase.openOpportunities.contains { $0.type == .purchaseProtection })

        // Re-running detection updates in place instead of duplicating.
        let before = purchase.opportunities.count
        await env.repository.refreshOpportunities(for: purchase)
        XCTAssertEqual(purchase.opportunities.count, before)
    }

    func testDataPersistsAcrossFetch() async throws {
        let document = try await doc("Netflix\nYour Premium plan renews on \(DateMath.adding(days: 3, to: .now)!.leverShort)\nNew price ₹1,499/month\nPreviously ₹1,199/month")
        let saved = try await env.repository.save(document: document, files: [])
        let fetched = env.repository.purchase(id: saved.id)
        XCTAssertNotNil(fetched?.subscription)
        XCTAssertEqual(fetched?.subscription?.previousPrice, 1_199)
        XCTAssertEqual(fetched?.subscription?.annualIncrease, 3_600)
    }

    func testSavingsOnlyCountWhenConfirmed() async throws {
        let document = try await doc("Netflix\nrenews on \(DateMath.adding(days: 1, to: .now)!.leverShort)\n₹1,499/month\nPreviously ₹1,199/month")
        let purchase = try await env.repository.save(document: document, files: [])
        let opportunity = purchase.openOpportunities.first { $0.type == .negotiation }!
        let event = env.repository.proposeSaving(for: opportunity, amount: 3_600, kind: .negotiated)
        XCTAssertEqual(env.repository.totals.lifetime, 0)
        XCTAssertEqual(env.repository.totals.pending, 3_600)
        env.repository.confirmSaving(event)
        XCTAssertEqual(env.repository.totals.lifetime, 3_600)
        XCTAssertEqual(env.repository.totals.byKind[.negotiated], 3_600)
        XCTAssertEqual(opportunity.status, .resolved)
    }

    func testRejectedSavingsNeverCount() {
        let rejected = SavingsEvent(kind: .saved, amount: 500, currencyCode: "INR", title: "x", status: .rejected)
        let confirmed = SavingsEvent(kind: .saved, amount: 200, currencyCode: "INR", title: "y", status: .confirmed)
        confirmed.confirmedAt = .now
        let totals = SavingsTotals(events: [rejected, confirmed], currencyCode: "INR")
        XCTAssertEqual(totals.lifetime, 200)
        XCTAssertEqual(totals.thisMonth, 200)
    }

    func testDeleteEverythingClearsStore() async throws {
        let document = try await doc("Apple Store\nTotal ₹89,999\nDate 1 Jan 2026")
        _ = try await env.repository.save(document: document, files: [.image(Data([0xFF, 0xD8, 0xFF]))])
        XCTAssertEqual(env.repository.allPurchases().count, 1)
        XCTAssertGreaterThan(env.files.totalBytes, 0)
        await env.repository.deleteEverything()
        XCTAssertTrue(env.repository.allPurchases().isEmpty)
        XCTAssertTrue(env.repository.savingsEvents().isEmpty)
        XCTAssertEqual(env.files.totalBytes, 0)
        XCTAssertEqual(WidgetSnapshot.load().openOpportunities, 0)
    }

    func testSnapshotPublishesAggregatesOnly() async throws {
        let document = try await doc("Netflix\nrenews on \(DateMath.adding(days: 1, to: .now)!.leverShort)\n₹1,499/month\nPreviously ₹1,199/month")
        _ = try await env.repository.save(document: document, files: [])
        let snapshot = WidgetSnapshot.load()
        XCTAssertGreaterThan(snapshot.openOpportunities, 0)
        XCTAssertGreaterThan(snapshot.potentialSavings, 0)
        XCTAssertFalse(snapshot.upcomingRenewals.isEmpty)
    }

    func testVaultSearch() async throws {
        let a = try await env.repository.save(document: doc("Amazon\nMacBook Pro\nTotal ₹1,49,990\nOrder date 1 Sep 2026"), files: [])
        let b = try await env.repository.save(document: doc("Netflix\n₹1,499/month\nrenews on \(DateMath.adding(days: 2, to: .now)!.leverShort)"), files: [])
        let all = [a, b]
        XCTAssertEqual(VaultFilter.apply(all, category: .all, query: "macbook").map(\.id), [a.id])
        XCTAssertEqual(VaultFilter.apply(all, category: .all, query: "subscriptions").map(\.id), [b.id])
        XCTAssertEqual(VaultFilter.apply(all, category: .all, query: "₹149990").map(\.id), [a.id])
        XCTAssertEqual(VaultFilter.apply(all, category: .subscriptions, query: "").map(\.id), [b.id])
        XCTAssertEqual(VaultFilter.apply(all, category: .all, query: "expires this month").map(\.id), [b.id])
    }
}

final class StoreLogicTests: XCTestCase {
    func testEntitlementResolution() {
        XCTAssertFalse(EntitlementResolver.isPro(activeProductIDs: []))
        XCTAssertFalse(EntitlementResolver.isPro(activeProductIDs: ["com.other.thing"]))
        XCTAssertTrue(EntitlementResolver.isPro(activeProductIDs: ["lever_pro_yearly"]))
        XCTAssertTrue(EntitlementResolver.isPro(activeProductIDs: ["lever_pro_lifetime", "junk"]))
    }

    func testFreeCaptureLimit() {
        XCTAssertTrue(EntitlementResolver.canCapture(isPro: false, capturesUsed: 2))
        XCTAssertFalse(EntitlementResolver.canCapture(isPro: false, capturesUsed: 3))
        XCTAssertTrue(EntitlementResolver.canCapture(isPro: true, capturesUsed: 300))
        XCTAssertEqual(EntitlementResolver.remainingFreeCaptures(capturesUsed: 5), 0)
        XCTAssertEqual(EntitlementResolver.remainingFreeCaptures(capturesUsed: 1), 2)
    }

    func testProductOrderingYearlyFirst() {
        let sorted = ProProduct.allCases.sorted { $0.displayOrder < $1.displayOrder }
        XCTAssertEqual(sorted.first, .yearly)
    }
}

final class NotificationPlannerTests: XCTestCase {
    func testPlansReturnWarrantyAndRenewalReminders() {
        var p = TestFixtures.purchase()
        p.returnWindow = .init(deadline: DateMath.adding(days: 5, to: .now), source: "Doc", confidence: .high)
        p.warranties = [.init(provider: "Apple", type: .manufacturer, endDate: DateMath.adding(days: 40, to: .now), confidence: .high, source: "Doc")]
        p.subscription = .init(price: 999, previousPrice: nil, cycle: .monthly, nextBillingDate: DateMath.adding(days: 10, to: .now), status: .active, confidence: .high)
        let planned = DeadlineNotificationPlanner.plan(for: p)
        XCTAssertEqual(planned.filter { $0.identifier.hasPrefix("return.") }.count, 2)
        XCTAssertEqual(planned.filter { $0.identifier.hasPrefix("warranty.") }.count, 2)
        XCTAssertEqual(planned.filter { $0.identifier.hasPrefix("renewal.") }.count, 2)
        XCTAssertTrue(planned.allSatisfy { $0.fireDate > .now })
        XCTAssertTrue(planned.allSatisfy { !$0.body.lowercased().contains("come back") })
    }

    func testPastDeadlinesProduceNoReminders() {
        var p = TestFixtures.purchase()
        p.returnWindow = .init(deadline: DateMath.adding(days: -3, to: .now), source: "Doc", confidence: .high)
        XCTAssertTrue(DeadlineNotificationPlanner.plan(for: p).isEmpty)
    }

    func testCancelledSubscriptionsAreNotReminded() {
        var p = TestFixtures.purchase()
        p.subscription = .init(price: 999, previousPrice: nil, cycle: .monthly, nextBillingDate: DateMath.adding(days: 10, to: .now), status: .cancelled, confidence: .high)
        XCTAssertTrue(DeadlineNotificationPlanner.plan(for: p).isEmpty)
    }

    @MainActor
    func testRepositorySchedulesThroughProtocol() async throws {
        let env = AppEnvironment.preview(seeded: false)
        env.settings.notificationsEnabled = true
        let document = try await env.intelligence.extractDocument(from: .text("Netflix\nrenews on \(DateMath.adding(days: 5, to: .now)!.leverShort)\n₹1,499/month"), currencyCode: "INR")
        _ = try await env.repository.save(document: document, files: [])
        let scheduler = env.notifications as! NoopNotifications
        XCTAssertEqual(scheduler.count, 2)
    }
}

final class InboxTests: XCTestCase {
    func testInboxRoundTrip() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("LEVERInboxTest-\(UUID().uuidString)", isDirectory: true)
        let store = InboxStore(directory: dir)
        let item = store.store(data: Data("hello".utf8), kind: .pdf, fileExtension: "pdf")
        XCTAssertNotNil(item)
        store.append(InboxItem(kind: .text, text: "Order total ₹500"))
        XCTAssertEqual(store.load().count, 2)
        store.remove(item!)
        XCTAssertEqual(store.load().count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: item!.fileURL!.path))
        store.removeAll()
        XCTAssertTrue(store.load().isEmpty)
    }

    func testAnalyticsDropsSensitiveKeys() {
        let analytics = LocalAnalyticsService()
        analytics.track(.captureCompleted, properties: ["rawText": "secret receipt", "documentType": "receipt"])
        XCTAssertEqual(analytics.recent.count, 1)
        analytics.isEnabled = false
        analytics.track(.appOpen)
        XCTAssertEqual(analytics.recent.count, 1)
    }
}
