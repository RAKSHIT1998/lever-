import XCTest
@testable import LEVER

final class StatementImporterTests: XCTestCase {
    private let importer = StatementImporter()

    func testParsesIndianBankCSV() {
        let csv = """
        Account Statement
        Date,Narration,Chq/Ref No,Withdrawal Amt,Deposit Amt,Closing Balance
        01/06/2026,UPI-NETFLIX.COM-8821,UPI1,1199.00,,45000.00
        03/06/2026,SALARY CREDIT,NEFT2,,85000.00,130000.00
        01/07/2026,UPI-NETFLIX.COM-9931,UPI3,1199.00,,120000.00
        01/08/2026,UPI-NETFLIX.COM-1201,UPI4,1499.00,,110000.00
        15/07/2026,POS 4421 CROMA MUMBAI,POS5,"12,499.00",,95000.00
        """
        let txns = importer.parse(csv, defaultCurrency: "INR")
        XCTAssertEqual(txns.count, 5)
        let netflix = txns.filter { $0.merchantName == "Netflix" }
        XCTAssertEqual(netflix.count, 3)
        XCTAssertTrue(netflix.allSatisfy(\.isDebit))
        XCTAssertEqual(txns.first { $0.description.contains("SALARY") }?.isDebit, false)
        XCTAssertEqual(txns.first { $0.merchantName == "Croma" }?.amount, Decimal(12_499))
        XCTAssertTrue(importer.looksLikeStatement(csv))
    }

    func testParsesSignedAmountCSV() {
        let csv = """
        Date,Description,Amount,Currency
        2026-05-14,SPOTIFY USA,-9.99,USD
        2026-06-14,SPOTIFY USA,-9.99,USD
        2026-06-20,REFUND AMAZON,25.00,USD
        """
        let txns = importer.parse(csv, defaultCurrency: "INR")
        XCTAssertEqual(txns.count, 3)
        XCTAssertEqual(txns[0].currencyCode, "USD")
        XCTAssertTrue(txns[0].isDebit)
        XCTAssertFalse(txns[2].isDebit)
        XCTAssertEqual(txns[0].merchantName, "Spotify")
    }

    func testParsesFreeformPDFLines() {
        let text = """
        HDFC Bank Statement  Account Number XXXX1234
        Opening Balance 50,000.00
        12/06/2026 ACH D- JIOFIBER BROADBAND 999.00 Dr
        12/07/2026 ACH D- JIOFIBER BROADBAND 999.00 Dr
        20/07/2026 IMPS CREDIT FROM RAHUL 5,000.00 Cr
        12/08/2026 ACH D- JIOFIBER BROADBAND 1,199.00 Dr
        Closing Balance 42,803.00
        """
        let txns = importer.parse(text, defaultCurrency: "INR")
        XCTAssertEqual(txns.count, 4)
        XCTAssertEqual(txns.filter(\.isDebit).count, 3)
        XCTAssertEqual(txns.filter { $0.merchantName == "Jio" }.count, 3)
        XCTAssertFalse(txns.contains { $0.description.lowercased().contains("balance") })
    }

    func testMerchantNormalisationStripsNoise() {
        XCTAssertEqual(StatementImporter.merchant(from: "POS 4421 CROMA MUMBAI 8821").0, "Croma")
        let (name, _) = StatementImporter.merchant(from: "UPI-BLUE TOKAI COFFEE-99182 PAYMENT")
        XCTAssertEqual(name, "Blue Tokai Coffee")
    }
}

final class RecurringChargeDetectorTests: XCTestCase {
    private func txn(_ merchant: String, _ amount: Decimal, daysAgo: Int) -> StatementTransaction {
        StatementTransaction(date: DateMath.adding(days: -daysAgo, to: .now)!, description: merchant, amount: amount, currencyCode: "INR", isDebit: true, merchantName: merchant, category: .streaming)
    }

    func testDetectsMonthlyWithPriceIncrease() {
        let txns = [txn("Netflix", 1_199, daysAgo: 70), txn("Netflix", 1_199, daysAgo: 40), txn("Netflix", 1_499, daysAgo: 10), txn("Croma", 12_499, daysAgo: 30)]
        let found = RecurringChargeDetector.detect(txns)
        XCTAssertEqual(found.count, 1)
        let netflix = found[0]
        XCTAssertEqual(netflix.cycle, .monthly)
        XCTAssertEqual(netflix.latestAmount, 1_499)
        XCTAssertEqual(netflix.previousAmount, 1_199)
        XCTAssertEqual(netflix.confidence, .high)
        XCTAssertEqual(netflix.annualCost, 17_988)
        XCTAssertNotNil(netflix.nextDate)
        XCTAssertGreaterThan(netflix.nextDate!, .now)
    }

    func testTwoOccurrencesAreMediumConfidence() {
        let found = RecurringChargeDetector.detect([txn("Spotify", 119, daysAgo: 35), txn("Spotify", 119, daysAgo: 5)])
        XCTAssertEqual(found.first?.confidence, .medium)
        XCTAssertEqual(found.first?.cycle, .monthly)
    }

    func testIrregularGapsOrWildAmountsAreNotSubscriptions() {
        XCTAssertTrue(RecurringChargeDetector.detect([txn("Swiggy", 450, daysAgo: 20), txn("Swiggy", 820, daysAgo: 3)]).isEmpty, "Amounts too different")
        XCTAssertTrue(RecurringChargeDetector.detect([txn("Uber", 300, daysAgo: 44), txn("Uber", 300, daysAgo: 30), txn("Uber", 300, daysAgo: 2)]).isEmpty, "Gaps irregular")
    }

    func testYearlyAndWeeklyCycles() {
        XCTAssertEqual(RecurringChargeDetector.cycle(forGaps: [365]), .yearly)
        XCTAssertEqual(RecurringChargeDetector.cycle(forGaps: [7, 7, 8]), .weekly)
        XCTAssertEqual(RecurringChargeDetector.cycle(forGaps: [90, 92]), .quarterly)
        XCTAssertNil(RecurringChargeDetector.cycle(forGaps: [15, 45]))
    }

    func testCreditsAreIgnored() {
        var refund = txn("Netflix", 1_199, daysAgo: 40); refund.isDebit = false
        XCTAssertTrue(RecurringChargeDetector.detect([refund, txn("Netflix", 1_199, daysAgo: 10)]).isEmpty)
    }
}

final class PriceExtractionTests: XCTestCase {
    func testOpenGraphPrice() {
        let html = #"<html><head><meta property="product:price:amount" content="1299.00"><meta property="product:price:currency" content="INR"></head></html>"#
        XCTAssertEqual(PublicPagePriceMonitor.extractPrice(from: html), Decimal(string: "1299.00"))
    }

    func testJSONLDPriceWithEuropeanFormat() {
        let html = #"<script type="application/ld+json">{"@type":"Product","offers":{"@type":"Offer","price":"1.299,00","priceCurrency":"EUR"}}</script>"#
        XCTAssertEqual(PublicPagePriceMonitor.extractPrice(from: html), Decimal(1_299))
    }

    func testNoPriceReturnsNil() {
        XCTAssertNil(PublicPagePriceMonitor.extractPrice(from: "<html><body>Out of stock</body></html>"))
    }

    func testMostCommonValueWins() {
        let html = #"{"price":"999"} ... {"price":"999"} ... {"price":"1099"}"#
        XCTAssertEqual(PublicPagePriceMonitor.extractPrice(from: html), Decimal(999))
    }
}

@MainActor
final class RecurringImportTests: XCTestCase {
    func testImportCreatesWatchedSubscriptionsAndOpportunities() async {
        let env = AppEnvironment.preview(seeded: false)
        let candidate = RecurringCandidate(merchantName: "Netflix", category: .streaming, typicalAmount: 1_199, latestAmount: 1_499, previousAmount: 1_199, currencyCode: "INR", cycle: .monthly, occurrences: 3, lastDate: DateMath.adding(days: -28, to: .now)!, nextDate: DateMath.adding(days: 2, to: .now), confidence: .high)
        let created = await env.repository.importRecurringCharges([candidate], source: "Statement", statementText: "01/08/2026 NETFLIX 1499.00")
        XCTAssertEqual(created.count, 1)
        let purchase = created[0]
        XCTAssertEqual(purchase.subscription?.previousPrice, 1_199)
        XCTAssertEqual(purchase.subscription?.source, "Statement")
        XCTAssertTrue(purchase.openOpportunities.contains { $0.type == .negotiation })
        XCTAssertTrue(purchase.openOpportunities.contains { $0.type == .subscriptionRenewal })
        XCTAssertEqual(purchase.documents.count, 1)

        // Importing again updates instead of duplicating.
        let again = await env.repository.importRecurringCharges([candidate], source: "Statement")
        XCTAssertTrue(again.isEmpty)
        XCTAssertEqual(env.repository.allPurchases().count, 1)
    }
}
