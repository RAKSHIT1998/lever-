import XCTest
@testable import LEVER

final class PaymentQRParserTests: XCTestCase {
    func testUPIURL() {
        let r = PaymentQRParser.parse("upi://pay?pa=bluetokai@icici&pn=Blue%20Tokai%20Coffee&am=499.00&cu=INR&tn=Order%2012", defaultCurrency: "INR")!
        XCTAssertEqual(r.rail, "UPI")
        XCTAssertEqual(r.payeeAddress, "bluetokai@icici")
        XCTAssertEqual(r.merchantName, "Blue Tokai Coffee")
        XCTAssertEqual(r.amount, 499)
        XCTAssertEqual(r.currencyCode, "INR")
        XCTAssertEqual(r.note, "Order 12")
        XCTAssertTrue(r.isPayable)
    }

    func testUPIWithoutAmountAndAppURLBuilding() {
        let r = PaymentQRParser.parse("upi://pay?pa=shop.9981@paytm&pn=Corner+Shop&cu=INR", defaultCurrency: "INR")!
        XCTAssertNil(r.amount)
        let url = PaymentQRParser.upiURL(for: r, template: "gpay://upi/pay?", amount: 250)!
        XCTAssertEqual(url.scheme, "gpay")
        XCTAssertTrue(url.absoluteString.contains("pa=shop.9981@paytm"))
        XCTAssertTrue(url.absoluteString.contains("am=250"))
        XCTAssertTrue(url.absoluteString.contains("pn=Corner%20Shop"))
    }

    func testEMVCoPIX() {
        // Minimal PIX payload: 26 (merchant account) with GUI + key, 52 category, 53 currency 986, 54 amount, 58 BR, 59 name, 60 city, 62 additional (05 = ref)
        let payload = "000201" + "26580014br.gov.bcb.pix0136123e4567-e89b-12d3-a456-426614174000" + "52040000" + "5303986" + "540545.90" + "5802BR" + "5911Padaria Sol" + "6009Sao Paulo" + "62070503abc" + "6304ABCD"
        let r = PaymentQRParser.parse(payload, defaultCurrency: "INR")!
        XCTAssertEqual(r.rail, "PIX")
        XCTAssertEqual(r.currencyCode, "BRL")
        XCTAssertEqual(r.amount, Decimal(string: "45.90"))
        XCTAssertEqual(r.merchantName, "Padaria Sol")
        XCTAssertEqual(r.countryCode, "BR")
        XCTAssertEqual(r.reference, "abc")
        XCTAssertNotNil(r.payeeAddress)
    }

    func testEMVCoPayNowRailByCountry() {
        let payload = "000201" + "26330009SG.PAYNOW010120210+6591234567" + "5303702" + "5802SG" + "5910Kopi Stall" + "6304FFFF"
        let r = PaymentQRParser.parse(payload, defaultCurrency: "INR")!
        XCTAssertEqual(r.rail, "PayNow"); XCTAssertEqual(r.currencyCode, "SGD"); XCTAssertNil(r.amount)
    }

    func testGarbageIsRejected() {
        XCTAssertNil(PaymentQRParser.parse("https://example.com/menu", defaultCurrency: "INR"))
        XCTAssertNil(PaymentQRParser.parse("hello", defaultCurrency: "INR"))
    }

    func testRegionDetection() {
        XCTAssertEqual(PaymentRegion.detect(locale: Locale(identifier: "en_IN")), .india)
        XCTAssertEqual(PaymentRegion.detect(locale: Locale(identifier: "pt_BR")), .brazil)
        XCTAssertEqual(PaymentRegion.detect(locale: Locale(identifier: "en_US")), .other)
        XCTAssertTrue(PaymentRegion.india.apps.contains { $0.scheme == "upi" })
    }
}

final class PaymentMessageParserTests: XCTestCase {
    func testGooglePayReceiptScreenshot() {
        let text = """
        Google Pay
        ₹499
        Paid to Blue Tokai Coffee Roasters
        bluetokai.payu@hdfcbank
        Completed · 13 Sep 2026, 9:41 am
        UPI transaction ID 426581234567
        From HDFC Bank ****4421
        """
        let m = PaymentMessageParser.parse(text, defaultCurrency: "INR")!
        XCTAssertEqual(m.app, "Google Pay")
        XCTAssertEqual(m.amount, 499)
        XCTAssertEqual(m.merchant, "Blue Tokai Coffee Roasters")
        XCTAssertEqual(m.payeeAddress, "bluetokai.payu@hdfcbank")
        XCTAssertEqual(m.reference, "426581234567")
        XCTAssertTrue(m.isDebit)
        XCTAssertNotNil(m.date)
    }

    func testBankDebitSMS() {
        let text = "Rs.1499.00 debited from A/c XX1234 to VPA netflix.upi@icici on 12-09-26. UPI Ref 426512345678. Not you? Call 1800xxxx -HDFC Bank"
        let m = PaymentMessageParser.parse(text, defaultCurrency: "INR")!
        XCTAssertEqual(m.amount, 1_499)
        XCTAssertEqual(m.payeeAddress, "netflix.upi@icici")
        XCTAssertEqual(m.merchant, "Netflix")
        XCTAssertEqual(m.bankAccountHint, "XX1234")
        XCTAssertEqual(m.reference, "426512345678")
        XCTAssertTrue(m.isDebit)
    }

    func testCreditIsNotADebit() {
        let m = PaymentMessageParser.parse("Rs.500.00 credited to A/c XX1234 by VPA rahul@okaxis on 12-09-26. UPI Ref 4265. -SBI", defaultCurrency: "INR")!
        XCTAssertFalse(m.isDebit)
    }

    func testUnrelatedTextIsNil() {
        XCTAssertNil(PaymentMessageParser.parse("Your OTP is 482913. Do not share it with anyone.", defaultCurrency: "INR"))
    }

    func testDocumentParserPromotesUPIReceipt() {
        let doc = DocumentParser().parse(RecognizedText(lines: ["PhonePe", "Paid to Croma", "₹26,990", "Success · 10 Sep 2026", "UPI Ref No 428811223344", "Debited from Axis Bank XX8812"], averageConfidence: 0.95), currencyCode: "INR")
        XCTAssertEqual(doc.merchant, "Croma")
        XCTAssertEqual(doc.amount, 26_990)
        XCTAssertEqual(doc.paymentMethod, "UPI · PhonePe")
        XCTAssertEqual(doc.referenceNumber, "428811223344")
        XCTAssertTrue(doc.tags.contains("upi"))
        XCTAssertEqual(doc.documentType, .receipt)
    }

    func testVPAHandleToName() {
        XCTAssertEqual(PaymentMessageParser.merchantName(fromVPA: "netflix.upi@icici"), "Netflix")
        XCTAssertEqual(PaymentMessageParser.merchantName(fromVPA: "blue.tokai.coffee@ybl"), "Blue Tokai Coffee")
        XCTAssertNil(PaymentMessageParser.merchantName(fromVPA: "paytmqr28100505010111@paytm"))
    }
}

final class PaymentAppStatementTests: XCTestCase {
    func testPhonePeStyleExport() {
        let csv = """
        Date,Transaction Details,Type,Amount
        "Sep 01, 2026",Paid to Netflix,DEBIT,₹1499
        "Aug 01, 2026",Paid to Netflix,DEBIT,₹1499
        "Aug 15, 2026",Received from Rahul Sharma,CREDIT,₹2000
        "Jul 01, 2026",Paid to Netflix,DEBIT,₹1199
        """
        let txns = StatementImporter().parse(csv, defaultCurrency: "INR")
        XCTAssertEqual(txns.count, 4)
        XCTAssertEqual(txns.filter(\.isDebit).count, 3)
        XCTAssertEqual(txns.filter { $0.merchantName == "Netflix" }.count, 3)
        let recurring = RecurringChargeDetector.detect(txns)
        XCTAssertEqual(recurring.first?.merchantName, "Netflix")
        XCTAssertEqual(recurring.first?.previousAmount, 1_199)
    }

    func testPaytmStyleExportWithVPA() {
        let csv = """
        Date,Activity,Source/Destination,Debit,Credit
        01/09/2026,Money sent,spotify.india@hdfcbank,119,
        01/08/2026,Money sent,spotify.india@hdfcbank,119,
        """
        let txns = StatementImporter().parse(csv, defaultCurrency: "INR")
        XCTAssertEqual(txns.count, 2)
        XCTAssertEqual(txns.first?.merchantName, "Spotify")
    }
}
