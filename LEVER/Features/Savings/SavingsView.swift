import SwiftUI
import SwiftData

struct SavingsView: View {
    @Environment(AppEnvironment.self) private var env
    @Query(sort: \SavingsEvent.date, order: .reverse) private var events: [SavingsEvent]
    @State private var confirming: SavingsEvent?

    private var totals: SavingsTotals { SavingsTotals(events: events, currencyCode: env.currencyCode) }
    private var confirmed: [SavingsEvent] { events.filter { $0.status == .confirmed } }
    private var pending: [SavingsEvent] { events.filter { $0.status == .pending } }

    private var grouped: [(String, [SavingsEvent])] {
        let groups = Dictionary(grouping: confirmed) { DateMath.monthTitle(for: $0.confirmedAt ?? $0.date) }
        return groups.sorted { ($0.value.first?.confirmedAt ?? .distantPast) > ($1.value.first?.confirmedAt ?? .distantPast) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    hero
                    if confirmed.isEmpty && pending.isEmpty {
                        EmptyState(symbol: "sparkles", title: "Your first \(Money.symbol(for: env.currencyCode))1 saved starts here.", message: "When LEVER helps you recover, avoid or negotiate money, confirm it and it lands here. Only what you confirm counts.", actionTitle: "Find a money leak") {
                            env.router.selectedTab = .home
                        }
                    } else {
                        breakdown
                        if !pending.isEmpty { pendingSection }
                        timeline
                    }
                }
                .padding(Spacing.md)
                .padding(.bottom, Spacing.xl)
            }
            .leverScreenBackground()
            .navigationTitle("Savings")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { ProfileButton() } }
            .sheet(item: $confirming) { event in
                if let opportunity = event.opportunity {
                    SavingsConfirmationSheet(opportunity: opportunity) { confirming = nil }
                } else {
                    PendingSavingSheet(event: event) { confirming = nil }
                }
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            MoneyAmount(amount: totals.lifetime, currencyCode: totals.currencyCode, size: .hero, tint: LeverColor.money)
                .accessibilityIdentifier("lifetimeSaved")
            Text("saved with LEVER").font(LeverFont.callout).foregroundStyle(LeverColor.inkSecondary)
            if totals.thisMonth > 0 {
                Text("\(Money.format(totals.thisMonth, code: totals.currencyCode)) this month").font(LeverFont.label).foregroundStyle(LeverColor.ink).padding(.top, Spacing.xxs)
            }
        }
        .padding(.top, Spacing.xs)
    }

    private var breakdown: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.xs) {
            ForEach(SavingsKind.allCases, id: \.self) { kind in
                SavingsCard(title: kind.displayName, amount: totals.byKind[kind] ?? 0, currencyCode: totals.currencyCode)
            }
        }
    }

    private var pendingSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: "Waiting for your confirmation")
            ForEach(pending) { event in
                Button { confirming = event } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(event.title).font(LeverFont.headline).foregroundStyle(LeverColor.ink).multilineTextAlignment(.leading)
                            Text("Did this actually happen?").font(LeverFont.caption).foregroundStyle(LeverColor.inkSecondary)
                        }
                        Spacer()
                        MoneyAmount(amount: event.amount, currencyCode: event.currencyCode, size: .small, tint: LeverColor.opportunity)
                    }
                    .leverCard(padding: Spacing.sm)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("pendingSavingRow")
            }
        }
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: "Savings timeline")
            ForEach(grouped, id: \.0) { month, items in
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    HStack {
                        Text(month).font(LeverFont.headline)
                        Spacer()
                        MoneyAmount(amount: items.map(\.amount).reduce(0, +), currencyCode: totals.currencyCode, size: .small, tint: LeverColor.money)
                    }
                    VStack(spacing: 0) {
                        ForEach(items) { event in
                            HStack(spacing: Spacing.sm) {
                                Image(systemName: event.kind.symbol).foregroundStyle(LeverColor.money).frame(width: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(event.title).font(LeverFont.callout)
                                    Text("\(event.kind.displayName) · \((event.confirmedAt ?? event.date).leverShort)").font(LeverFont.caption).foregroundStyle(LeverColor.inkSecondary)
                                }
                                Spacer()
                                MoneyAmount(amount: event.amount, currencyCode: event.currencyCode, size: .small)
                            }
                            .padding(.vertical, Spacing.xs)
                            if event.persistentModelID != items.last?.persistentModelID { Divider() }
                        }
                    }
                    .leverCard(padding: Spacing.sm)
                }
            }
        }
    }
}

/// Confirmation for a pending saving whose opportunity no longer exists.
struct PendingSavingSheet: View {
    @Environment(AppEnvironment.self) private var env
    let event: SavingsEvent
    let onDone: () -> Void

    var body: some View {
        BottomSheet(title: "Did you save \(Money.format(event.amount, code: event.currencyCode))?") {
            Text(event.title).font(LeverFont.callout).foregroundStyle(LeverColor.inkSecondary)
            Button("Yes, I saved it") { env.repository.confirmSaving(event); Haptics.savingConfirmed(); onDone() }.buttonStyle(.money)
            Button("No") { env.repository.rejectSaving(event); onDone() }.buttonStyle(.secondary)
        }
    }
}
