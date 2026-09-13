import Foundation
import SwiftData
import WidgetKit

/// Orchestrates the purchase graph: persisting extractions, running the opportunity engine, tracking savings,
/// scheduling reminders and publishing the widget snapshot. All on the main actor with the app's ModelContext.
@MainActor
final class PurchaseRepository {
    let context: ModelContext
    let intelligence: IntelligenceProvider
    let policies: ReturnPolicyProviding
    let notifications: NotificationScheduling
    let files: DocumentFileStore
    let analytics: AnalyticsTracking
    let liveActivities = LiveActivityManager()
    let spotlight = SpotlightIndexer()

    init(context: ModelContext, intelligence: IntelligenceProvider, policies: ReturnPolicyProviding, notifications: NotificationScheduling, files: DocumentFileStore, analytics: AnalyticsTracking) {
        self.context = context
        self.intelligence = intelligence
        self.policies = policies
        self.notifications = notifications
        self.files = files
        self.analytics = analytics
    }

    // MARK: - Settings & profile

    private var cachedSettings: AppSettings?
    private var cachedProfile: UserProfile?

    /// Single-row settings. Cached so every reader observes the same instance.
    func settings() -> AppSettings {
        if let cachedSettings, !cachedSettings.isDeleted { return cachedSettings }
        let rows = (try? context.fetch(FetchDescriptor<AppSettings>())) ?? []
        let row: AppSettings
        if let first = rows.first {
            row = first
            rows.dropFirst().forEach { context.delete($0) }
        } else {
            row = AppSettings()
            context.insert(row)
            try? context.save()
        }
        cachedSettings = row
        return row
    }

    func profile() -> UserProfile {
        if let cachedProfile, !cachedProfile.isDeleted { return cachedProfile }
        let rows = (try? context.fetch(FetchDescriptor<UserProfile>())) ?? []
        let row: UserProfile
        if let first = rows.first {
            row = first
        } else {
            row = UserProfile(currencyCode: Money.defaultCurrencyCode)
            context.insert(row)
            try? context.save()
        }
        cachedProfile = row
        return row
    }

    // MARK: - Fetching

    func allPurchases() -> [Purchase] {
        let descriptor = FetchDescriptor<Purchase>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        return (try? context.fetch(descriptor)) ?? []
    }

    func purchase(id: UUID) -> Purchase? {
        var descriptor = FetchDescriptor<Purchase>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    func openOpportunities() -> [Opportunity] {
        let open = OpportunityStatus.open.rawValue
        let inProgress = OpportunityStatus.inProgress.rawValue
        let descriptor = FetchDescriptor<Opportunity>(predicate: #Predicate { $0.statusRaw == open || $0.statusRaw == inProgress })
        let items = ((try? context.fetch(descriptor)) ?? []).filter { !$0.isSnoozed }
        return OpportunityRanker.rank(items) { $0.priorityScore }
    }

    func opportunity(id: UUID) -> Opportunity? {
        var descriptor = FetchDescriptor<Opportunity>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    func savingsEvents() -> [SavingsEvent] {
        let descriptor = FetchDescriptor<SavingsEvent>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Persisting a capture

    /// Persists a reviewed document as a full purchase graph, then runs detection and reminders.
    @discardableResult
    func save(document doc: PurchaseDocument, files captured: [CaptureFile]) async throws -> Purchase {
        let merchantName = doc.merchant ?? "Unknown merchant"
        let purchase = Purchase(
            title: doc.displayTitle,
            merchantName: merchantName,
            merchantCategory: doc.merchantCategory,
            documentType: doc.documentType,
            amount: doc.amount ?? 0,
            currencyCode: doc.currencyCode,
            purchaseDate: doc.purchaseDate,
            tags: doc.tags
        )
        purchase.orderNumber = doc.orderNumber
        purchase.invoiceNumber = doc.invoiceNumber
        purchase.referenceNumber = doc.referenceNumber
        purchase.serialNumber = doc.serialNumber
        purchase.policyNumber = doc.policyNumber
        purchase.paymentMethod = doc.paymentMethod
        purchase.productURL = doc.productURL
        purchase.serviceDate = doc.serviceDate
        purchase.bookingDate = doc.bookingDate
        purchase.merchant = upsertMerchant(named: merchantName, category: doc.merchantCategory)
        context.insert(purchase)

        for item in doc.items {
            let model = PurchaseItem(name: item.name, quantity: item.quantity, unitPrice: item.unitPrice)
            model.purchase = purchase
            context.insert(model)
        }

        // Originals + text.
        var storedText = false
        for file in captured {
            if let name = try? files.write(file.data, extension: file.fileExtension) {
                let document = StoredDocument(kind: file.kind, fileName: name, rawText: storedText ? nil : doc.rawText)
                document.purchase = purchase
                context.insert(document)
                storedText = true
            }
        }
        if !storedText {
            let document = StoredDocument(kind: .text, rawText: doc.rawText)
            document.purchase = purchase
            context.insert(document)
        }

        // Subscription
        if let info = doc.subscription, let price = doc.amount {
            let sub = Subscription(
                merchantName: merchantName,
                price: price,
                currencyCode: doc.currencyCode,
                billingCycle: info.billingCycle,
                nextBillingDate: info.nextBillingDate ?? doc.renewalDate ?? doc.purchaseDate.flatMap { SubscriptionMath.nextBillingDate(after: $0, cycle: info.billingCycle) },
                previousPrice: info.previousPrice,
                confidence: doc.confidence(for: "subscription"),
                source: "Document"
            )
            sub.purchase = purchase
            context.insert(sub)
        }

        // Warranties
        for info in doc.warranties {
            let warranty = Warranty(provider: info.provider, type: info.type, startDate: doc.purchaseDate, endDate: info.endDate, coverageSummary: info.months.map { "\($0) months" }, source: info.source, confidence: info.confidence)
            warranty.purchase = purchase
            context.insert(warranty)
        }

        // Return window: stated deadline beats policy knowledge; never guess for unknown merchants.
        if let window = ReturnWindowCalculator.calculate(statedDeadline: doc.returnDeadline, purchaseDate: doc.purchaseDate, merchant: merchantName, category: doc.merchantCategory, documentType: doc.documentType, policies: policies) {
            window.purchase = purchase
            context.insert(window)
        }

        let analysis = AIAnalysis(providerName: doc.providerName, documentType: doc.documentType, confidence: doc.overallConfidence, fieldConfidences: doc.fieldConfidences, processedOnDevice: doc.processedOnDevice)
        analysis.purchase = purchase
        context.insert(analysis)

        try context.save()
        analytics.track(.captureCompleted, properties: ["documentType": doc.documentType.rawValue, "confidence": doc.overallConfidence.rawValue])

        await refreshOpportunities(for: purchase)
        await scheduleReminders(for: purchase)
        publishSnapshot()
        return purchase
    }

    func upsertMerchant(named name: String, category: MerchantCategory) -> Merchant {
        var descriptor = FetchDescriptor<Merchant>(predicate: #Predicate { $0.name == name })
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor).first { return existing }
        let directory = MerchantDirectory()
        let entry = directory.entry(named: name)
        let merchant = Merchant(name: name, category: entry?.category ?? category, domain: entry?.domain, typicalReturnDays: entry?.typicalReturnDays, policySource: entry?.policyNote)
        context.insert(merchant)
        return merchant
    }

    // MARK: - Opportunities

    func refreshOpportunities(for purchase: Purchase) async {
        let others = allPurchases().filter { $0.id != purchase.id }.map(PurchaseSnapshot.init)
        let ctx = OpportunityContext(purchase: PurchaseSnapshot(purchase), otherPurchases: others)
        let drafts = (try? await intelligence.detectOpportunities(in: ctx)) ?? []
        var kept: Set<String> = []
        for draft in drafts {
            kept.insert(draft.dedupeKey)
            if let existing = purchase.opportunities.first(where: { $0.dedupeKey == draft.dedupeKey }) {
                guard existing.status == .open || existing.status == .inProgress || existing.status == .expired else { continue }
                existing.title = draft.title
                existing.detail = draft.detail
                existing.estimatedSavings = draft.estimatedSavings
                existing.confidence = draft.confidence
                existing.urgency = draft.urgency
                existing.deadline = draft.deadline
                existing.recommendedAction = draft.recommendedAction
                existing.lastCheckedAt = .now
                if existing.status == .expired { existing.status = .open }
                for e in existing.evidence { context.delete(e) }
                for e in draft.evidence {
                    let model = Evidence(kind: e.kind, statement: e.statement, source: e.source)
                    model.opportunity = existing
                    context.insert(model)
                }
            } else {
                let model = Opportunity(type: draft.type, title: draft.title, detail: draft.detail, estimatedSavings: draft.estimatedSavings, currencyCode: draft.currencyCode, confidence: draft.confidence, urgency: draft.urgency, deadline: draft.deadline, merchantName: draft.merchantName, recommendedAction: draft.recommendedAction, dedupeKey: draft.dedupeKey)
                model.purchase = purchase
                context.insert(model)
                for e in draft.evidence {
                    let evidence = Evidence(kind: e.kind, statement: e.statement, source: e.source)
                    evidence.opportunity = model
                    context.insert(evidence)
                }
                analytics.track(.opportunityFound, properties: ["type": draft.type.rawValue, "confidence": draft.confidence.rawValue])
            }
        }
        // Open opportunities the engine no longer produces (deadline passed etc.) expire.
        for existing in purchase.opportunities where !kept.contains(existing.dedupeKey) && existing.status == .open {
            existing.status = .expired
        }
        purchase.updatedAt = .now
        try? context.save()
    }

    func refreshAllOpportunities() async {
        for purchase in allPurchases() {
            await refreshOpportunities(for: purchase)
        }
        publishSnapshot()
        liveActivities.sync(with: openOpportunities())
        await scheduleWeeklyDigest()
    }

    /// One Monday-morning digest, only when the fortnight ahead holds real deadlines.
    func scheduleWeeklyDigest() async {
        await notifications.cancel(identifiers: [DigestPlanner.identifier])
        guard settings().notificationsEnabled else { return }
        let lite = openOpportunities().compactMap(OpportunitySnapshotLite.init)
        guard let planned = DigestPlanner.plan(opportunities: lite, currencyCode: profile().currencyCode) else { return }
        await notifications.schedule(identifier: planned.identifier, title: planned.title, body: planned.body, at: planned.fireDate, userInfo: planned.userInfo)
    }

    func ensureActionPlan(for opportunity: Opportunity) async -> ActionPlan? {
        if let plan = opportunity.actionPlan { return plan }
        guard let draft = try? await intelligence.generateActionPlan(for: OpportunitySnapshot(opportunity)) else { return nil }
        let plan = ActionPlan(summary: draft.summary, whyItMatters: draft.whyItMatters, estimatedSavings: draft.estimatedSavings, steps: draft.steps, messageDraft: draft.messageDraft, callScript: draft.callScript, deadline: draft.deadline, confidence: draft.confidence, generatedBy: draft.generatedBy)
        plan.opportunity = opportunity
        context.insert(plan)
        try? context.save()
        return plan
    }

    func snooze(_ opportunity: Opportunity, days: Int) {
        var until = DateMath.adding(days: days, to: .now) ?? .now
        // Never hide something past the moment it matters: wake at least a day before the deadline.
        if let deadline = opportunity.deadline, let dayBefore = DateMath.adding(days: -1, to: deadline), dayBefore < until { until = max(dayBefore, .now) }
        opportunity.snoozedUntil = until
        try? context.save()
        publishSnapshot()
        liveActivities.sync(with: openOpportunities())
    }

    func update(_ opportunity: Opportunity, status: OpportunityStatus) {
        opportunity.status = status
        if status == .resolved || status == .dismissed { opportunity.resolvedAt = .now }
        try? context.save()
        publishSnapshot()
        liveActivities.sync(with: openOpportunities())
    }

    // MARK: - Savings

    /// Creates a pending saving. Only confirmation by the user moves it into the totals.
    @discardableResult
    func proposeSaving(for opportunity: Opportunity, amount: Decimal, kind: SavingsKind) -> SavingsEvent {
        if let existing = opportunity.savingsEvents.first(where: { $0.status == .pending }) {
            existing.amount = amount
            existing.kind = kind
            try? context.save()
            return existing
        }
        let event = SavingsEvent(kind: kind, amount: amount, currencyCode: opportunity.currencyCode, title: opportunity.title)
        event.opportunity = opportunity
        event.purchase = opportunity.purchase
        context.insert(event)
        try? context.save()
        return event
    }

    func confirmSaving(_ event: SavingsEvent, amount: Decimal? = nil) {
        event.confirm(amount: amount)
        if let opportunity = event.opportunity, opportunity.status != .resolved {
            opportunity.status = .resolved
            opportunity.resolvedAt = .now
        }
        try? context.save()
        analytics.track(.savingsConfirmed, properties: ["kind": event.kind.rawValue])
        publishSnapshot()
    }

    func rejectSaving(_ event: SavingsEvent) {
        event.status = .rejected
        try? context.save()
        publishSnapshot()
    }

    var totals: SavingsTotals { SavingsTotals(events: savingsEvents(), currencyCode: profile().currencyCode) }

    // MARK: - Editing

    struct PurchaseEdits {
        var title: String
        var merchantName: String
        var amount: Decimal
        var purchaseDate: Date?
        var returnDeadline: Date?
        var orderNumber: String?
        var serialNumber: String?
        var notes: String?
    }

    /// Applies user corrections and re-runs everything that depends on them. User input is trusted (high confidence).
    func apply(_ edits: PurchaseEdits, to purchase: Purchase) async {
        purchase.title = edits.title
        if purchase.merchantName != edits.merchantName {
            purchase.merchantName = edits.merchantName
            purchase.merchant = upsertMerchant(named: edits.merchantName, category: purchase.merchantCategory)
        }
        purchase.amount = edits.amount
        purchase.purchaseDate = edits.purchaseDate
        purchase.orderNumber = edits.orderNumber
        purchase.serialNumber = edits.serialNumber
        purchase.notes = edits.notes
        if let deadline = edits.returnDeadline {
            if let window = purchase.returnWindow {
                window.deadline = deadline
                window.policySource = "Entered by you"
                window.confidenceRaw = Confidence.high.rawValue
                window.daysAllowed = edits.purchaseDate.map { DateMath.days(from: $0, to: deadline) }
            } else {
                let window = ReturnWindow(deadline: deadline, daysAllowed: edits.purchaseDate.map { DateMath.days(from: $0, to: deadline) }, policySource: "Entered by you", policyDate: .now, confidence: .high)
                window.purchase = purchase
                context.insert(window)
            }
        } else if let window = purchase.returnWindow {
            context.delete(window)
        }
        purchase.updatedAt = .now
        try? context.save()
        await refreshOpportunities(for: purchase)
        await scheduleReminders(for: purchase)
        publishSnapshot()
    }

    // MARK: - Price observations

    func recordPrice(_ price: Decimal, url: String?, for purchase: Purchase, source: String = "Entered by you") async {
        let observation = PriceObservation(productURL: url, observedPrice: price, currencyCode: purchase.currencyCode, source: source)
        observation.purchase = purchase
        if let url, purchase.productURL == nil { purchase.productURL = url }
        context.insert(observation)
        try? context.save()
        await refreshOpportunities(for: purchase)
        publishSnapshot()
    }

    // MARK: - Reminders

    func scheduleReminders(for purchase: Purchase) async {
        guard settings().notificationsEnabled else { return }
        let pending = await notifications.pendingIdentifiers()
        let prefixes = DeadlineNotificationPlanner.prefixes(for: purchase.id)
        await notifications.cancel(identifiers: pending.filter { id in prefixes.contains { id.hasPrefix($0) } })
        for planned in DeadlineNotificationPlanner.plan(for: PurchaseSnapshot(purchase)) {
            await notifications.schedule(identifier: planned.identifier, title: planned.title, body: planned.body, at: planned.fireDate, userInfo: planned.userInfo)
        }
    }

    func rescheduleAllReminders() async {
        await notifications.cancelAll()
        for purchase in allPurchases() { await scheduleReminders(for: purchase) }
        await scheduleWeeklyDigest()
    }

    // MARK: - Deletion & export

    func delete(_ purchase: Purchase) async {
        for document in purchase.documents {
            if let name = document.fileName { files.delete(name) }
        }
        let pending = await notifications.pendingIdentifiers()
        let prefixes = DeadlineNotificationPlanner.prefixes(for: purchase.id)
        await notifications.cancel(identifiers: pending.filter { id in prefixes.contains { id.hasPrefix($0) } })
        spotlight.remove(purchase.id)
        context.delete(purchase)
        try? context.save()
        publishSnapshot()
    }

    /// Wipes every record, file, notification and shared snapshot. Settings are reset too.
    func deleteEverything() async {
        for purchase in allPurchases() { context.delete(purchase) }
        for event in savingsEvents() { context.delete(event) }
        for merchant in (try? context.fetch(FetchDescriptor<Merchant>())) ?? [] { context.delete(merchant) }
        for rule in (try? context.fetch(FetchDescriptor<NotificationRule>())) ?? [] { context.delete(rule) }
        for profile in (try? context.fetch(FetchDescriptor<UserProfile>())) ?? [] { context.delete(profile) }
        for s in (try? context.fetch(FetchDescriptor<AppSettings>())) ?? [] { context.delete(s) }
        cachedSettings = nil
        cachedProfile = nil
        try? context.save()
        files.deleteAll()
        spotlight.removeAll()
        InboxStore().removeAll()
        WidgetSnapshot.clear()
        KeychainStore().removeAll()
        await notifications.cancelAll()
        WidgetCenter.shared.reloadAllTimelines()
    }

    struct ExportPayload: Codable {
        struct PurchaseExport: Codable {
            var title: String
            var merchant: String
            var amount: Decimal
            var currency: String
            var purchaseDate: Date?
            var documentType: String
            var orderNumber: String?
            var returnDeadline: Date?
            var warranties: [String]
            var subscription: String?
            var openOpportunities: [String]
        }
        struct SavingExport: Codable {
            var title: String
            var amount: Decimal
            var currency: String
            var kind: String
            var status: String
            var date: Date
        }
        var exportedAt: Date
        var purchases: [PurchaseExport]
        var savings: [SavingExport]
    }

    func exportJSON() -> Data? {
        let payload = ExportPayload(
            exportedAt: .now,
            purchases: allPurchases().map { p in
                ExportPayload.PurchaseExport(
                    title: p.title, merchant: p.merchantName, amount: p.amount, currency: p.currencyCode, purchaseDate: p.purchaseDate,
                    documentType: p.documentType.rawValue, orderNumber: p.orderNumber, returnDeadline: p.returnWindow?.deadline,
                    warranties: p.warranties.map { "\($0.provider) \($0.type.displayName)\($0.endDate.map { " until \($0.leverShort)" } ?? "")" },
                    subscription: p.subscription.map { Money.format($0.price, code: $0.currencyCode) + $0.billingCycle.shortSuffix },
                    openOpportunities: p.openOpportunities.map(\.title)
                )
            },
            savings: savingsEvents().map { ExportPayload.SavingExport(title: $0.title, amount: $0.amount, currency: $0.currencyCode, kind: $0.kind.rawValue, status: $0.status.rawValue, date: $0.date) }
        )
        let encoder = JSONEncoder.lever
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(payload)
    }

    // MARK: - Widget snapshot

    func publishSnapshot() {
        spotlight.index(allPurchases())
        let currency = profile().currencyCode
        let open = openOpportunities().filter { $0.currencyCode == currency }
        let now = Date.now
        let weekAhead = DateMath.adding(days: 7, to: now) ?? now
        let purchases = allPurchases()
        let totals = self.totals

        let deadlines = open.compactMap { o -> WidgetSnapshot.Deadline? in
            guard let d = o.deadline, d >= now, d <= weekAhead else { return nil }
            return .init(id: o.id, title: o.title, date: d, amount: o.estimatedSavings)
        }
        let warranties = purchases.flatMap { p in p.warranties.compactMap { w -> WidgetSnapshot.Deadline? in
            guard let end = w.endDate, end >= now, DateMath.days(from: now, to: end) <= 60 else { return nil }
            return .init(id: w.id, title: "\(p.title) · \(w.provider)", date: end, amount: p.amount)
        } }.sorted { $0.date < $1.date }
        let renewals = purchases.compactMap { p -> WidgetSnapshot.Deadline? in
            guard let s = p.subscription, s.status != .cancelled, let next = s.nextBillingDate, next >= now, DateMath.days(from: now, to: next) <= 30 else { return nil }
            return .init(id: s.id, title: p.merchantName, date: next, amount: s.price)
        }.sorted { $0.date < $1.date }

        let snapshot = WidgetSnapshot(
            currencyCode: currency,
            potentialSavings: open.filter(\.countsAsPotentialSaving).compactMap(\.estimatedSavings).reduce(0, +),
            openOpportunities: open.count,
            moneyAtRisk: deadlines.compactMap(\.amount).reduce(0, +),
            deadlinesThisWeek: deadlines,
            savedThisMonth: totals.thisMonth,
            lifetimeSaved: totals.lifetime,
            expiringWarranties: warranties,
            upcomingRenewals: renewals,
            updatedAt: now
        )
        snapshot.save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}

/// Aggregates over confirmed savings only.
struct SavingsTotals: Equatable {
    var lifetime: Decimal = 0
    var thisMonth: Decimal = 0
    var byKind: [SavingsKind: Decimal] = [:]
    var pending: Decimal = 0
    var currencyCode: String

    init(events: [SavingsEvent], currencyCode: String, now: Date = .now) {
        self.currencyCode = currencyCode
        let monthStart = DateMath.startOfMonth(for: now)
        for event in events {
            switch event.status {
            case .confirmed:
                lifetime += event.amount
                byKind[event.kind, default: 0] += event.amount
                if (event.confirmedAt ?? event.date) >= monthStart { thisMonth += event.amount }
            case .pending:
                pending += event.amount
            case .rejected:
                continue
            }
        }
    }

    init(currencyCode: String) {
        self.currencyCode = currencyCode
    }
}

/// Decides a return deadline from a stated date or a known policy. Unknown merchant → no deadline, no guess.
enum ReturnWindowCalculator {
    static func calculate(statedDeadline: Date?, purchaseDate: Date?, merchant: String, category: MerchantCategory, documentType: DocumentType, policies: ReturnPolicyProviding) -> ReturnWindow? {
        if let statedDeadline {
            return ReturnWindow(deadline: statedDeadline, daysAllowed: purchaseDate.map { DateMath.days(from: $0, to: statedDeadline) }, policySource: "Stated in document", policyDate: .now, confidence: .high)
        }
        let returnable: Set<DocumentType> = [.receipt, .invoice, .orderConfirmation, .unknown]
        guard returnable.contains(documentType), let purchaseDate, let policy = policies.policy(forMerchant: merchant, category: category) else { return nil }
        guard let deadline = DateMath.adding(days: policy.days, to: purchaseDate) else { return nil }
        return ReturnWindow(deadline: deadline, daysAllowed: policy.days, policySource: policy.source, policyDate: .now, confidence: policy.confidence)
    }
}
