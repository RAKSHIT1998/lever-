import Foundation
import UIKit

// MARK: - Intelligence

/// Everything LEVER "understands" goes through this seam so an on-device or cloud brain can be swapped in.
protocol IntelligenceProvider: Sendable {
    var name: String { get }
    var processesOnDevice: Bool { get }
    func extractDocument(from input: CaptureInput, currencyCode: String) async throws -> PurchaseDocument
    func detectOpportunities(in context: OpportunityContext) async throws -> [OpportunityDraft]
    func generateActionPlan(for opportunity: OpportunitySnapshot) async throws -> ActionPlanDraft
}

/// What the user captured. The raw payload never leaves the device unless a remote provider is explicitly enabled.
enum CaptureInput: Sendable {
    case image(Data)
    case pdf(Data)
    case text(String)
    case url(URL)

    var kindDescription: String {
        switch self {
        case .image: "image"
        case .pdf: "PDF"
        case .text: "text"
        case .url: "link"
        }
    }
}

enum IntelligenceError: LocalizedError {
    case unreadable
    case unsupportedInput
    case lowConfidence
    case remoteUnavailable

    var errorDescription: String? {
        switch self {
        case .unreadable: "LEVER couldn't confidently read this."
        case .unsupportedInput: "LEVER can't process this kind of file yet."
        case .lowConfidence: "LEVER found text but couldn't identify a purchase."
        case .remoteUnavailable: "Cloud intelligence isn't available. On-device processing was used instead."
        }
    }
}

// MARK: - OCR

protocol TextRecognizing: Sendable {
    func recognizeText(in imageData: Data) async throws -> RecognizedText
    func extractText(fromPDF data: Data) async throws -> RecognizedText
}

struct RecognizedText: Sendable, Equatable {
    var lines: [String]
    /// Mean Vision confidence 0...1 across lines.
    var averageConfidence: Double
    var pageCount: Int = 1

    var joined: String { lines.joined(separator: "\n") }
    var isEmpty: Bool { lines.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty } }
}

// MARK: - Notifications

protocol NotificationScheduling: Sendable {
    func requestAuthorization() async -> Bool
    func authorizationGranted() async -> Bool
    func schedule(identifier: String, title: String, body: String, at date: Date) async
    func cancel(identifiers: [String]) async
    func cancelAll() async
    func pendingIdentifiers() async -> [String]
}

// MARK: - Policies

/// Return-policy knowledge. Never guesses: returns nil when the merchant is unknown.
protocol ReturnPolicyProviding: Sendable {
    func policy(forMerchant merchant: String, category: MerchantCategory) -> ReturnPolicy?
}

struct ReturnPolicy: Equatable, Sendable {
    var merchant: String
    var days: Int
    var source: String
    var confidence: Confidence
    var note: String?
}

// MARK: - Price monitoring

protocol PriceMonitoring: Sendable {
    /// MVP: user-provided observations only. Automated sources plug in here later.
    func supportsAutomaticTracking(for url: URL) -> Bool
    func fetchCurrentPrice(for url: URL) async throws -> Decimal?
}

// MARK: - Analytics

/// Product analytics without document content. Only event names and coarse, non-sensitive properties.
protocol AnalyticsTracking: Sendable {
    func track(_ event: AnalyticsEvent, properties: [String: String])
}

extension AnalyticsTracking {
    func track(_ event: AnalyticsEvent) { track(event, properties: [:]) }
}

enum AnalyticsEvent: String {
    case appOpen = "app_open"
    case captureStarted = "capture_started"
    case captureCompleted = "capture_completed"
    case opportunityFound = "opportunity_found"
    case opportunityOpened = "opportunity_opened"
    case actionStarted = "action_started"
    case actionCompleted = "action_completed"
    case savingsConfirmed = "savings_confirmed"
    case paywallViewed = "paywall_viewed"
    case trialStarted = "trial_started"
    case subscriptionStarted = "subscription_started"
    case subscriptionCancelled = "subscription_cancelled"
}

// MARK: - Security

protocol BiometricAuthenticating: Sendable {
    var isAvailable: Bool { get }
    var biometryName: String { get }
    func authenticate(reason: String) async -> Bool
}

// MARK: - Store

enum ProProduct: String, CaseIterable {
    case monthly = "lever_pro_monthly"
    case yearly = "lever_pro_yearly"
    case lifetime = "lever_pro_lifetime"

    var displayOrder: Int {
        switch self {
        case .yearly: 0
        case .monthly: 1
        case .lifetime: 2
        }
    }
}

@MainActor
protocol ProEntitlementProviding: AnyObject {
    var isPro: Bool { get }
}
