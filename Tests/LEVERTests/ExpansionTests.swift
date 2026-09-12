import XCTest
@testable import LEVER

final class ResaleTests: XCTestCase {
    func testRetentionCurveIsMonotonic() {
        let curve = ResaleEstimator.DeviceClass.phone.curve
        let values = [0, 6, 12, 18, 24, 36].map { ResaleEstimator.retained(months: $0, curve: curve) }
        XCTAssertEqual(values[0], 1.0)
        XCTAssertEqual(values[2], curve.firstYear, accuracy: 0.0001)
        for (a, b) in zip(values, values.dropFirst()) { XCTAssertGreaterThan(a, b) }
    }

    func testEstimateClassifiesAndRounds() {
        let bought = DateMath.adding(months: -14, to: .now)!
        let e = ResaleEstimator.estimate(price: 89_999, purchaseDate: bought, title: "iPhone 15 Pro", category: .electronics)!
        XCTAssertEqual(e.deviceClass, .phone)
        XCTAssertEqual(e.ageMonths, 14)
        XCTAssertLessThan(e.valueNow, 89_999)
        XCTAssertLessThan(e.valueInSixMonths, e.valueNow)
        XCTAssertEqual(e.valueNow.rounded(scale: -2), e.valueNow, "Rounded to hundreds")
        XCTAssertEqual(e.confidence, .medium)
        XCTAssertTrue(e.method.contains("estimate"))
    }

    func testNonElectronicsGetNoEstimate() {
        XCTAssertNil(ResaleEstimator.estimate(price: 5_000, purchaseDate: .now, title: "Running shoes", category: .fashion))
        XCTAssertNil(ResaleEstimator.estimate(price: 48_000, purchaseDate: .now, title: "Hotel booking", category: .travel))
    }

    func testResaleRuleNeedsAgeValueAndMeaningfulDrop() {
        var p = TestFixtures.purchase(amount: 149_990, merchant: "Amazon")
        p.title = "MacBook Pro 14\""
        p.purchaseDate = DateMath.adding(months: -18, to: .now)
        let drafts = ResaleValueRule().evaluate(OpportunityContext(purchase: p))
        XCTAssertEqual(drafts.count, 1)
        XCTAssertEqual(drafts[0].type, .resale)
        XCTAssertEqual(drafts[0].confidence, .low, "A model, never a quote")
        XCTAssertTrue(drafts[0].evidence.contains { $0.kind == .possibility })

        var young = p; young.purchaseDate = DateMath.adding(months: -3, to: .now)
        XCTAssertTrue(ResaleValueRule().evaluate(OpportunityContext(purchase: young)).isEmpty, "Too new")
        var cheap = p; cheap.amount = 8_000
        XCTAssertTrue(ResaleValueRule().evaluate(OpportunityContext(purchase: cheap)).isEmpty, "Below threshold")
    }
}

@MainActor
final class FamilyTransferTests: XCTestCase {
    func testExportImportRoundTripIntoAnotherVault() async throws {
        let sender = AppEnvironment.preview(seeded: false)
        sender.repository.profile().displayName = "Rakshit"
        let doc = try await sender.intelligence.extractDocument(from: .text("Amazon.in Order Confirmation\nOrder # 405-1\nApple MacBook Pro 14-inch\nOrder Total ₹1,49,990\nOrder date \(DateMath.adding(days: -3, to: .now)!.leverShort)\n12 months Apple Limited Warranty"), currencyCode: "INR")
        let purchase = try await sender.repository.save(document: doc, files: [.image(Data([0xFF, 0xD8, 0xFF, 0xE0]))])
        let bundle = sender.repository.shareBundle(for: purchase)
        XCTAssertNotNil(purchase.householdID)
        XCTAssertEqual(bundle.sharedBy, "Rakshit")
        XCTAssertEqual(bundle.documents.count, 1)
        XCTAssertNotNil(bundle.documents[0].payload)

        let data = try PurchaseTransferCodec.encode(bundle)
        let receiver = AppEnvironment.preview(seeded: false)
        let imported = try await receiver.repository.importTransfer(PurchaseTransferCodec.decode(data))
        XCTAssertEqual(imported.id, purchase.id)
        XCTAssertEqual(imported.amount, 149_990)
        XCTAssertEqual(imported.sharedBy, "Rakshit")
        XCTAssertEqual(imported.warranties.count, 1)
        XCTAssertEqual(imported.documents.count, 1)
        XCTAssertTrue(imported.tags.contains("family"))
        XCTAssertTrue(VaultFilter.matches(imported, category: .family))
        XCTAssertFalse(imported.openOpportunities.isEmpty, "Rules run on shared purchases too")

        // Second import of the same id updates rather than duplicates.
        _ = try await receiver.repository.importTransfer(PurchaseTransferCodec.decode(data))
        XCTAssertEqual(receiver.repository.allPurchases().count, 1)
    }

    func testNewerVersionIsRejectedHonestly() throws {
        var bundle = PurchaseTransfer(id: UUID(), title: "x", merchantName: "m", merchantCategory: "other", documentType: "receipt", amount: 1, currencyCode: "INR", tags: [], items: [], documents: [], warranties: [], exportedAt: .now)
        bundle.version = 99
        let data = try PurchaseTransferCodec.encode(bundle)
        XCTAssertThrowsError(try PurchaseTransferCodec.decode(data))
    }
}

final class GmailDecodingTests: XCTestCase {
    func testMultipartMessagePrefersPlainTextAndKeepsHeaders() throws {
        let plain = GmailMessage.decodeTestHelper("Order Total ₹1,499\nRenews on 1 Oct 2026")
        let html = GmailMessage.decodeTestHelper("<p>Order Total ₹1,499</p>")
        let json = """
        {"id":"abc","internalDate":"1757600000000","payload":{"mimeType":"multipart/alternative","headers":[{"name":"Subject","value":"Your Netflix receipt"},{"name":"From","value":"Netflix <info@netflix.com>"}],"parts":[{"mimeType":"text/plain","body":{"data":"\(plain)"}},{"mimeType":"text/html","body":{"data":"\(html)"}}]}}
        """
        let message = try JSONDecoder().decode(GmailMessage.self, from: Data(json.utf8))
        let email = message.asEmailMessage()!
        XCTAssertEqual(email.subject, "Your Netflix receipt")
        XCTAssertTrue(email.bodyText.contains("Order Total ₹1,499"))
        XCTAssertTrue(email.bodyText.contains("From: Netflix"))
        XCTAssertFalse(email.bodyText.contains("<p>"))
    }

    func testHTMLOnlyMessageIsStripped() throws {
        let html = GmailMessage.decodeTestHelper("<html><body><div>Total <b>$5.99</b></div></body></html>")
        let json = """
        {"id":"h","payload":{"mimeType":"text/html","headers":[{"name":"Subject","value":"Spotify"}],"body":{"data":"\(html)"}}}
        """
        let email = try JSONDecoder().decode(GmailMessage.self, from: Data(json.utf8)).asEmailMessage()!
        XCTAssertTrue(email.bodyText.contains("Total $5.99"))
        XCTAssertFalse(email.bodyText.contains("<"))
    }

    func testEmailClaimFromIDToken() {
        let payload = GmailImportSource.base64URL(Data(#"{"email":"me@example.com","sub":"1"}"#.utf8))
        XCTAssertEqual(GmailImportSource.emailClaim(fromIDToken: "hdr.\(payload).sig"), "me@example.com")
        XCTAssertNil(GmailImportSource.emailClaim(fromIDToken: "garbage"))
    }

    func testQueryIsScopedToPurchasesAndExcludesPromotions() {
        let q = EmailQuery.gmail(days: 90)
        XCTAssertTrue(q.contains("newer_than:90d"))
        XCTAssertTrue(q.contains("-category:promotions"))
        XCTAssertTrue(q.contains("receipt"))
    }
}

extension GmailMessage {
    static func decodeTestHelper(_ text: String) -> String {
        GmailImportSource.base64URL(Data(text.utf8))
    }
}
