import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(AppEnvironment.self) private var env
    @Query(sort: \Opportunity.createdAt, order: .reverse) private var allOpportunities: [Opportunity]
    @Query private var savingsEvents: [SavingsEvent]
    @Query private var purchases: [Purchase]
    @State private var selected: Opportunity?
    @State private var showAll = false
    @State private var showScreenshots = false
    @State private var showSources = false
    @State private var otherCurrencyApprox: Decimal?
    @State private var toolDestination: Tool?
    @State private var showTools = false
    @State private var insightPurchase: Purchase?

    private var open: [Opportunity] {
        OpportunityRanker.rank(allOpportunities.filter { $0.isVisibleInFeed && $0.currencyCode == env.currencyCode }) { $0.priorityScore }
    }

    private var totals: SavingsTotals { SavingsTotals(events: savingsEvents, currencyCode: env.currencyCode) }

    private var protectedValue: Decimal {
        purchases.filter { $0.warranties.contains(where: \.isActive) || ($0.returnWindow?.isOpen ?? false) }.map(\.amount).reduce(0, +)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    header
                    if !purchases.isEmpty { hero }
                    if purchases.isEmpty {
                        EmptyState(symbol: "shield.lefthalf.filled", title: "LEVER is waiting for something to protect.", message: "Scan a receipt, renewal or booking and LEVER will look for money you're about to lose.", actionTitle: "Scan your first purchase") {
                            env.router.selectedTab = .capture
                        }
                        .leverCard(padding: Spacing.md)
                    } else if open.isEmpty {
                        InsightBanner(symbol: "checkmark.seal.fill", title: "No money leaks right now.", message: "LEVER re-checks your \(purchases.count) purchase\(purchases.count == 1 ? "" : "s") for deadlines, renewals and price drops every time you open the app.", tint: LeverColor.money)
                    } else {
                        SectionHeader(title: "Money leaks")
                        ForEach(Array((showAll ? open : Array(open.prefix(4))).enumerated()), id: \.element.id) { index, opportunity in
                            OpportunityCard(opportunity: opportunity) {
                                env.analytics.track(.opportunityOpened, properties: ["type": opportunity.type.rawValue])
                                selected = opportunity
                            }
                            .accessibilityIdentifier("opportunityCard")
                            .staggeredAppear(index: index)
                        }
                        if open.count > 4 {
                            Button(showAll ? "Show fewer" : "Show \(open.count - 4) more") { withAnimation(Motion.snappy) { showAll.toggle() } }
                                .buttonStyle(.secondary)
                        }
                        if otherCurrencyCount > 0 {
                            Text(otherCurrencyApprox.map { "\(otherCurrencyCount) more in other currencies ≈ \(Money.format($0, code: env.currencyCode)) at ECB rates — see them in the Vault." } ?? "\(otherCurrencyCount) more in other currencies — see them in the Vault.")
                                .font(LeverFont.caption).foregroundStyle(LeverColor.inkTertiary).frame(maxWidth: .infinity).multilineTextAlignment(.center)
                                .task(id: otherCurrencyCount) { await approximateOtherCurrencies() }
                        }
                    }

                    quickActions
                    insightsSection
                    thisMonth
                    toolsRow
                    sourcesRow

                    Button {
                        env.router.selectedTab = .capture
                    } label: {
                        Label("Scan something", systemImage: "viewfinder")
                    }
                    .buttonStyle(.primary)
                    .accessibilityIdentifier("homeScanButton")
                    .padding(.top, Spacing.xs)

                    HStack(spacing: Spacing.xs) {
                        TrustChip(symbol: "iphone", text: "Read on-device")
                        TrustChip(symbol: "lock.fill", text: "Encrypted vault")
                        TrustChip(symbol: "hand.raised.fill", text: "Never sent for you")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, Spacing.xxs)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.bottom, Spacing.xl)
            }
            .leverScreenBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("LEVER").font(.system(size: 13, weight: .heavy, design: .rounded)).tracking(2).foregroundStyle(LeverColor.inkSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) { ProfileButton() }
            }
            .navigationDestination(item: $selected) { opportunity in
                OpportunityDetailView(opportunity: opportunity)
            }
            .onChange(of: env.router.pendingOpportunityID) { _, id in
                guard let id, let match = allOpportunities.first(where: { $0.id == id }) else { return }
                selected = match
                env.router.pendingOpportunityID = nil
            }
            .refreshable {
                await env.repository.refreshAllOpportunities()
            }
            .sheet(isPresented: $showScreenshots) { ScreenshotPickerSheet() }
            .navigationDestination(isPresented: $showSources) { SourcesView() }
            .navigationDestination(isPresented: $showTools) { ToolsView() }
            .navigationDestination(item: $toolDestination) { ToolRouter(tool: $0) }
            .navigationDestination(item: $insightPurchase) { PurchaseDetailView(purchase: $0) }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("\(greeting)  ·  \(Date.now.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)))")
                .font(LeverFont.callout)
                .foregroundStyle(LeverColor.inkSecondary)
            Text(headline)
                .font(LeverFont.hero(32))
                .foregroundStyle(LeverColor.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("homeHeadline")
            if env.pendingInboxCount > 0 {
                Button {
                    env.router.selectedTab = .capture
                } label: {
                    InsightBanner(symbol: "tray.and.arrow.down.fill", title: "\(env.pendingInboxCount) item\(env.pendingInboxCount == 1 ? "" : "s") shared to LEVER", message: "Tap to review what LEVER finds.")
                }
                .buttonStyle(.plain)
            }
            if env.pendingScreenshotCount > 0 {
                Button { showScreenshots = true } label: {
                    InsightBanner(symbol: "rectangle.dashed.badge.record", title: "\(env.pendingScreenshotCount) new screenshot\(env.pendingScreenshotCount == 1 ? "" : "s") since you last looked", message: "Any receipts or renewals in there? Tap to check.", tint: LeverColor.money)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, Spacing.xs)
    }

    private var potentialTotal: Decimal { open.filter(\.countsAsPotentialSaving).compactMap(\.estimatedSavings).reduce(0, +) }
    private var atStake: Decimal { open.filter { !$0.countsAsPotentialSaving }.compactMap(\.estimatedSavings).reduce(0, +) }

    private var nextDeadline: Opportunity? {
        open.filter { ($0.deadline ?? .distantPast) >= Calendar.current.startOfDay(for: .now) }.min { ($0.deadline ?? .distantFuture) < ($1.deadline ?? .distantFuture) }
    }

    private var watchedValue: Decimal { purchases.filter { $0.currencyCode == env.currencyCode }.map(\.amount).reduce(0, +) }
    private var otherCurrencyCount: Int { allOpportunities.filter { $0.isVisibleInFeed && $0.currencyCode != env.currencyCode }.count }

    /// The value proposition in one panel: what LEVER can still save, what it protects, what's next.
    private var hero: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(open.isEmpty ? "EVERYTHING WATCHED" : "POTENTIAL SAVINGS")
                        .font(.caption2.weight(.bold)).tracking(1.1)
                        .foregroundStyle(LeverColor.onInkSecondary)
                    MoneyAmount(amount: open.isEmpty ? watchedValue : potentialTotal, currencyCode: env.currencyCode, size: .hero, tint: open.isEmpty ? LeverColor.onInk : Color(red: 0.36, green: 0.88, blue: 0.55))
                    Text(open.isEmpty
                         ? "across \(purchases.count) purchase\(purchases.count == 1 ? "" : "s") LEVER is watching for you"
                         : "across \(open.count) open opportunit\(open.count == 1 ? "y" : "ies"). Counted only when you confirm it.")
                        .font(LeverFont.caption)
                        .foregroundStyle(LeverColor.onInkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(LeverColor.onInkSecondary)
            }
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
            HStack(spacing: Spacing.md) {
                HeroStat(label: "At stake", value: Money.format(atStake, code: env.currencyCode, compact: true))
                HeroStat(label: "Watching", value: Money.format(watchedValue, code: env.currencyCode, compact: true))
                HeroStat(label: "Next deadline", value: nextDeadline?.deadline.map { DateMath.relativePhrase(to: $0).capitalized } ?? "None")
            }
        }
        .inkPanel()
        .accessibilityElement(children: .combine)
    }

    private var connectedSources: Int {
        1 + (env.settings.screenshotWatchEnabled ? 1 : 0) + (env.settings.walletConnected ? 1 : 0) + (purchases.contains { $0.productURL != nil } ? 1 : 0) + (purchases.contains { $0.subscription?.source.lowercased().contains("statement") ?? false } ? 1 : 0)
    }

    @State private var showAsk = false
    @State private var showStatementImport = false

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: "Quick actions")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.xs) {
                QuickActionCard(symbol: "qrcode.viewfinder", title: "Scan & Pay", subtitle: "\(env.paymentRegion.railName) QR → your app → logged", tint: LeverColor.money) { toolDestination = .scanAndPay }
                QuickActionCard(symbol: "viewfinder", title: "Scan receipt", subtitle: "Receipt, bill or screen") { env.router.selectedTab = .capture }
                QuickActionCard(symbol: "chart.bar.xaxis", title: "Spending", subtitle: "Where the money went", tint: LeverColor.info) { toolDestination = .spending }
                QuickActionCard(symbol: "building.columns", title: "Statement", subtitle: "Bank, PhonePe, Paytm, GPay exports", tint: LeverColor.opportunity) { showSources = true }
                QuickActionCard(symbol: "doc.on.clipboard", title: "Paste", subtitle: "Email, SMS or UPI receipt", tint: LeverColor.protection) { env.router.pendingPasteRequest = true; env.router.selectedTab = .capture }
                QuickActionCard(symbol: "text.bubble", title: "Ask LEVER", subtitle: "Warranties, renewals, returns…") { toolDestination = .askLever }
            }
        }
    }

    private var insights: [Insight] {
        Array(InsightEngine.generate(VaultSummary(purchases: purchases, currencyCode: env.currencyCode)).prefix(3))
    }

    /// Patterns across the vault — softer than leaks, still grounded in the user's own data.
    @ViewBuilder
    private var insightsSection: some View {
        if !insights.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                SectionHeader(title: "Smart suggestions", action: { showTools = true }, actionTitle: "Tools")
                ForEach(insights) { insight in
                    Button { act(on: insight) } label: {
                        HStack(alignment: .top, spacing: Spacing.sm) {
                            ZStack {
                                Circle().fill(LeverColor.moneySoft)
                                Image(systemName: insight.symbol).font(.body.weight(.semibold)).foregroundStyle(LeverColor.money)
                            }
                            .frame(width: 36, height: 36)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(insight.title).font(LeverFont.headline).foregroundStyle(LeverColor.ink).multilineTextAlignment(.leading)
                                Text(insight.detail).font(LeverFont.caption).foregroundStyle(LeverColor.inkSecondary).multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 0)
                            if let title = insight.actionTitle {
                                Text(title).font(.caption.weight(.bold)).foregroundStyle(LeverColor.money).padding(.top, 8)
                            }
                        }
                        .leverCard(padding: Spacing.sm, radius: Radius.md)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("insightCard")
                }
            }
        }
    }

    private func act(on insight: Insight) {
        switch insight.action {
        case .none: break
        case .openPurchase(let id): insightPurchase = purchases.first { $0.id == id }
        case .openTool(let tool): toolDestination = tool
        case .openSources: showSources = true
        }
    }

    private var toolsRow: some View {
        Button { showTools = true } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "wrench.and.screwdriver").font(.body.weight(.semibold)).foregroundStyle(LeverColor.ink).frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tools").font(LeverFont.headline).foregroundStyle(LeverColor.ink)
                    Text("Subscription audit · Next 30 days · Cost per use · Should I return it? · Ask LEVER").font(LeverFont.caption).foregroundStyle(LeverColor.inkSecondary).multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(LeverColor.inkTertiary)
            }
            .leverCard(padding: Spacing.sm, radius: Radius.md)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("toolsRow")
    }

    /// Where LEVER's knowledge comes from — and an invitation to widen it.
    private var sourcesRow: some View {
        Button { showSources = true } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "antenna.radiowaves.left.and.right").font(.body.weight(.semibold)).foregroundStyle(LeverColor.ink).frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(connectedSources <= 1 ? "LEVER only knows what you scan" : "\(connectedSources) sources feeding LEVER").font(LeverFont.headline).foregroundStyle(LeverColor.ink)
                    Text(connectedSources <= 1 ? "Import a statement or turn on the screenshot watcher to catch renewals you'd never scan." : "Statements, screenshots, Wallet and tracked prices. Manage sources.")
                        .font(LeverFont.caption).foregroundStyle(LeverColor.inkSecondary).multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(LeverColor.inkTertiary)
            }
            .leverCard(padding: Spacing.sm, radius: Radius.md)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("sourcesRow")
    }

    /// Sums other-currency potential savings in the home currency using cached ECB rates. Nil when a rate is missing.
    private func approximateOtherCurrencies() async {
        let others = allOpportunities.filter { $0.isVisibleInFeed && $0.currencyCode != env.currencyCode && $0.countsAsPotentialSaving }
        var total: Decimal = 0
        for o in others {
            guard let amount = o.estimatedSavings, let converted = await ExchangeRateService.shared.convert(amount, from: o.currencyCode, to: env.currencyCode) else { otherCurrencyApprox = nil; return }
            total += converted
        }
        otherCurrencyApprox = total > 0 ? total : nil
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        switch hour {
        case 5..<12: return "Good morning."
        case 12..<17: return "Good afternoon."
        default: return "Good evening."
        }
    }

    private var headline: String {
        if purchases.isEmpty { return "Let's find your first money leak." }
        switch open.count {
        case 0: return "Nothing leaking. Nice."
        case 1: return "LEVER found 1 money leak."
        default: return "LEVER found \(open.count) money leaks."
        }
    }

    private var thisMonth: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: "This month", action: { env.router.selectedTab = .savings }, actionTitle: "Savings")
            HStack(spacing: Spacing.xs) {
                SavingsCard(title: "Saved", amount: totals.thisMonth, currencyCode: totals.currencyCode, tint: LeverColor.money, symbol: "arrow.down.circle.fill")
                SavingsCard(title: "Recovered", amount: totals.byKind[.recovered] ?? 0, currencyCode: totals.currencyCode, symbol: "arrow.uturn.backward.circle.fill")
                SavingsCard(title: "Protected", amount: protectedValue, currencyCode: totals.currencyCode, symbol: "shield.fill")
            }
        }
    }
}
