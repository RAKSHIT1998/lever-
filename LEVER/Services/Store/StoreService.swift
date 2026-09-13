import Foundation
import StoreKit
import Observation

/// Pure entitlement logic so it can be unit-tested without StoreKit.
enum EntitlementResolver {
    static func isPro(activeProductIDs: Set<String>) -> Bool {
        !activeProductIDs.isDisjoint(with: ProProduct.allCases.map(\.rawValue))
    }

    static func canCapture(isPro: Bool, capturesUsed: Int, freeLimit: Int = AppSettings.freeCaptureLimit) -> Bool {
        isPro || capturesUsed < freeLimit
    }

    static func remainingFreeCaptures(capturesUsed: Int, freeLimit: Int = AppSettings.freeCaptureLimit) -> Int {
        max(0, freeLimit - capturesUsed)
    }
}

/// StoreKit 2 subscription manager. Prices and names always come from the App Store — nothing is hardcoded.
@MainActor
@Observable
final class StoreService: ProEntitlementProviding {
    private(set) var products: [Product] = []
    private(set) var activeProductIDs: Set<String> = []
    private(set) var isLoading = false
    private(set) var lastError: String?
    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    /// UI-test override so paywall flows can be exercised without the App Store. Ignored outside `-ui-testing`.
    var debugOverridePro: Bool? = nil

    var isPro: Bool {
        if let debugOverridePro, ProcessInfo.processInfo.arguments.contains("-ui-testing") { return debugOverridePro }
        return EntitlementResolver.isPro(activeProductIDs: activeProductIDs)
    }

    init() {
        startObservingTransactions()
    }

    func stopObserving() {
        updatesTask?.cancel()
        updatesTask = nil
    }

    private func startObservingTransactions() {
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { break }
                if case .verified(let transaction) = result {
                    await transaction.finish()
                }
                await self.refreshEntitlements()
            }
        }
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let fetched = try await Product.products(for: ProProduct.allCases.map(\.rawValue))
            products = fetched.sorted { a, b in
                (ProProduct(rawValue: a.id)?.displayOrder ?? 9) < (ProProduct(rawValue: b.id)?.displayOrder ?? 9)
            }
            lastError = nil
        } catch {
            lastError = "Couldn't load products. Check your connection."
        }
        await refreshEntitlements()
    }

    func refreshEntitlements() async {
        var active: Set<String> = []
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result, transaction.revocationDate == nil {
                active.insert(transaction.productID)
            }
        }
        activeProductIDs = active
    }

    enum PurchaseOutcome { case success, pending, cancelled, failed(String) }

    func purchase(_ product: Product) async -> PurchaseOutcome {
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    await transaction.finish()
                    await refreshEntitlements()
                    return .success
                case .unverified:
                    return .failed("Purchase couldn't be verified.")
                }
            case .pending:
                return .pending
            case .userCancelled:
                return .cancelled
            @unknown default:
                return .failed("Unknown purchase result.")
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    func restore() async {
        try? await AppStore.sync()
        await refreshEntitlements()
    }

    func product(_ kind: ProProduct) -> Product? {
        products.first { $0.id == kind.rawValue }
    }

    /// Localised description of the renewal terms, read from StoreKit metadata.
    func renewalDescription(for product: Product) -> String {
        guard let sub = product.subscription else { return "One-time purchase. No renewal." }
        let unit: String
        switch sub.subscriptionPeriod.unit {
        case .day: unit = sub.subscriptionPeriod.value == 7 ? "week" : "\(sub.subscriptionPeriod.value)-day period"
        case .week: unit = "week"
        case .month: unit = sub.subscriptionPeriod.value == 1 ? "month" : "\(sub.subscriptionPeriod.value) months"
        case .year: unit = "year"
        @unknown default: unit = "period"
        }
        var text = "\(product.displayPrice) per \(unit). Renews automatically until cancelled."
        if let intro = sub.introductoryOffer, intro.paymentMode == .freeTrial {
            text = "\(intro.period.value) \(intro.period.unit == .week ? "week" : "day")\(intro.period.value > 1 ? "s" : "") free, then " + text.prefix(1).lowercased() + text.dropFirst()
        }
        return text
    }
}
