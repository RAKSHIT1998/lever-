import XCTest
@testable import LEVER

/// Live round-trip against Gemini using the build-time key. Skips cleanly when no key is configured (CI, other machines).
final class GeminiLiveTests: XCTestCase {
    func testLiveExtractionThroughAppProvider() async throws {
        guard let key = GeminiIntelligenceProvider.buildDefaultKey else { throw XCTSkip("No Gemini key in Config/Secrets.xcconfig") }
        let provider = GeminiIntelligenceProvider(apiKey: key, model: GeminiIntelligenceProvider.storedModel)
        let doc = try await provider.extractDocument(from: .text("""
        Croma Tax Invoice
        Sony WH-1000XM5 Wireless Headphones  Qty 1
        Grand Total ₹26,990.00
        Invoice Date: 10/09/2026
        Paid by Visa ending 8812
        1 Year Manufacturer Warranty
        """), currencyCode: "INR")
        XCTAssertEqual(doc.merchant, "Croma")
        XCTAssertEqual(doc.amount, 26_990)
        XCTAssertNotNil(doc.purchaseDate)
        XCTAssertEqual(doc.warranties.first?.months, 12)
        XCTAssertFalse(doc.processedOnDevice)
    }

    func testHybridFallsBackToCloudForMessyText() async throws {
        guard GeminiIntelligenceProvider.buildDefaultKey != nil else { throw XCTSkip("No Gemini key") }
        let hybrid = HybridIntelligenceProvider(isCloudEnabled: { true })
        // No currency symbol, odd layout: the local parser can't find a total; Gemini should.
        let doc = try await hybrid.extractDocument(from: .text("Thanks for shopping with Blue Tokai Coffee Roasters. You were charged one thousand two hundred rupees (1200) on 9 September 2026 for the Attikan Estate 500g bag."), currencyCode: "INR")
        XCTAssertEqual(doc.amount, 1_200)
        XCTAssertTrue(doc.providerName.contains("Gemini"))
    }
}
