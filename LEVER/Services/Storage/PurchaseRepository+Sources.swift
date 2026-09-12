import Foundation
import SwiftData

/// Ingestion channels that don't start with a photo: statements, Wallet, tracked prices, repeat-charge detection.
extension PurchaseRepository {
    // MARK: - Statements & Wallet

    /// Creates (or updates) one subscription record per selected recurring charge. Individual transactions are
    /// not stored as purchases — the vault stays about things you own, not every coffee.
    @discardableResult
    func importRecurringCharges(_ candidates: [RecurringCandidate], source: String, statementText: String? = nil) async -> [Purchase] {
        var created: [Purchase] = []
        for candidate in candidates {
            let purchase: Purchase
            if let existing = allPurchases().first(where: { $0.subscription != nil && $0.merchantName.lowercased() == candidate.merchantName.lowercased() }) {
                purchase = existing
                if let sub = existing.subscription {
                    if sub.price != candidate.latestAmount { sub.previousPrice = sub.price; sub.price = candidate.latestAmount }
                    sub.nextBillingDate = candidate.nextDate ?? sub.nextBillingDate
                    sub.billingCycle = candidate.cycle
                    sub.source = source
                    sub.confidenceRaw = candidate.confidence.rawValue
                }
                purchase.purchaseDate = candidate.lastDate
            } else {
                purchase = Purchase(title: "\(candidate.merchantName) subscription", merchantName: candidate.merchantName, merchantCategory: candidate.category, documentType: .subscription, amount: candidate.latestAmount, currencyCode: candidate.currencyCode, purchaseDate: candidate.lastDate, tags: ["subscription", "recurring"])
                purchase.merchant = upsertMerchant(named: candidate.merchantName, category: candidate.category)
                context.insert(purchase)
                let sub = Subscription(merchantName: candidate.merchantName, price: candidate.latestAmount, currencyCode: candidate.currencyCode, billingCycle: candidate.cycle, nextBillingDate: candidate.nextDate, previousPrice: candidate.previousAmount, status: .active, confidence: candidate.confidence, source: source)
                sub.purchase = purchase
                context.insert(sub)
                let analysis = AIAnalysis(providerName: "LEVER recurring-charge detector", documentType: .subscription, confidence: candidate.confidence, fieldConfidences: ["subscription": candidate.confidence.weight], processedOnDevice: true)
                analysis.purchase = purchase
                context.insert(analysis)
                created.append(purchase)
            }
            if let statementText, purchase.documents.isEmpty {
                let relevant = statementText.components(separatedBy: .newlines).filter { $0.lowercased().contains(candidate.merchantName.lowercased().split(separator: " ").first.map(String.init) ?? "§") }
                let document = StoredDocument(kind: .text, rawText: relevant.isEmpty ? nil : relevant.joined(separator: "\n"))
                document.purchase = purchase
                context.insert(document)
            }
        }
        try? context.save()
        analytics.track(.captureCompleted, properties: ["documentType": "statement", "recurring": "\(candidates.count)"])
        for purchase in created { await refreshOpportunities(for: purchase); await scheduleReminders(for: purchase) }
        publishSnapshot()
        return created
    }

    /// Looks across everything already in the vault for merchants that keep charging on a schedule and marks them
    /// as subscriptions. Source is labelled so the user knows it was inferred.
    func detectRecurringChargesInVault() async {
        let purchases = allPurchases().filter { $0.subscription == nil && $0.purchaseDate != nil && $0.amount > 0 }
        let transactions = purchases.map {
            StatementTransaction(date: $0.purchaseDate ?? .now, description: $0.title, amount: $0.amount, currencyCode: $0.currencyCode, isDebit: true, merchantName: $0.merchantName, category: $0.merchantCategory)
        }
        let candidates = RecurringChargeDetector.detect(transactions)
        guard !candidates.isEmpty else { return }
        for candidate in candidates {
            guard let latest = purchases.filter({ $0.merchantName.lowercased() == candidate.merchantName.lowercased() }).max(by: { ($0.purchaseDate ?? .distantPast) < ($1.purchaseDate ?? .distantPast) }) else { continue }
            let sub = Subscription(merchantName: candidate.merchantName, price: candidate.latestAmount, currencyCode: candidate.currencyCode, billingCycle: candidate.cycle, nextBillingDate: candidate.nextDate, previousPrice: candidate.previousAmount, status: .active, confidence: .medium, source: "Detected from \(candidate.occurrences) repeat charges")
            sub.purchase = latest
            context.insert(sub)
            await refreshOpportunities(for: latest)
            await scheduleReminders(for: latest)
        }
        try? context.save()
    }

    // MARK: - Price tracking

    /// Re-checks every tracked product page. Only records a new observation when the price actually changed.
    func checkTrackedPrices(using monitor: PriceMonitoring) async -> Int {
        guard settings().priceTrackingEnabled else { return 0 }
        var updated = 0
        for purchase in allPurchases() {
            guard let urlString = purchase.productURL, let url = URL(string: urlString), monitor.supportsAutomaticTracking(for: url) else { continue }
            guard let price = try? await monitor.fetchCurrentPrice(for: url) else { continue }
            if let latest = purchase.latestPriceObservation, latest.observedPrice == price, latest.source != "Entered by you" { continue }
            await recordPrice(price, url: urlString, for: purchase, source: "Product page")
            updated += 1
        }
        return updated
    }

    // MARK: - Background refresh

    /// Everything LEVER does while the user isn't looking: expire/refresh opportunities, check prices, re-arm reminders.
    func performBackgroundRefresh(priceMonitor: PriceMonitoring) async {
        await refreshAllOpportunities()
        _ = await checkTrackedPrices(using: priceMonitor)
        await detectRecurringChargesInVault()
        settings().lastBackgroundRefresh = .now
        try? context.save()
        publishSnapshot()
    }
}
