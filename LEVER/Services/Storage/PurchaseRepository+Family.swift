import Foundation
import SwiftData

extension PurchaseRepository {
    /// Marks a purchase as part of the household and produces the shareable bundle.
    func shareBundle(for purchase: Purchase) -> PurchaseTransfer {
        let profile = self.profile()
        if profile.householdID == nil { profile.householdID = UUID() }
        purchase.householdID = profile.householdID
        try? context.save()
        return PurchaseTransferCodec.export(purchase, sharedBy: profile.displayName ?? profile.householdName.map { "\($0) member" } ?? "Family", householdID: profile.householdID, files: files)
    }

    /// Imports a bundle. Same `id` updates the existing record instead of duplicating.
    @discardableResult
    func importTransfer(_ t: PurchaseTransfer) async throws -> Purchase {
        if let existing = purchase(id: t.id) {
            existing.title = t.title
            existing.amount = t.amount
            existing.sharedBy = t.sharedBy ?? existing.sharedBy
            existing.householdID = t.householdID ?? existing.householdID
            existing.updatedAt = .now
            try context.save()
            await refreshOpportunities(for: existing)
            publishSnapshot()
            return existing
        }
        let p = Purchase(id: t.id, title: t.title, merchantName: t.merchantName, merchantCategory: MerchantCategory(rawValue: t.merchantCategory) ?? .other, documentType: DocumentType(rawValue: t.documentType) ?? .unknown, amount: t.amount, currencyCode: t.currencyCode, purchaseDate: t.purchaseDate, tags: t.tags + ["family"])
        p.serviceDate = t.serviceDate
        p.orderNumber = t.orderNumber
        p.serialNumber = t.serialNumber
        p.policyNumber = t.policyNumber
        p.paymentMethod = t.paymentMethod
        p.productURL = t.productURL
        p.notes = t.notes
        p.householdID = t.householdID
        p.sharedBy = t.sharedBy
        p.merchant = upsertMerchant(named: t.merchantName, category: p.merchantCategory)
        context.insert(p)
        for name in t.items { let item = PurchaseItem(name: name); item.purchase = p; context.insert(item) }
        for d in t.documents {
            var fileName: String?
            if let payload = d.payload { fileName = try? files.write(payload, extension: d.kind == "pdf" ? "pdf" : "jpg") }
            let doc = StoredDocument(kind: StoredDocument.Kind(rawValue: d.kind) ?? .text, fileName: fileName, rawText: d.rawText)
            doc.purchase = p
            context.insert(doc)
        }
        for w in t.warranties {
            let model = Warranty(provider: w.provider, type: WarrantyType(rawValue: w.type) ?? .manufacturer, startDate: w.start, endDate: w.end, coverageSummary: w.coverage, source: w.source, confidence: Confidence(rawValue: w.confidence) ?? .medium)
            model.purchase = p
            context.insert(model)
        }
        if let s = t.subscription {
            let model = Subscription(merchantName: t.merchantName, price: s.price, currencyCode: s.currency, billingCycle: BillingCycle(rawValue: s.cycle) ?? .unknown, nextBillingDate: s.next, previousPrice: s.previous, status: SubscriptionStatus(rawValue: s.status) ?? .active, confidence: .medium, source: s.source)
            model.purchase = p
            context.insert(model)
        }
        if let r = t.returnWindow {
            let model = ReturnWindow(deadline: r.deadline, daysAllowed: r.days, policySource: r.source, confidence: Confidence(rawValue: r.confidence) ?? .medium)
            model.purchase = p
            context.insert(model)
        }
        let analysis = AIAnalysis(providerName: "Shared by \(t.sharedBy ?? "family")", documentType: p.documentType, confidence: .medium, fieldConfidences: [:], processedOnDevice: true)
        analysis.purchase = p
        context.insert(analysis)
        try context.save()
        analytics.track(.captureCompleted, properties: ["documentType": "familyTransfer"])
        await refreshOpportunities(for: p)
        await scheduleReminders(for: p)
        publishSnapshot()
        return p
    }

    func importTransfer(fileURL: URL) async throws -> Purchase {
        let accessed = fileURL.startAccessingSecurityScopedResource()
        defer { if accessed { fileURL.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: fileURL)
        return try await importTransfer(PurchaseTransferCodec.decode(data))
    }
}
