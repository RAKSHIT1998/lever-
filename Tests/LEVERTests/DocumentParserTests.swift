import XCTest
@testable import LEVER

final class DocumentParserTests: XCTestCase {
    private let parser = DocumentParser()

    private func parse(_ text: String, confidence: Double = 0.95) -> PurchaseDocument {
        parser.parse(RecognizedText(lines: text.components(separatedBy: "\n"), averageConfidence: confidence), currencyCode: "INR")
    }

    func testAmazonOrderConfirmation() {
        let doc = parse("""
        Amazon.in
        Order Confirmation
        Order # 405-7781234-9921107
        Apple MacBook Pro 14-inch M4 Qty: 1
        Order Total: ₹1,49,990.00
        Order date: 12 Sep 2026
        Paid with Visa ending 4421
        Return or replace by 22 Sep 2026
        12 months Apple Limited Warranty
        """)
        XCTAssertEqual(doc.merchant, "Amazon")
        XCTAssertEqual(doc.amount, Decimal(149_990))
        XCTAssertEqual(doc.currencyCode, "INR")
        XCTAssertEqual(doc.orderNumber, "405-7781234-9921107")
        XCTAssertEqual(doc.documentType, .orderConfirmation)
        XCTAssertNotNil(doc.purchaseDate)
        XCTAssertNotNil(doc.returnDeadline)
        XCTAssertEqual(doc.warranties.first?.months, 12)
        XCTAssertEqual(doc.paymentMethod, "Visa ending 4421")
        XCTAssertTrue(doc.productTitle?.contains("MacBook") ?? false)
        XCTAssertEqual(doc.confidence(for: "amount"), .high)
    }

    func testNetflixRenewalNoticeWithPriceIncrease() {
        let doc = parse("""
        Netflix
        Your price is changing
        Your Premium plan will renew on 13 Sep 2026
        New price: ₹1,499/month
        Previously ₹1,199/month
        """)
        XCTAssertEqual(doc.merchant, "Netflix")
        XCTAssertEqual(doc.merchantCategory, .streaming)
        XCTAssertNotNil(doc.subscription)
        XCTAssertEqual(doc.subscription?.billingCycle, .monthly)
        XCTAssertEqual(doc.amount, Decimal(1_499))
        XCTAssertEqual(doc.subscription?.previousPrice, Decimal(1_199))
        XCTAssertNotNil(doc.renewalDate)
    }

    func testHotelBooking() {
        let doc = parse("""
        Booking.com
        Booking confirmation
        Confirmation number: 8827114
        Ubud Jungle Resort
        Check-in: 20 Oct 2026
        Total price INR 48,000
        Free cancellation until 11 Oct 2026
        """)
        XCTAssertEqual(doc.merchant, "Booking.com")
        XCTAssertEqual(doc.documentType, .booking)
        XCTAssertEqual(doc.amount, Decimal(48_000))
        XCTAssertNotNil(doc.serviceDate)
        XCTAssertEqual(doc.referenceNumber, "8827114")
    }

    func testUSDReceiptDetectsCurrency() {
        let doc = parse("""
        Best Buy
        Sony WH-1000XM5 Headphones $349.99
        Subtotal $349.99
        Tax $28.00
        Total $377.99
        03/14/2026
        """)
        XCTAssertEqual(doc.currencyCode, "USD")
        XCTAssertEqual(doc.amount, Decimal(string: "377.99"))
        XCTAssertEqual(doc.merchant, "Best Buy")
    }

    func testUnknownMerchantHasNoInventedFields() {
        let doc = parse("hello world this is not a receipt")
        XCTAssertNil(doc.amount)
        XCTAssertNil(doc.purchaseDate)
        XCTAssertNil(doc.returnDeadline)
        XCTAssertTrue(doc.warranties.isEmpty)
        XCTAssertEqual(doc.overallConfidence, .low)
    }

    func testLowOCRConfidenceLowersFieldConfidence() {
        let clear = parse("Amazon\nTotal ₹500\nOrder date 1 Jan 2026", confidence: 1.0)
        let blurry = parse("Amazon\nTotal ₹500\nOrder date 1 Jan 2026", confidence: 0.5)
        XCTAssertGreaterThan(clear.fieldConfidences["amount"] ?? 0, blurry.fieldConfidences["amount"] ?? 0)
        XCTAssertFalse(blurry.fieldsNeedingVerification.isEmpty)
    }

    func testFeeLineItemsAreExtracted() {
        let doc = parse("""
        MakeMyTrip
        Flight DEL-BOM
        Base fare ₹4,500
        Convenience fee ₹349
        Grand Total ₹4,849
        """)
        XCTAssertEqual(doc.amount, Decimal(4_849))
        XCTAssertTrue(doc.items.contains { $0.name.lowercased().contains("convenience fee") && $0.unitPrice == Decimal(349) })
    }
}

final class AmountParserTests: XCTestCase {
    func testIndianGroupingParses() {
        XCTAssertEqual(AmountParser.parseDecimal("1,49,990.00"), Decimal(149_990))
        XCTAssertEqual(AmountParser.parseDecimal("48,000"), Decimal(48_000))
        XCTAssertEqual(AmountParser.parseDecimal("5.99"), Decimal(string: "5.99"))
        XCTAssertNil(AmountParser.parseDecimal("abc"))
    }

    func testTotalPrefersLabelledLine() {
        let parser = AmountParser()
        let amounts = parser.amounts(in: ["Item A ₹9,000", "Item B ₹500", "Grand Total ₹9,500", "You saved ₹12,000"])
        let (total, confidence) = parser.total(from: amounts)!
        XCTAssertEqual(total.value, Decimal(9_500))
        XCTAssertGreaterThan(confidence, 0.9)
    }

    func testSubtotalIsExcludedWhenUnlabelled() {
        let parser = AmountParser()
        let amounts = parser.amounts(in: ["Subtotal ₹1,000", "₹1,180"])
        XCTAssertEqual(parser.total(from: amounts)?.0.value, Decimal(1_180))
    }
}

final class DateParserTests: XCTestCase {
    func testExplicitFormats() {
        let dates = DateParser.explicitDates(in: "Order date: 12 Sep 2026, invoice 2026-09-13, paid 14/09/2026")
        XCTAssertEqual(dates.count, 3)
        let days = dates.map { Calendar.current.component(.day, from: $0) }
        XCTAssertEqual(Set(days), [12, 13, 14])
    }

    func testLabelsAreAttached() {
        let parsed = DateParser().dates(in: ["Return by 22 Sep 2026", "Renews on 1 Oct 2026", "Warranty valid until 12 Sep 2027"])
        XCTAssertEqual(parsed.first { $0.label == "returnDeadline" }?.lineIndex, 0)
        XCTAssertEqual(parsed.first { $0.label == "renewal" }?.lineIndex, 1)
        XCTAssertEqual(parsed.first { $0.label == "warrantyEnd" }?.lineIndex, 2)
    }

    func testAmbiguousDayMonthPrefersDayFirst() {
        let date = DateParser.explicitDates(in: "05/09/2026").first!
        XCTAssertEqual(Calendar.current.component(.month, from: date), 9)
        XCTAssertEqual(Calendar.current.component(.day, from: date), 5)
    }
}
