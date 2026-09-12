import Foundation
import SwiftData

@Model
final class Subscription {
    @Attribute(.unique) var id: UUID
    var merchantName: String
    var price: Decimal
    var currencyCode: String
    var billingCycleRaw: String
    var nextBillingDate: Date?
    var previousPrice: Decimal?
    var lastUsedDate: Date?
    var statusRaw: String
    var confidenceRaw: String
    var source: String
    var purchase: Purchase?

    init(
        id: UUID = UUID(),
        merchantName: String,
        price: Decimal,
        currencyCode: String,
        billingCycle: BillingCycle,
        nextBillingDate: Date? = nil,
        previousPrice: Decimal? = nil,
        status: SubscriptionStatus = .active,
        confidence: Confidence = .medium,
        source: String = "Document"
    ) {
        self.id = id
        self.merchantName = merchantName
        self.price = price
        self.currencyCode = currencyCode
        self.billingCycleRaw = billingCycle.rawValue
        self.nextBillingDate = nextBillingDate
        self.previousPrice = previousPrice
        self.statusRaw = status.rawValue
        self.confidenceRaw = confidence.rawValue
        self.source = source
    }

    var billingCycle: BillingCycle {
        get { BillingCycle(rawValue: billingCycleRaw) ?? .unknown }
        set { billingCycleRaw = newValue.rawValue }
    }

    var status: SubscriptionStatus {
        get { SubscriptionStatus(rawValue: statusRaw) ?? .unknown }
        set { statusRaw = newValue.rawValue }
    }

    var confidence: Confidence { Confidence(rawValue: confidenceRaw) ?? .low }

    var annualCost: Decimal? { SubscriptionMath.annualCost(price: price, cycle: billingCycle) }

    var annualIncrease: Decimal? {
        guard let previousPrice else { return nil }
        return SubscriptionMath.annualIncrease(current: price, previous: previousPrice, cycle: billingCycle)
    }
}

/// Pure functions so subscription arithmetic is trivially testable.
enum SubscriptionMath {
    static func annualCost(price: Decimal, cycle: BillingCycle) -> Decimal? {
        guard let periods = cycle.periodsPerYear else { return nil }
        return price * periods
    }

    static func annualIncrease(current: Decimal, previous: Decimal, cycle: BillingCycle) -> Decimal? {
        guard current > previous, let periods = cycle.periodsPerYear else { return nil }
        return (current - previous) * periods
    }

    static func increasePercent(current: Decimal, previous: Decimal) -> Decimal? {
        guard previous > 0, current > previous else { return nil }
        return ((current - previous) / previous * 100).rounded(scale: 0)
    }

    static func nextBillingDate(after date: Date, cycle: BillingCycle, calendar: Calendar = .current, now: Date = .now) -> Date? {
        guard let (component, value) = cycle.calendarComponent else { return nil }
        var candidate = date
        var guardCounter = 0
        while candidate < now, guardCounter < 600 {
            guard let next = calendar.date(byAdding: component, value: value, to: candidate) else { return nil }
            candidate = next
            guardCounter += 1
        }
        return candidate
    }
}
