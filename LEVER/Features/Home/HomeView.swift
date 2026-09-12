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
                    if purchases.isEmpty {
                        EmptyState(symbol: "shield.lefthalf.filled", title: "LEVER is waiting for something to protect.", message: "Scan a receipt, renewal or booking and LEVER will look for money you're about to lose.", actionTitle: "Scan your first purchase") {
                            env.router.selectedTab = .capture
                        }
                        .leverCard(padding: Spacing.md)
                    } else if open.isEmpty {
                        InsightBanner(symbol: "checkmark.seal.fill", title: "No money leaks right now.", message: "LEVER re-checks your \(purchases.count) purchase\(purchases.count == 1 ? "" : "s") for deadlines, renewals and price drops every time you open the app.", tint: LeverColor.money)
                    } else {
                        ForEach((showAll ? open : Array(open.prefix(4)))) { opportunity in
                            OpportunityCard(opportunity: opportunity) {
                                env.analytics.track(.opportunityOpened, properties: ["type": opportunity.type.rawValue])
                                selected = opportunity
                            }
                            .accessibilityIdentifier("opportunityCard")
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
            Text(greeting)
                .font(LeverFont.callout)
                .foregroundStyle(LeverColor.inkSecondary)
            Text(headline)
                .font(LeverFont.hero(34))
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
        case 1: return "LEVER found 1 money leak"
        default: return "LEVER found \(open.count) money leaks"
        }
    }

    private var thisMonth: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: "This month", action: { env.router.selectedTab = .savings }, actionTitle: "Savings")
            HStack(spacing: Spacing.xs) {
                SavingsCard(title: "Saved", amount: totals.thisMonth, currencyCode: totals.currencyCode, tint: LeverColor.money)
                SavingsCard(title: "Recovered", amount: totals.byKind[.recovered] ?? 0, currencyCode: totals.currencyCode)
                SavingsCard(title: "Protected", amount: protectedValue, currencyCode: totals.currencyCode)
            }
        }
    }
}
