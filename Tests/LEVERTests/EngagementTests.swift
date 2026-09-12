import XCTest
@testable import LEVER

final class DigestPlannerTests: XCTestCase {
    private func lite(_ title: String, inDays: Int, amount: Decimal, saving: Bool, from now: Date) -> OpportunitySnapshotLite {
        OpportunitySnapshotLite(id: UUID(), title: title, deadline: DateMath.adding(days: inDays, to: now)!, amount: amount, countsAsSaving: saving)
    }

    func testNoDeadlinesMeansNoDigest() {
        XCTAssertNil(DigestPlanner.plan(opportunities: [], currencyCode: "INR"))
        let now = Date.now
        XCTAssertNil(DigestPlanner.plan(opportunities: [lite("Far away", inDays: 60, amount: 100, saving: true, from: now)], currencyCode: "INR", now: now))
    }

    func testDigestFiresNextMondayMorningWithSplitAmounts() {
        let now = Date.now
        let planned = DigestPlanner.plan(opportunities: [
            lite("MacBook return window closes", inDays: 9, amount: 149_990, saving: false, from: now),
            lite("Netflix renews", inDays: 10, amount: 3_600, saving: true, from: now),
        ], currencyCode: "INR", now: now)
        XCTAssertNotNil(planned)
        let fire = planned!.fireDate
        XCTAssertEqual(Calendar.current.component(.weekday, from: fire), 2, "Monday")
        XCTAssertEqual(Calendar.current.component(.hour, from: fire), 9)
        XCTAssertGreaterThan(fire, now)
        XCTAssertTrue(planned!.body.contains("at stake"))
        XCTAssertTrue(planned!.body.contains("still save"))
        XCTAssertFalse(planned!.body.lowercased().contains("come back"))
        XCTAssertNotNil(planned!.userInfo[NotificationDelegate.opportunityKey])
    }
}

@MainActor
final class LiveActivityCandidateTests: XCTestCase {
    private func opp(deadlineHours: Double?, status: OpportunityStatus = .open) -> Opportunity {
        let o = Opportunity(type: .returnDeadline, title: "t", detail: "d", estimatedSavings: 100, currencyCode: "INR", confidence: .high, urgency: .high, deadline: deadlineHours.map { Date.now.addingTimeInterval($0 * 3600) }, merchantName: "Amazon", recommendedAction: "a", dedupeKey: UUID().uuidString)
        o.status = status
        return o
    }

    func testPicksSoonestWithin48Hours() {
        let soon = opp(deadlineHours: 5)
        let later = opp(deadlineHours: 30)
        let tooFar = opp(deadlineHours: 80)
        let resolved = opp(deadlineHours: 2, status: .resolved)
        let none = opp(deadlineHours: nil)
        XCTAssertEqual(LiveActivityManager.candidate(from: [later, tooFar, resolved, none, soon])?.id, soon.id)
        XCTAssertNil(LiveActivityManager.candidate(from: [tooFar, resolved, none]))
    }
}

final class InsuranceAndHTMLTests: XCTestCase {
    func testInsuranceRenewalIsAPossibilityWithoutInventedSavings() {
        var p = TestFixtures.purchase(amount: 18_000, merchant: "HDFC ERGO")
        p.documentType = .insurance
        p.category = .insurance
        p.subscription = .init(price: 18_000, previousPrice: nil, cycle: .yearly, nextBillingDate: DateMath.adding(days: 20, to: .now), status: .active, confidence: .high)
        let drafts = OpportunityEngine.standard.detect(OpportunityContext(purchase: p))
        XCTAssertEqual(drafts.filter { $0.type == .insuranceOpportunity }.count, 1)
        XCTAssertNil(drafts.first { $0.type == .insuranceOpportunity }?.estimatedSavings)
        XCTAssertTrue(drafts.filter { $0.type == .subscriptionRenewal }.isEmpty, "Insurance is not treated as a streaming-style renewal")
    }

    func testHTMLStripping() {
        let html = """
        <html><head><style>.x{color:red}</style></head><body>
        <div>Order Confirmation</div><table><tr><td>Order #</td><td>405-11</td></tr>
        <tr><td>Total</td><td>&#8377;1,499.00</td></tr></table><p>Thanks &amp; regards</p>
        <script>track()</script></body></html>
        """
        let text = HTMLText.strip(html)
        XCTAssertFalse(text.contains("<"))
        XCTAssertFalse(text.contains("track()"))
        XCTAssertTrue(text.contains("Order Confirmation"))
        XCTAssertTrue(text.contains("₹1,499.00"))
        XCTAssertTrue(text.contains("Thanks & regards"))
        XCTAssertEqual(HTMLText.strip("plain 5 < 6 text"), "plain 5 < 6 text", "Plain text with a stray < is left alone")
    }

    func testManageURLsResolveForAliases() {
        XCTAssertEqual(MerchantDirectory.manageURL(for: "netflix")?.host, "www.netflix.com")
        XCTAssertNotNil(MerchantDirectory.manageURL(for: "Bharti Airtel"))
        XCTAssertNil(MerchantDirectory.manageURL(for: "Corner Shop"))
    }
}
