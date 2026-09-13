import XCTest
@testable import LEVER

/// Live round-trip against Gemini using the build-time key. Skips cleanly when no key is configured (CI, other machines).
final class GeminiLiveTests: XCTestCase {
    func testLiveExtractionThroughAppProvider() async throws {
        guard let key = GeminiIntelligenceProvider.buildDefaultKey else { throw XCTSkip("No Gemini key in Config/Secrets.xcconfig") }
        let provider = GeminiIntelligenceProvider(apiKey: key, model: GeminiIntelligenceProvider.storedModel)
        let doc: PurchaseDocument
        do { doc = try await provider.extractDocument(from: .text("""
        Croma Tax Invoice
        Sony WH-1000XM5 Wireless Headphones  Qty 1
        Grand Total ₹26,990.00
        Invoice Date: 10/09/2026
        Paid by Visa ending 8812
        1 Year Manufacturer Warranty
        """), currencyCode: "INR") } catch { throw XCTSkip("Gemini unavailable right now: \(error.localizedDescription)") }
        XCTAssertEqual(doc.merchant, "Croma")
        XCTAssertEqual(doc.amount, 26_990)
        XCTAssertNotNil(doc.purchaseDate)
        XCTAssertEqual(doc.warranties.first?.months, 12)
        XCTAssertFalse(doc.processedOnDevice)
    }

    func testHybridFallsBackToCloudForMessyText() async throws {
        guard let key = GeminiIntelligenceProvider.buildDefaultKey else { throw XCTSkip("No Gemini key") }
        let text = "Thanks for shopping with Blue Tokai Coffee Roasters. You were charged one thousand two hundred rupees (1200) on 9 September 2026 for the Attikan Estate 500g bag."
        // Probe the API first so quota/network hiccups skip rather than fail.
        let cloud = GeminiIntelligenceProvider(apiKey: key, model: GeminiIntelligenceProvider.storedModel)
        do { _ = try await cloud.extract(text: text) } catch { throw XCTSkip("Gemini unavailable right now: \(error.localizedDescription)") }
        let hybrid = HybridIntelligenceProvider(isCloudEnabled: { true })
        let doc = try await hybrid.extractDocument(from: .text(text), currencyCode: "INR")
        XCTAssertEqual(doc.amount, 1_200)
        XCTAssertTrue(doc.providerName.contains("Gemini"))
    }
}

extension GeminiLiveTests {
    func testVisionReadsReceiptPhoto() async throws {
        guard let key = GeminiIntelligenceProvider.buildDefaultKey else { throw XCTSkip("No Gemini key") }
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/receipt-croma.jpg")
        let data = try Data(contentsOf: url)
        let cloud = GeminiIntelligenceProvider(apiKey: key, model: GeminiIntelligenceProvider.storedModel)
        let e: GeminiIntelligenceProvider.Extraction
        do { e = try await cloud.extract(imageData: data) } catch { throw XCTSkip("Gemini unavailable: \(error.localizedDescription)") }
        XCTAssertEqual(e.merchant?.lowercased().contains("croma"), true)
        XCTAssertEqual(e.amount ?? 0, 34_090.20, accuracy: 0.01)
        XCTAssertEqual(e.warranty_months, 12)
        XCTAssertEqual(e.purchase_date, "2026-09-10")
        XCTAssertEqual(e.currency, "INR")
    }
}
