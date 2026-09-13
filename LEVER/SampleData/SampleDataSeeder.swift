import Foundation
import SwiftData

/// Fixture data for automated UI tests and SwiftUI previews ONLY. The shipping app never calls this —
/// real users start with an empty vault and everything they see comes from their own documents.
@MainActor
enum SampleDataSeeder {
    static func seedIfNeeded(_ repo: PurchaseRepository, force: Bool = false) {
        let settings = repo.settings()
        guard force || !settings.sampleDataSeeded else { return }
        guard force || repo.allPurchases().isEmpty else { return }
        let ctx = repo.context
        let now = Date.now
        let code = "INR"
        repo.profile().currencyCode = code

        func day(_ offset: Int) -> Date { DateMath.adding(days: offset, to: now) ?? now }

        // 1. MacBook Pro — return window closing, warranty tracked, price drop recorded.
        let mac = Purchase(title: "MacBook Pro 14\"", merchantName: "Amazon", merchantCategory: .electronics, documentType: .orderConfirmation, amount: 149_990, currencyCode: code, purchaseDate: day(-6), tags: ["electronics", "order confirmation"])
        mac.orderNumber = "405-7781234-9921107"
        mac.serialNumber = "C02XL0G9JGH5"
        mac.paymentMethod = "Visa ending 4421"
        mac.merchant = repo.upsertMerchant(named: "Amazon", category: .retail)
        ctx.insert(mac)
        let macReturn = ReturnWindow(deadline: day(4), daysAllowed: 10, policySource: "Typical Amazon policy — verify", policyDate: now, confidence: .medium)
        macReturn.purchase = mac
        ctx.insert(macReturn)
        let macWarranty = Warranty(provider: "Apple", type: .manufacturer, startDate: day(-6), endDate: DateMath.adding(months: 12, to: day(-6)), coverageSummary: "12 months", source: "Duration stated in document", confidence: .medium)
        macWarranty.purchase = mac
        ctx.insert(macWarranty)
        let macPrice = PriceObservation(productURL: "https://www.amazon.in/dp/B0EXAMPLE", observedPrice: 142_990, currencyCode: code, observedAt: day(-1), source: "Entered by you")
        macPrice.purchase = mac
        ctx.insert(macPrice)
        let macDoc = StoredDocument(kind: .text, rawText: "Amazon.in Order Confirmation\nOrder # 405-7781234-9921107\nApple MacBook Pro 14-inch M4\nOrder Total ₹1,49,990.00\nOrder date: \(day(-6).leverShort)\nPaid with Visa ending 4421\n12 months Apple Limited Warranty")
        macDoc.purchase = mac
        ctx.insert(macDoc)

        // 2. Netflix — renews tomorrow, price increased.
        let netflix = Purchase(title: "Netflix Premium", merchantName: "Netflix", merchantCategory: .streaming, documentType: .renewalNotice, amount: 1_499, currencyCode: code, purchaseDate: day(-29), tags: ["subscription", "streaming"])
        netflix.merchant = repo.upsertMerchant(named: "Netflix", category: .streaming)
        ctx.insert(netflix)
        let netflixSub = Subscription(merchantName: "Netflix", price: 1_499, currencyCode: code, billingCycle: .monthly, nextBillingDate: day(1), previousPrice: 1_199, status: .active, confidence: .high, source: "Renewal notice")
        netflixSub.purchase = netflix
        ctx.insert(netflixSub)

        // 3. Bali hotel — price dropped.
        let hotel = Purchase(title: "Ubud Jungle Resort, Bali", merchantName: "Booking.com", merchantCategory: .travel, documentType: .booking, amount: 48_000, currencyCode: code, purchaseDate: day(-12), tags: ["travel", "booking"])
        hotel.referenceNumber = "BK-8827-114"
        hotel.serviceDate = day(38)
        hotel.merchant = repo.upsertMerchant(named: "Booking.com", category: .travel)
        ctx.insert(hotel)
        let hotelReturn = ReturnWindow(deadline: day(31), daysAllowed: nil, policySource: "Stated in document", policyDate: now, confidence: .high)
        hotelReturn.purchase = hotel
        ctx.insert(hotelReturn)
        let hotelPrice = PriceObservation(productURL: nil, observedPrice: 40_600, currencyCode: code, observedAt: day(-1), source: "Entered by you")
        hotelPrice.purchase = hotel
        ctx.insert(hotelPrice)

        // 4. iPhone — warranty expiring in 21 days.
        let iphone = Purchase(title: "iPhone 15 Pro", merchantName: "Apple", merchantCategory: .electronics, documentType: .receipt, amount: 89_999, currencyCode: code, purchaseDate: DateMath.adding(months: -12, to: day(21)), tags: ["electronics", "receipt"])
        iphone.serialNumber = "F2LXK9QJ0D3"
        iphone.merchant = repo.upsertMerchant(named: "Apple", category: .electronics)
        ctx.insert(iphone)
        let iphoneWarranty = Warranty(provider: "Apple", type: .manufacturer, startDate: iphone.purchaseDate, endDate: day(21), coverageSummary: "Apple Limited Warranty, 12 months", source: "Stated in document", confidence: .high)
        iphoneWarranty.purchase = iphone
        ctx.insert(iphoneWarranty)

        // 5. Home insurance — renews in 40 days.
        let insurance = Purchase(title: "HDFC ERGO Home Shield", merchantName: "HDFC ERGO", merchantCategory: .insurance, documentType: .insurance, amount: 18_000, currencyCode: code, purchaseDate: DateMath.adding(months: -11, to: now), tags: ["insurance"])
        insurance.policyNumber = "2919 2033 4411 00"
        insurance.merchant = repo.upsertMerchant(named: "HDFC ERGO", category: .insurance)
        ctx.insert(insurance)
        let insuranceSub = Subscription(merchantName: "HDFC ERGO", price: 18_000, currencyCode: code, billingCycle: .yearly, nextBillingDate: day(40), status: .active, confidence: .high, source: "Policy document")
        insuranceSub.purchase = insurance
        ctx.insert(insuranceSub)

        // 6. Airtel broadband bill with a fee and a marked-unused Spotify.
        let airtel = Purchase(title: "Airtel Xstream Fiber bill", merchantName: "Airtel", merchantCategory: .telecom, documentType: .bill, amount: 1_178, currencyCode: code, purchaseDate: day(-3), tags: ["bill"])
        airtel.merchant = repo.upsertMerchant(named: "Airtel", category: .telecom)
        ctx.insert(airtel)
        for (name, price) in [("Xstream Fiber 200 Mbps plan", Decimal(999)), ("Late payment fee", Decimal(100)), ("GST", Decimal(79))] {
            let item = PurchaseItem(name: name, quantity: 1, unitPrice: price)
            item.purchase = airtel
            ctx.insert(item)
        }
        let spotify = Purchase(title: "Spotify Premium", merchantName: "Spotify", merchantCategory: .streaming, documentType: .subscription, amount: 119, currencyCode: code, purchaseDate: day(-25), tags: ["subscription"])
        spotify.merchant = repo.upsertMerchant(named: "Spotify", category: .streaming)
        ctx.insert(spotify)
        let spotifySub = Subscription(merchantName: "Spotify", price: 119, currencyCode: code, billingCycle: .monthly, nextBillingDate: day(5), status: .markedUnused, confidence: .high, source: "App Store receipt")
        spotifySub.purchase = spotify
        ctx.insert(spotifySub)

        // Confirmed savings history.
        let history: [(SavingsKind, Decimal, String, Int)] = [
            (.recovered, 7_400, "Hotel price recovery", -20),
            (.avoided, 3_600, "Subscription avoided", -34),
            (.recovered, 2_100, "Refund recovered", -47),
            (.saved, 1_299, "Warranty claim", -61),
            (.negotiated, 2_400, "Broadband retention discount", -75),
        ]
        for (kind, amount, title, offset) in history {
            let event = SavingsEvent(kind: kind, amount: amount, currencyCode: code, title: title, status: .confirmed, date: day(offset))
            event.confirmedAt = day(offset)
            ctx.insert(event)
        }

        settings.sampleDataSeeded = true
        settings.capturesUsed = 2
        try? ctx.save()

        Task { @MainActor in
            await repo.refreshAllOpportunities()
        }
    }
}
