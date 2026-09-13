import Foundation

/// A suggestion derived from patterns across the vault — softer than an opportunity, always explainable.
struct Insight: Identifiable, Equatable {
    enum Kind: String { case subscriptions, coverage, tracking, cashflow, hygiene }
    enum Action: Equatable {
        case none
        case openPurchase(UUID)
        case openTool(Tool)
        case openSources
    }

    var id: String
    var kind: Kind
    var symbol: String
    var title: String
    var detail: String
    var actionTitle: String?
    var action: Action
    var weight: Double
}

enum Tool: String, CaseIterable, Identifiable {
    case scanAndPay, spending, subscriptionAudit, cashForecast, costPerUse, returnDecision, askLever

    var id: String { rawValue }

    var title: String {
        switch self {
        case .scanAndPay: "Scan & Pay"
        case .spending: "Spending"
        case .subscriptionAudit: "Subscription audit"
        case .cashForecast: "Next 30 days"
        case .costPerUse: "Cost per use"
        case .returnDecision: "Should I return it?"
        case .askLever: "Ask LEVER"
        }
    }

    var subtitle: String {
        switch self {
        case .scanAndPay: "Scan a shop's QR, pay with your own app, and LEVER logs the spend."
        case .spending: "Where the money went this month — categories, merchants, UPI vs recurring."
        case .subscriptionAudit: "Everything you pay for on repeat, what it adds up to, what to cut."
        case .cashForecast: "Renewals and deadlines landing in the next month."
        case .costPerUse: "Is that subscription worth it? Divide price by how often you use it."
        case .returnDecision: "A 30-second check while the return window is open."
        case .askLever: "Ask about warranties, renewals, returns, spending — answered from your vault."
        }
    }

    var symbol: String {
        switch self {
        case .scanAndPay: "qrcode.viewfinder"
        case .spending: "chart.bar.xaxis"
        case .subscriptionAudit: "list.bullet.rectangle.portrait"
        case .cashForecast: "calendar.badge.clock"
        case .costPerUse: "divide.circle"
        case .returnDecision: "arrow.uturn.backward.circle"
        case .askLever: "text.bubble"
        }
    }
}

/// Snapshot-based so it's pure and testable.
struct VaultSummary: Sendable {
    struct Sub: Sendable { var purchaseID: UUID; var merchant: String; var category: MerchantCategory; var price: Decimal; var cycle: BillingCycle; var next: Date?; var previous: Decimal?; var status: SubscriptionStatus }
    struct Item: Sendable { var id: UUID; var title: String; var merchant: String; var category: MerchantCategory; var amount: Decimal; var date: Date?; var hasWarranty: Bool; var hasReturnWindow: Bool; var hasProductURL: Bool; var documentType: DocumentType }
    var currencyCode: String
    var subscriptions: [Sub]
    var items: [Item]
    var now: Date = .now
}

enum InsightEngine {
    static func generate(_ v: VaultSummary) -> [Insight] {
        var out: [Insight] = []
        let code = v.currencyCode
        let active = v.subscriptions.filter { $0.status != .cancelled && $0.cycle != .unknown }

        // 1. Recurring total
        let monthly = active.compactMap { s -> Decimal? in SubscriptionMath.annualCost(price: s.price, cycle: s.cycle).map { $0 / 12 } }.reduce(0, +)
        if active.count >= 2, monthly > 0 {
            out.append(Insight(id: "recurring-total", kind: .subscriptions, symbol: "arrow.triangle.2.circlepath",
                title: "\(Money.format(monthly.rounded(scale: 0), code: code)) a month on \(active.count) subscriptions",
                detail: "That's \(Money.format((monthly * 12).rounded(scale: 0), code: code, compact: true)) a year. Worth a five-minute audit twice a year.",
                actionTitle: "Audit", action: .openTool(.subscriptionAudit), weight: 0.7))
        }

        // 2. Marked unused
        let unused = active.filter { $0.status == .markedUnused }
        if !unused.isEmpty {
            let waste = unused.compactMap { SubscriptionMath.annualCost(price: $0.price, cycle: $0.cycle) }.reduce(0, +)
            out.append(Insight(id: "unused", kind: .subscriptions, symbol: "hand.raised.fill",
                title: "\(unused.count) subscription\(unused.count == 1 ? "" : "s") you said you don't use",
                detail: "\(unused.map(\.merchant).joined(separator: ", ")) — \(Money.format(waste, code: code)) a year if left running.",
                actionTitle: "Cancel", action: .openPurchase(unused[0].purchaseID), weight: 1.0))
        }

        // 3. Overlapping streaming
        let streaming = active.filter { $0.category == .streaming }
        if streaming.count >= 3 {
            let cost = streaming.compactMap { SubscriptionMath.annualCost(price: $0.price, cycle: $0.cycle) }.reduce(0, +)
            out.append(Insight(id: "streaming-overlap", kind: .subscriptions, symbol: "play.rectangle.on.rectangle",
                title: "\(streaming.count) streaming services at once",
                detail: "\(streaming.map(\.merchant).joined(separator: ", ")) cost \(Money.format(cost, code: code, compact: true)) a year. Rotating one at a time is a common way to halve that.",
                actionTitle: "Review", action: .openTool(.subscriptionAudit), weight: 0.8))
        }

        // 4. Price creep
        let crept = active.filter { ($0.previous ?? $0.price) < $0.price }
        if !crept.isEmpty {
            let extra = crept.compactMap { SubscriptionMath.annualIncrease(current: $0.price, previous: $0.previous ?? $0.price, cycle: $0.cycle) }.reduce(0, +)
            out.append(Insight(id: "creep", kind: .subscriptions, symbol: "chart.line.uptrend.xyaxis",
                title: "Prices crept up on \(crept.count) plan\(crept.count == 1 ? "" : "s")",
                detail: "\(Money.format(extra, code: code)) more per year than you originally signed up for. Each one is a negotiation.",
                actionTitle: "See which", action: .openTool(.subscriptionAudit), weight: 0.85))
        }

        // 5. Expensive electronics with no coverage recorded
        let uncovered = v.items.filter { $0.category == .electronics && $0.amount >= 20_000 && !$0.hasWarranty && $0.documentType != .subscription }
        if let first = uncovered.first {
            out.append(Insight(id: "no-warranty", kind: .coverage, symbol: "shield.slash",
                title: "\(uncovered.count == 1 ? first.title : "\(uncovered.count) devices") with no warranty on record",
                detail: "Most electronics carry at least 12 months. Add the coverage so LEVER can warn you before it lapses.",
                actionTitle: "Add coverage", action: .openPurchase(first.id), weight: 0.75))
        }

        // 6. Recent electronics not price-tracked
        let recentUntracked = v.items.filter { $0.category == .electronics && $0.amount >= 10_000 && !$0.hasProductURL && ($0.date.map { DateMath.days(from: $0, to: v.now) <= 30 } ?? false) }
        if let first = recentUntracked.first {
            out.append(Insight(id: "track-price", kind: .tracking, symbol: "tag",
                title: "Track the price of \(first.title)",
                detail: "Bought \(first.date.map { DateMath.relativePhrase(to: $0, from: v.now) } ?? "recently"). If it drops while the return window is open, many sellers will match — but only if you notice.",
                actionTitle: "Add link", action: .openPurchase(first.id), weight: 0.6))
        }

        // 7. Unknown return window on recent purchases
        let unknownReturn = v.items.filter { !$0.hasReturnWindow && [.receipt, .orderConfirmation, .invoice].contains($0.documentType) && $0.amount >= 2_000 && ($0.date.map { DateMath.days(from: $0, to: v.now) <= 10 } ?? false) }
        if let first = unknownReturn.first {
            out.append(Insight(id: "return-unknown", kind: .hygiene, symbol: "questionmark.circle",
                title: "Return deadline unknown for \(first.title)",
                detail: "LEVER doesn't know \(first.merchant)'s policy. Check the receipt or site and set the date — takes ten seconds.",
                actionTitle: "Set deadline", action: .openPurchase(first.id), weight: 0.65))
        }

        // 8. Next-30-day outflow
        let horizon = DateMath.adding(days: 30, to: v.now) ?? v.now
        let due = active.filter { ($0.next ?? .distantPast) >= v.now && ($0.next ?? .distantFuture) <= horizon }
        if due.count >= 2 {
            let total = due.map(\.price).reduce(0, +)
            out.append(Insight(id: "cash-30", kind: .cashflow, symbol: "calendar.badge.clock",
                title: "\(Money.format(total, code: code)) in renewals over the next 30 days",
                detail: "\(due.count) charges are coming. See the dates and decide before they land.",
                actionTitle: "See dates", action: .openTool(.cashForecast), weight: 0.7))
        }

        // 9. Nothing beyond manual capture
        if v.items.count >= 3, v.subscriptions.isEmpty {
            out.append(Insight(id: "no-subs", kind: .hygiene, symbol: "building.columns",
                title: "No subscriptions found yet",
                detail: "Almost everyone has a few. Import a bank statement and LEVER finds the ones charging on repeat.",
                actionTitle: "Import", action: .openSources, weight: 0.55))
        }

        return out.sorted { $0.weight > $1.weight }
    }
}

extension VaultSummary {
    @MainActor
    init(purchases: [Purchase], currencyCode: String, now: Date = .now) {
        self.currencyCode = currencyCode
        self.now = now
        subscriptions = purchases.compactMap { p in
            guard let s = p.subscription, p.currencyCode == currencyCode else { return nil }
            return Sub(purchaseID: p.id, merchant: p.merchantName, category: p.merchantCategory, price: s.price, cycle: s.billingCycle, next: s.nextBillingDate, previous: s.previousPrice, status: s.status)
        }
        items = purchases.filter { $0.currencyCode == currencyCode }.map { p in
            Item(id: p.id, title: p.title, merchant: p.merchantName, category: p.merchantCategory, amount: p.amount, date: p.purchaseDate, hasWarranty: !p.warranties.isEmpty, hasReturnWindow: p.returnWindow?.deadline != nil, hasProductURL: p.productURL != nil, documentType: p.documentType)
        }
    }
}
