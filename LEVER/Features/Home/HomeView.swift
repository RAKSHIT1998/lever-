import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(AppEnvironment.self) private var env
    @Query(sort: \Opportunity.createdAt, order: .reverse) private var allOpportunities: [Opportunity]
    @Query private var savingsEvents: [SavingsEvent]
    @Query private var purchases: [Purchase]
    @State private var selected: Opportunity?
    @State private var showAll = false

    private var open: [Opportunity] {
        OpportunityRanker.rank(allOpportunities.filter(\.isActionable)) { $0.priorityScore }
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
                    }

                    thisMonth

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
        }
        .padding(.top, Spacing.xs)
    }

    private var potentialTotal: Decimal { open.filter(\.countsAsPotentialSaving).compactMap(\.estimatedSavings).reduce(0, +) }
    private var atStake: Decimal { open.filter { !$0.countsAsPotentialSaving }.compactMap(\.estimatedSavings).reduce(0, +) }

    private var nextDeadline: Opportunity? {
        open.filter { ($0.deadline ?? .distantPast) >= Calendar.current.startOfDay(for: .now) }.min { ($0.deadline ?? .distantFuture) < ($1.deadline ?? .distantFuture) }
    }

    private var watchedValue: Decimal { purchases.map(\.amount).reduce(0, +) }

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
