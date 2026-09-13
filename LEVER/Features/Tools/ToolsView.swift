import SwiftUI
import SwiftData

/// The toolbox: focused, fast utilities that answer one money question each.
struct ToolsView: View {
    @State private var selected: Tool?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Tools").font(LeverFont.display)
                Text("Small, sharp answers from your own vault. Nothing here is a guess.").font(LeverFont.callout).foregroundStyle(LeverColor.inkSecondary)
                ForEach(Tool.allCases) { tool in
                    Button { selected = tool } label: {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: tool.symbol).font(.title3.weight(.medium)).foregroundStyle(LeverColor.ink).frame(width: 34)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(tool.title).font(LeverFont.headline).foregroundStyle(LeverColor.ink)
                                Text(tool.subtitle).font(LeverFont.caption).foregroundStyle(LeverColor.inkSecondary).multilineTextAlignment(.leading)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(LeverColor.inkTertiary)
                        }
                        .leverCard(padding: Spacing.sm, radius: Radius.md)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("tool-\(tool.rawValue)")
                }
            }
            .padding(Spacing.md)
        }
        .leverScreenBackground()
        .navigationTitle("Tools")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selected) { ToolRouter(tool: $0) }
    }
}

struct ToolRouter: View {
    let tool: Tool
    var body: some View {
        switch tool {
        case .subscriptionAudit: SubscriptionAuditView()
        case .cashForecast: CashForecastView()
        case .costPerUse: CostPerUseView()
        case .returnDecision: ReturnDecisionView()
        case .askLever: AskLeverView()
        }
    }
}

// MARK: - Subscription audit

struct SubscriptionAuditView: View {
    @Environment(AppEnvironment.self) private var env
    @Query private var purchases: [Purchase]
    @State private var yearly = false

    private var subs: [Purchase] { purchases.filter { $0.subscription != nil && $0.subscription?.status != .cancelled && $0.currencyCode == env.currencyCode } }
    private func cost(_ p: Purchase) -> Decimal? {
        guard let s = p.subscription, let annual = SubscriptionMath.annualCost(price: s.price, cycle: s.billingCycle) else { return nil }
        return yearly ? annual : (annual / 12).rounded(scale: 0)
    }
    private var total: Decimal { subs.compactMap(cost).reduce(0, +) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("YOU PAY ON REPEAT").font(.caption2.weight(.bold)).tracking(1.1).foregroundStyle(LeverColor.inkSecondary)
                    MoneyAmount(amount: total, currencyCode: env.currencyCode, size: .hero)
                    Picker("", selection: $yearly) { Text("per month").tag(false); Text("per year").tag(true) }.pickerStyle(.segmented).frame(width: 220)
                }
                if subs.isEmpty {
                    InsightBanner(symbol: "building.columns", title: "No subscriptions yet", message: "Import a bank statement or scan a renewal email and they'll appear here.", tint: LeverColor.inkSecondary)
                }
                ForEach(subs.sorted { (cost($0) ?? 0) > (cost($1) ?? 0) }) { p in
                    NavigationLink { PurchaseDetailView(purchase: p) } label: {
                        HStack(spacing: Spacing.sm) {
                            MerchantAvatar(name: p.merchantName, category: p.merchantCategory, size: 40)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(p.merchantName).font(LeverFont.headline).foregroundStyle(LeverColor.ink)
                                HStack(spacing: 6) {
                                    if let s = p.subscription {
                                        Text("\(Money.format(s.price, code: p.currencyCode))\(s.billingCycle.shortSuffix)")
                                        if let prev = s.previousPrice, prev < s.price { Text("↑ from \(Money.format(prev, code: p.currencyCode))").foregroundStyle(LeverColor.opportunity) }
                                        if s.status == .markedUnused { Text("· unused").foregroundStyle(LeverColor.urgent) }
                                    }
                                }
                                .font(LeverFont.caption).foregroundStyle(LeverColor.inkSecondary)
                            }
                            Spacer()
                            if let c = cost(p) { MoneyAmount(amount: c, currencyCode: p.currencyCode, size: .small) }
                        }
                        .leverCard(padding: Spacing.sm, radius: Radius.md)
                    }
                    .buttonStyle(.plain)
                }
                if !subs.isEmpty {
                    Text("Tap a subscription to mark it unused, see manage links, or negotiate. Marked-unused ones become renewal warnings before they charge.")
                        .font(.caption2).foregroundStyle(LeverColor.inkTertiary)
                }
            }
            .padding(Spacing.md)
        }
        .leverScreenBackground()
        .navigationTitle("Subscription audit")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Cash forecast

struct CashForecastView: View {
    @Environment(AppEnvironment.self) private var env
    @Query private var purchases: [Purchase]
    @Query private var opportunities: [Opportunity]

    struct Entry: Identifiable { let id: String; let date: Date; let title: String; let amount: Decimal?; let symbol: String; let purchaseID: UUID? }

    private var entries: [Entry] {
        let now = Calendar.current.startOfDay(for: .now)
        let end = DateMath.adding(days: 30, to: now) ?? now
        var out: [Entry] = []
        for p in purchases where p.currencyCode == env.currencyCode {
            if let s = p.subscription, s.status != .cancelled, let d = s.nextBillingDate, d >= now, d <= end {
                out.append(Entry(id: "sub-\(p.id)", date: d, title: "\(p.merchantName) renews", amount: s.price, symbol: "arrow.triangle.2.circlepath", purchaseID: p.id))
            }
            if let d = p.returnWindow?.deadline, d >= now, d <= end {
                out.append(Entry(id: "ret-\(p.id)", date: d, title: "Return window closes · \(p.title)", amount: nil, symbol: "arrow.uturn.backward", purchaseID: p.id))
            }
            for w in p.warranties { if let d = w.endDate, d >= now, d <= end { out.append(Entry(id: "war-\(w.id)", date: d, title: "\(w.provider) coverage ends · \(p.title)", amount: nil, symbol: "shield", purchaseID: p.id)) } }
        }
        return out.sorted { $0.date < $1.date }
    }
    private var outflow: Decimal { entries.compactMap(\.amount).reduce(0, +) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("NEXT 30 DAYS").font(.caption2.weight(.bold)).tracking(1.1).foregroundStyle(LeverColor.inkSecondary)
                    MoneyAmount(amount: outflow, currencyCode: env.currencyCode, size: .hero)
                    Text("in renewals · \(entries.filter { $0.amount == nil }.count) deadline\(entries.filter { $0.amount == nil }.count == 1 ? "" : "s")").font(LeverFont.callout).foregroundStyle(LeverColor.inkSecondary)
                }
                if entries.isEmpty {
                    InsightBanner(symbol: "checkmark.circle", title: "Nothing scheduled in the next month", tint: LeverColor.money)
                }
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(entries) { e in
                        HStack(alignment: .top, spacing: Spacing.sm) {
                            VStack(spacing: 0) {
                                Text(e.date.formatted(.dateTime.day())).font(.system(.title3, design: .rounded).weight(.bold)).monospacedDigit()
                                Text(e.date.formatted(.dateTime.month(.abbreviated)).uppercased()).font(.caption2.weight(.bold)).foregroundStyle(LeverColor.inkSecondary)
                            }
                            .frame(width: 44)
                            Image(systemName: e.symbol).foregroundStyle(LeverColor.inkSecondary).frame(width: 20).padding(.top, 4)
                            Text(e.title).font(LeverFont.callout).lineLimit(2)
                            Spacer()
                            if let a = e.amount { MoneyAmount(amount: a, currencyCode: env.currencyCode, size: .small) }
                        }
                        .padding(.vertical, Spacing.sm)
                        Divider()
                    }
                }
                .leverCard(padding: Spacing.sm)
                if !entries.isEmpty {
                    Button {
                        Task {
                            for e in entries { _ = await env.calendar.addDeadline(title: "LEVER: \(e.title)", notes: e.amount.map { Money.format($0, code: env.currencyCode) } ?? "", date: e.date) }
                            Haptics.actionCompleted()
                        }
                    } label: { Label("Add all to Calendar", systemImage: "calendar.badge.plus") }
                    .buttonStyle(.secondary)
                }
            }
            .padding(Spacing.md)
        }
        .leverScreenBackground()
        .navigationTitle("Next 30 days")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Cost per use

struct CostPerUseView: View {
    @Environment(AppEnvironment.self) private var env
    @Query private var purchases: [Purchase]
    @State private var selected: Purchase?
    @State private var usesPerMonth: Double = 4

    private var subs: [Purchase] { purchases.filter { $0.subscription != nil && $0.subscription?.status != .cancelled } }
    private var monthly: Decimal? {
        guard let s = selected?.subscription, let annual = SubscriptionMath.annualCost(price: s.price, cycle: s.billingCycle) else { return nil }
        return annual / 12
    }
    private var perUse: Decimal? { monthly.map { usesPerMonth > 0 ? ($0 / Decimal(usesPerMonth)).rounded(scale: 0) : $0 } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                Text("Price ÷ how often you actually use it. The number that makes a subscription decision obvious.").font(LeverFont.callout).foregroundStyle(LeverColor.inkSecondary)
                if subs.isEmpty {
                    InsightBanner(symbol: "building.columns", title: "No subscriptions to evaluate yet", tint: LeverColor.inkSecondary)
                } else {
                    Picker("Subscription", selection: $selected) {
                        Text("Choose…").tag(Purchase?.none)
                        ForEach(subs) { p in Text(p.merchantName).tag(Purchase?.some(p)) }
                    }
                    .pickerStyle(.menu).leverCard(padding: Spacing.sm, radius: Radius.md)
                }
                if let selected, let monthly, let perUse {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("How many times a month do you use \(selected.merchantName)?").font(LeverFont.headline)
                        HStack {
                            Slider(value: $usesPerMonth, in: 0...60, step: 1)
                            Text("\(Int(usesPerMonth))×").font(LeverFont.label).monospacedDigit().frame(width: 40)
                        }
                        Divider()
                        HStack(alignment: .lastTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Per use").font(LeverFont.caption).foregroundStyle(LeverColor.inkSecondary)
                                MoneyAmount(amount: perUse, currencyCode: selected.currencyCode, size: .large, tint: verdictColor(perUse: perUse, monthly: monthly))
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("Per month").font(LeverFont.caption).foregroundStyle(LeverColor.inkSecondary)
                                MoneyAmount(amount: monthly.rounded(scale: 0), currencyCode: selected.currencyCode, size: .medium)
                            }
                        }
                        Text(verdict(perUse: perUse, monthly: monthly, merchant: selected.merchantName)).font(LeverFont.callout).foregroundStyle(LeverColor.inkSecondary)
                        NavigationLink { PurchaseDetailView(purchase: selected) } label: { Text("Open \(selected.merchantName)").frame(maxWidth: .infinity) }.buttonStyle(.secondary)
                    }
                    .leverCard()
                }
            }
            .padding(Spacing.md)
        }
        .leverScreenBackground()
        .navigationTitle("Cost per use")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func verdictColor(perUse: Decimal, monthly: Decimal) -> Color {
        usesPerMonth == 0 ? LeverColor.urgent : (perUse > monthly / 2 ? LeverColor.opportunity : LeverColor.money)
    }

    private func verdict(perUse: Decimal, monthly: Decimal, merchant: String) -> String {
        if usesPerMonth == 0 { return "You're paying for nothing. Mark it unused and LEVER will warn you before the next charge." }
        if perUse > monthly / 2 { return "Two uses or fewer a month. Consider pausing, or check whether \(merchant) has a cheaper tier or a pay-per-use option." }
        if usesPerMonth >= 20 { return "Daily-ish use. This one earns its keep — the only question is whether a yearly plan would be cheaper." }
        return "Reasonable value. Revisit if the price goes up or your habits change."
    }
}

// MARK: - Return decision

struct ReturnDecisionView: View {
    @Environment(AppEnvironment.self) private var env
    @Query private var purchases: [Purchase]
    @State private var selected: Purchase?
    @State private var useIt: Bool? = nil
    @State private var cheaperText = ""
    @State private var faulty = false

    private var candidates: [Purchase] { purchases.filter { $0.returnWindow?.isOpen ?? false } }
    private var cheaper: Decimal? { AmountParser.parseDecimal(cheaperText) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                Text("Only for purchases whose return window is still open. Three questions, one recommendation.").font(LeverFont.callout).foregroundStyle(LeverColor.inkSecondary)
                if candidates.isEmpty {
                    InsightBanner(symbol: "checkmark.circle", title: "No open return windows right now", message: "When a purchase with a known return deadline is in the vault, it shows up here.", tint: LeverColor.inkSecondary)
                } else {
                    Picker("Purchase", selection: $selected) {
                        Text("Choose…").tag(Purchase?.none)
                        ForEach(candidates) { p in Text("\(p.title) · \(p.returnWindow?.deadline.map { DateMath.relativePhrase(to: $0) } ?? "")").tag(Purchase?.some(p)) }
                    }
                    .pickerStyle(.menu).leverCard(padding: Spacing.sm, radius: Radius.md)
                }
                if let selected {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        question("Have you actually used it since it arrived?") {
                            HStack { choice("Yes", useIt == true) { useIt = true }; choice("Not really", useIt == false) { useIt = false } }
                        }
                        question("Anything wrong with it?") {
                            Toggle("Faulty, damaged or not as described", isOn: $faulty).tint(LeverColor.money).font(LeverFont.callout)
                        }
                        question("Seen it cheaper elsewhere? (\(selected.currencyCode))") {
                            TextField("Leave blank if not", text: $cheaperText).keyboardType(.decimalPad).font(LeverFont.callout)
                                .padding(10).background(LeverColor.surfaceElevated, in: RoundedRectangle(cornerRadius: Radius.sm))
                        }
                    }
                    .leverCard()
                    if let useIt {
                        let r = ReturnDecision.recommend(useIt: useIt, faulty: faulty, paid: selected.amount, cheaper: cheaper, daysLeft: selected.returnWindow?.daysRemaining() ?? 0)
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Label(r.title, systemImage: r.symbol).font(LeverFont.title3).foregroundStyle(r.keep ? LeverColor.money : LeverColor.urgent)
                            Text(r.detail).font(LeverFont.callout).foregroundStyle(LeverColor.inkSecondary)
                            NavigationLink { PurchaseDetailView(purchase: selected) } label: { Text(r.keep ? "Open purchase" : "Start the return").frame(maxWidth: .infinity) }.buttonStyle(r.keep ? .secondary : .secondary)
                        }
                        .leverCard()
                    }
                }
            }
            .padding(Spacing.md)
        }
        .leverScreenBackground()
        .navigationTitle("Should I return it?")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func question<Content: View>(_ text: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) { Text(text).font(LeverFont.headline); content() }
    }

    private func choice(_ label: String, _ on: Bool, action: @escaping () -> Void) -> some View {
        Button(label, action: action)
            .font(LeverFont.label)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(on ? LeverColor.ink : LeverColor.surfaceElevated, in: Capsule())
            .foregroundStyle(on ? LeverColor.background : LeverColor.ink)
    }
}

/// Pure so it's testable: the return recommendation.
enum ReturnDecision {
    struct Result: Equatable { var keep: Bool; var title: String; var detail: String; var symbol: String }

    static func recommend(useIt: Bool, faulty: Bool, paid: Decimal, cheaper: Decimal?, daysLeft: Int) -> Result {
        if faulty {
            return Result(keep: false, title: "Return or exchange it", detail: "Faulty or not-as-described items are the strongest return case there is. Don't wait — \(daysLeft) day\(daysLeft == 1 ? "" : "s") left.", symbol: "exclamationmark.arrow.circlepath")
        }
        if let cheaper, cheaper < paid, paid - cheaper >= max(500, paid / 20) {
            let diff = paid - cheaper
            return Result(keep: useIt, title: useIt ? "Keep it — but claim the difference" : "Return and rebuy cheaper", detail: useIt
                ? "You use it, so keep it. Ask the seller to price-match the \(diff) difference; if they won't and the window allows, return and rebuy."
                : "You barely use it and it's \(diff) cheaper elsewhere. Return it; rebuy only if you still want it in a week.", symbol: useIt ? "tag" : "arrow.uturn.backward")
        }
        if !useIt {
            return Result(keep: false, title: "Return it", detail: "Unused after arrival is the most reliable predictor of regret. \(daysLeft) day\(daysLeft == 1 ? "" : "s") left to decide — decide now.", symbol: "arrow.uturn.backward")
        }
        return Result(keep: true, title: "Keep it", detail: "You use it, it works, and it's fairly priced. LEVER will still watch the warranty and the price.", symbol: "checkmark.seal")
    }
}

// MARK: - Ask LEVER

struct AskLeverView: View {
    @Environment(AppEnvironment.self) private var env
    @Query private var purchases: [Purchase]
    @Query private var savings: [SavingsEvent]
    @State private var question = ""
    @State private var messages: [(q: String, a: String)] = []
    @State private var thinking = false

    private let suggestions = ["Which warranties expire this year?", "What renews next month?", "How much have I saved?", "What can I still return?", "How much do I spend on subscriptions?"]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    if messages.isEmpty {
                        Text("Ask about your own vault. Answers come from your data on this iPhone\(env.settings.cloudAIEnabled && GeminiIntelligenceProvider.storedKey != nil ? "; free-form questions may use Gemini with a summary of your vault (no documents)" : "").")
                            .font(LeverFont.callout).foregroundStyle(LeverColor.inkSecondary)
                        ForEach(suggestions, id: \.self) { s in
                            Button { question = s; Task { await ask() } } label: {
                                Text(s).font(LeverFont.callout).foregroundStyle(LeverColor.ink).frame(maxWidth: .infinity, alignment: .leading).leverCard(padding: Spacing.sm, radius: Radius.md)
                            }.buttonStyle(.plain)
                        }
                    }
                    ForEach(Array(messages.enumerated()), id: \.offset) { _, m in
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text(m.q).font(LeverFont.headline).frame(maxWidth: .infinity, alignment: .trailing).multilineTextAlignment(.trailing)
                            Text(m.a).font(LeverFont.callout).textSelection(.enabled).leverCard(padding: Spacing.sm, radius: Radius.md)
                        }
                    }
                    if thinking { ProgressView().frame(maxWidth: .infinity) }
                }
                .padding(Spacing.md)
            }
            HStack(spacing: Spacing.xs) {
                TextField("Ask about warranties, renewals, returns, spending…", text: $question, axis: .vertical).lineLimit(1...3)
                    .padding(10).background(LeverColor.surface, in: RoundedRectangle(cornerRadius: Radius.md))
                    .accessibilityIdentifier("askField")
                Button { Task { await ask() } } label: { Image(systemName: "arrow.up.circle.fill").font(.title) }
                    .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty || thinking)
                    .accessibilityIdentifier("askSend")
            }
            .padding(Spacing.md)
            .background(LeverColor.background)
        }
        .leverScreenBackground()
        .navigationTitle("Ask LEVER")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func ask() async {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        question = ""
        thinking = true
        let summary = VaultSummary(purchases: purchases, currencyCode: env.currencyCode)
        let totals = SavingsTotals(events: savings, currencyCode: env.currencyCode)
        var answer = VaultAnswerer.answer(q, purchases: purchases, totals: totals, currencyCode: env.currencyCode)
        if answer == nil, env.settings.cloudAIEnabled, let key = GeminiIntelligenceProvider.storedKey {
            answer = await VaultAnswerer.cloudAnswer(q, summary: summary, totals: totals, key: key, model: GeminiIntelligenceProvider.storedModel)
        }
        messages.append((q, answer ?? "I can answer about warranties, renewals, returns, subscriptions, spending and savings in your vault. Try one of those — or turn on cloud intelligence in Privacy Center for free-form questions."))
        thinking = false
    }
}

/// On-device answers for the questions people actually ask. Deterministic, no model needed.
enum VaultAnswerer {
    @MainActor
    static func answer(_ q: String, purchases: [Purchase], totals: SavingsTotals, currencyCode code: String) -> String? {
        let lower = q.lowercased()
        let now = Date.now
        func list(_ lines: [String], empty: String) -> String { lines.isEmpty ? empty : lines.joined(separator: "\n") }

        if lower.contains("warrant") || lower.contains("coverage") {
            let horizon = lower.contains("year") ? 365 : (lower.contains("month") ? 30 : 180)
            let lines = purchases.flatMap { p in p.warranties.compactMap { w -> (Date, String)? in
                guard let end = w.endDate, end >= now, DateMath.days(from: now, to: end) <= horizon else { return nil }
                return (end, "• \(p.title) — \(w.provider) until \(end.leverShort) (\(DateMath.relativePhrase(to: end)))")
            } }.sorted { $0.0 < $1.0 }.map(\.1)
            return list(lines, empty: "No warranties expire in the next \(horizon) days. \(purchases.filter { !$0.warranties.isEmpty }.count) purchases have coverage on record.")
        }
        if lower.contains("renew") || lower.contains("subscription") || lower.contains("recurring") {
            let subs = purchases.filter { $0.subscription != nil && $0.subscription?.status != .cancelled }
            if lower.contains("how much") || lower.contains("spend") || lower.contains("total") || lower.contains("cost") {
                let monthly = subs.compactMap { s in SubscriptionMath.annualCost(price: s.subscription!.price, cycle: s.subscription!.billingCycle).map { $0 / 12 } }.reduce(0, +)
                return "\(subs.count) active subscriptions cost about \(Money.format(monthly.rounded(scale: 0), code: code)) a month — \(Money.format((monthly * 12).rounded(scale: 0), code: code)) a year. Biggest: \(subs.sorted { ($0.subscription?.annualCost ?? 0) > ($1.subscription?.annualCost ?? 0) }.prefix(3).map(\.merchantName).joined(separator: ", "))."
            }
            let horizon = lower.contains("week") ? 7 : (lower.contains("year") ? 365 : 45)
            let lines = subs.compactMap { p -> (Date, String)? in
                guard let d = p.subscription?.nextBillingDate, d >= now, DateMath.days(from: now, to: d) <= horizon else { return nil }
                return (d, "• \(p.merchantName) — \(Money.format(p.subscription!.price, code: p.currencyCode)) on \(d.leverShort)")
            }.sorted { $0.0 < $1.0 }.map(\.1)
            return list(lines, empty: "Nothing renews in the next \(horizon) days.")
        }
        if lower.contains("return") {
            let lines = purchases.compactMap { p -> (Date, String)? in
                guard let d = p.returnWindow?.deadline, p.returnWindow?.isOpen == true else { return nil }
                return (d, "• \(p.title) (\(Money.format(p.amount, code: p.currencyCode))) — until \(d.leverShort), \(DateMath.relativePhrase(to: d))")
            }.sorted { $0.0 < $1.0 }.map(\.1)
            return list(lines, empty: "No open return windows right now.")
        }
        if lower.contains("saved") || lower.contains("savings") || lower.contains("recover") {
            return "You've confirmed \(Money.format(totals.lifetime, code: code)) saved with LEVER — \(Money.format(totals.thisMonth, code: code)) this month\(totals.pending > 0 ? ", with \(Money.format(totals.pending, code: code)) awaiting your confirmation" : ""). Breakdown: " + SavingsKind.allCases.compactMap { k in (totals.byKind[k] ?? 0) > 0 ? "\(k.displayName.lowercased()) \(Money.format(totals.byKind[k]!, code: code))" : nil }.joined(separator: ", ") + "."
        }
        if lower.contains("spend") || lower.contains("spent") || lower.contains("total") || lower.contains("how much") {
            let recent = purchases.filter { ($0.purchaseDate.map { DateMath.days(from: $0, to: now) <= 30 } ?? false) && $0.currencyCode == code }
            let total = recent.map(\.amount).reduce(0, +)
            return "In the last 30 days LEVER has \(recent.count) purchase\(recent.count == 1 ? "" : "s") totalling \(Money.format(total, code: code)). Across everything in the vault: \(Money.format(purchases.filter { $0.currencyCode == code }.map(\.amount).reduce(0, +), code: code)) over \(purchases.count) records. (Only what you've captured — not your whole bank account.)"
        }
        if lower.contains("expensive") || lower.contains("biggest") || lower.contains("largest") {
            let top = purchases.sorted { $0.amount > $1.amount }.prefix(3)
            return list(top.map { "• \($0.title) — \(Money.format($0.amount, code: $0.currencyCode)) from \($0.merchantName)" }, empty: "Nothing in the vault yet.")
        }
        return nil
    }

    /// Free-form questions go to Gemini with a compact, document-free summary of the vault.
    static func cloudAnswer(_ q: String, summary: VaultSummary, totals: SavingsTotals, key: String, model: String) async -> String? {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        var lines = ["Today: \(f.string(from: .now)). Currency: \(summary.currencyCode).", "PURCHASES:"]
        lines += summary.items.prefix(60).map { "- \($0.title) | \($0.merchant) | \($0.amount) | \($0.date.map(f.string) ?? "?") | warranty:\($0.hasWarranty) return:\($0.hasReturnWindow)" }
        lines.append("SUBSCRIPTIONS:")
        lines += summary.subscriptions.map { "- \($0.merchant) | \($0.price)\($0.cycle.shortSuffix) | next \($0.next.map(f.string) ?? "?") | prev \($0.previous.map { "\($0)" } ?? "-") | \($0.status.rawValue)" }
        lines.append("CONFIRMED SAVINGS: \(totals.lifetime) lifetime, \(totals.thisMonth) this month.")
        let prompt = "You are LEVER, a careful personal-finance assistant. Answer the user's question using ONLY the vault data below. If the data can't answer it, say so plainly. Be concise (max 5 sentences or a short bullet list). Never invent purchases, prices, policies or dates.\n\n" + lines.joined(separator: "\n") + "\n\nQUESTION: \(q)"
        var request = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!)
        request.httpMethod = "POST"; request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["contents": [["parts": [["text": prompt]]]], "generationConfig": ["temperature": 0.2]])
        guard let (data, response) = try? await URLSession.shared.data(for: request), (response as? HTTPURLResponse)?.statusCode == 200,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = object["candidates"] as? [[String: Any]], let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]], let text = parts.first?["text"] as? String else { return nil }
        return text.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n— answered with Gemini from a summary of your vault"
    }
}
