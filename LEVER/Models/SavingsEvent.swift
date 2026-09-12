import Foundation
import SwiftData

/// Money the user saved, recovered, avoided, protected or negotiated.
/// Only `confirmed` events count towards totals — LEVER never inflates its own scoreboard.
@Model
final class SavingsEvent {
    @Attribute(.unique) var id: UUID
    var kindRaw: String
    var amount: Decimal
    var currencyCode: String
    var title: String
    var statusRaw: String
    var date: Date
    var confirmedAt: Date?
    var purchase: Purchase?
    var opportunity: Opportunity?

    init(id: UUID = UUID(), kind: SavingsKind, amount: Decimal, currencyCode: String, title: String, status: SavingsStatus = .pending, date: Date = .now) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.amount = amount
        self.currencyCode = currencyCode
        self.title = title
        self.statusRaw = status.rawValue
        self.date = date
    }

    var kind: SavingsKind {
        get { SavingsKind(rawValue: kindRaw) ?? .saved }
        set { kindRaw = newValue.rawValue }
    }

    var status: SavingsStatus {
        get { SavingsStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    func confirm(amount: Decimal? = nil) {
        if let amount { self.amount = amount }
        status = .confirmed
        confirmedAt = .now
    }
}

@Model
final class PriceObservation {
    var productURL: String?
    var observedPrice: Decimal
    var currencyCode: String
    var observedAt: Date
    var source: String
    var purchase: Purchase?

    init(productURL: String?, observedPrice: Decimal, currencyCode: String, observedAt: Date = .now, source: String) {
        self.productURL = productURL
        self.observedPrice = observedPrice
        self.currencyCode = currencyCode
        self.observedAt = observedAt
        self.source = source
    }
}

@Model
final class NotificationRule {
    @Attribute(.unique) var identifier: String
    var fireDate: Date
    var title: String
    var body: String
    var purchaseID: UUID?
    var opportunityID: UUID?
    var isScheduled: Bool

    init(identifier: String, fireDate: Date, title: String, body: String, purchaseID: UUID? = nil, opportunityID: UUID? = nil) {
        self.identifier = identifier
        self.fireDate = fireDate
        self.title = title
        self.body = body
        self.purchaseID = purchaseID
        self.opportunityID = opportunityID
        self.isScheduled = false
    }
}

@Model
final class UserProfile {
    @Attribute(.unique) var id: UUID
    var displayName: String?
    var currencyCode: String
    var householdID: UUID?
    var createdAt: Date

    init(id: UUID = UUID(), displayName: String? = nil, currencyCode: String, householdID: UUID? = nil) {
        self.id = id
        self.displayName = displayName
        self.currencyCode = currencyCode
        self.householdID = householdID
        self.createdAt = .now
    }
}

/// Single-row settings entity.
@Model
final class AppSettings {
    var hasCompletedOnboarding: Bool
    var requireBiometrics: Bool
    var notificationsEnabled: Bool
    var cloudAIEnabled: Bool
    var analyticsEnabled: Bool
    var capturesUsed: Int
    var paywallSeenAt: Date?
    var lastInboxImportAt: Date?
    var sampleDataSeeded: Bool
    // Ingestion sources (added later — defaults keep lightweight migration happy).
    var screenshotWatchEnabled: Bool = false
    var lastScreenshotCheck: Date? = nil
    var priceTrackingEnabled: Bool = true
    var walletConnected: Bool = false
    var lastWalletSync: Date? = nil
    var lastBackgroundRefresh: Date? = nil

    init() {
        hasCompletedOnboarding = false
        requireBiometrics = false
        notificationsEnabled = false
        cloudAIEnabled = false
        analyticsEnabled = true
        capturesUsed = 0
        sampleDataSeeded = false
    }

    static let freeCaptureLimit = 3
}
