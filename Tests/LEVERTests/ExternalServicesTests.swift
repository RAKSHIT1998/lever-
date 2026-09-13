import XCTest
@testable import LEVER

final class GeminiMergeTests: XCTestCase {
    private func extraction(_ json: String) throws -> GeminiIntelligenceProvider.Extraction {
        try JSONDecoder().decode(GeminiIntelligenceProvider.Extraction.self, from: Data(json.utf8))
    }

    func testCloudFillsOnlyMissingOrWeakFields() throws {
        var doc = PurchaseDocument(rawText: "x", currencyCode: "INR")
        doc.merchant = "Amazon"; doc.fieldConfidences["merchant"] = 0.95   // strong — must be kept
        doc.amount = 500; doc.fieldConfidences["amount"] = 0.5             // weak — may be replaced
        let e = try extraction(#"{"merchant":"Flipkart","amount":1499,"purchase_date":"2026-09-12","document_type":"orderConfirmation","warranty_months":12,"order_number":"OD123456","items":[{"name":"Kettle","price":1499}]}"#)
        GeminiIntelligenceProvider.apply(e, to: &doc, confidence: 0.75)
        XCTAssertEqual(doc.merchant, "Amazon", "High-confidence local read wins")
        XCTAssertEqual(doc.amount, 1499, "Weak local read is replaced")
        XCTAssertEqual(doc.fieldConfidences["amount"], 0.75)
        XCTAssertEqual(doc.documentType, .orderConfirmation)
        XCTAssertEqual(Calendar.current.component(.day, from: doc.purchaseDate!), 12)
        XCTAssertEqual(doc.warranties.first?.months, 12)
        XCTAssertEqual(doc.warranties.first?.confidence, .medium, "Cloud reads are never high confidence")
        XCTAssertEqual(doc.orderNumber, "OD123456")
        XCTAssertEqual(doc.items.first?.name, "Kettle")
    }

    func testNullsAndBadDatesAreIgnored() throws {
        var doc = PurchaseDocument(rawText: "x", currencyCode: "INR")
        let e = try extraction(#"{"merchant":null,"amount":null,"purchase_date":"next tuesday","billing_cycle":"monthly","previous_price":999}"#)
        GeminiIntelligenceProvider.apply(e, to: &doc, confidence: 0.75)
        XCTAssertNil(doc.merchant)
        XCTAssertNil(doc.amount)
        XCTAssertNil(doc.purchaseDate, "Unparseable dates are dropped, never guessed")
        XCTAssertEqual(doc.subscription?.billingCycle, .monthly)
        XCTAssertEqual(doc.subscription?.previousPrice, 999)
        XCTAssertEqual(doc.overallConfidence, .low)
    }

    func testHybridOnlyAsksForHelpWhenUnsure() {
        var confident = PurchaseDocument(rawText: "x", currencyCode: "INR")
        confident.merchant = "Amazon"; confident.amount = 1; confident.purchaseDate = .now; confident.overallConfidence = .high
        XCTAssertFalse(HybridIntelligenceProvider.needsHelp(confident))
        var unsure = confident; unsure.amount = nil
        XCTAssertTrue(HybridIntelligenceProvider.needsHelp(unsure))
    }

    func testResponseSchemaCoversAllDocumentTypes() {
        let props = GeminiIntelligenceProvider.responseSchema["properties"] as! [String: Any]
        let type = props["document_type"] as! [String: Any]
        XCTAssertEqual((type["enum"] as! [String]).count, DocumentType.allCases.count)
    }
}

final class ExchangeRateTests: XCTestCase {
    func testSameCurrencyIsIdentityWithoutNetwork() async {
        let r = await ExchangeRateService.shared.rate(from: "INR", to: "INR")
        XCTAssertEqual(r, 1)
        let c = await ExchangeRateService.shared.convert(250, from: "USD", to: "USD")
        XCTAssertEqual(c, 250)
    }
}

final class MerchantIdentityTests: XCTestCase {
    func testLogoURLsAreWellFormed() {
        XCTAssertEqual(MerchantIdentityService.logoURL(domain: "netflix.com")?.host, "t3.gstatic.com")
        XCTAssertEqual(MerchantIdentityService.fallbackLogoURL(domain: "netflix.com")?.path, "/ip3/netflix.com.ico")
    }

    func testShortNamesAreNotLookedUp() async {
        let identity = await MerchantIdentityService().identity(for: "Vi")
        XCTAssertNil(identity)
    }
}
