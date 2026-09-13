import SwiftUI

/// After a statement or Wallet sync: what LEVER read, and which recurring charges to start watching.
struct StatementReviewView: View {
    @Environment(AppEnvironment.self) private var env
    let transactions: [StatementTransaction]
    let source: String
    let statementText: String?
    let onDone: (Int) -> Void

    @State private var candidates: [RecurringCandidate] = []
    @State private var selected: Set<String> = []
    @State private var importing = false

    private var debits: [StatementTransaction] { transactions.filter(\.isDebit) }
    private var span: String {
        guard let first = transactions.map(\.date).min(), let last = transactions.map(\.date).max() else { return "" }
        return "\(first.leverShort) – \(last.leverShort)"
    }
    private var currency: String { transactions.first?.currencyCode ?? env.currencyCode }
    private var selectedAnnual: Decimal { candidates.filter { selected.contains($0.id) }.compactMap(\.annualCost).reduce(0, +) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("I read \(transactions.count) transactions.").font(LeverFont.display)
                    Text("\(span) · \(Money.format(debits.map(\.amount).reduce(0, +), code: currency)) spent · \(source)")
                        .font(LeverFont.caption).foregroundStyle(LeverColor.inkSecondary)
                }

                if candidates.isEmpty {
                    InsightBanner(symbol: "magnifyingglass", title: "No repeating charges found", message: "LEVER looks for the same merchant charging on a weekly, monthly, quarterly or yearly rhythm. Import a longer statement to catch more.", tint: LeverColor.inkSecondary)
                } else {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text("\(candidates.count) recurring charge\(candidates.count == 1 ? "" : "s") found")
                            .font(LeverFont.title3)
                        Text("Costing about \(Money.format(candidates.compactMap(\.annualCost).reduce(0, +), code: currency)) a year. Choose which to watch.")
                            .font(LeverFont.callout).foregroundStyle(LeverColor.inkSecondary)
                    }
                    VStack(spacing: Spacing.xs) {
                        ForEach(candidates) { candidate in
                            candidateRow(candidate)
                        }
                    }
                }

                DisclosureGroup {
                    VStack(spacing: 0) {
                        ForEach(debits.sorted { $0.date > $1.date }.prefix(40)) { t in
                            HStack {
                                Text(t.date.leverShort).font(LeverFont.caption).foregroundStyle(LeverColor.inkSecondary).frame(width: 84, alignment: .leading)
                                Text(t.merchantName).font(LeverFont.caption).lineLimit(1)
                                Spacer()
                                Text(Money.format(t.amount, code: t.currencyCode)).font(LeverFont.caption).monospacedDigit()
                            }
                            .padding(.vertical, 5)
                        }
                    }
                } label: {
                    Text("All debits").font(LeverFont.label).foregroundStyle(LeverColor.inkSecondary)
                }
                .leverCard(padding: Spacing.sm)

                VStack(spacing: Spacing.xs) {
                    Button {
                        importing = true
                        let chosen = candidates.filter { selected.contains($0.id) }
                        Task {
                            let created = await env.repository.importRecurringCharges(chosen, source: source, statementText: statementText)
                            importing = false
                            Haptics.scanSucceeded()
                            onDone(created.count)
                        }
                    } label: {
                        if importing { ProgressView().tint(LeverColor.background) }
                        else { Text(selected.isEmpty ? "Nothing to watch" : "Watch \(selected.count) subscription\(selected.count == 1 ? "" : "s") · \(Money.format(selectedAnnual, code: currency, compact: true))/yr") }
                    }
                    .buttonStyle(.money)
                    .disabled(selected.isEmpty || importing)
                    .accessibilityIdentifier("statementImportButton")
                    Button("Skip") { onDone(0) }.buttonStyle(.secondary)
                }
                Text("Individual transactions aren't stored — only the subscriptions you choose. The statement text stays on this iPhone.")
                    .font(.caption2).foregroundStyle(LeverColor.inkTertiary)
            }
            .padding(Spacing.md)
        }
        .leverScreenBackground()
        .navigationTitle("Statement")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            candidates = RecurringChargeDetector.detect(transactions)
            selected = Set(candidates.map(\.id))
        }
    }

    private func candidateRow(_ c: RecurringCandidate) -> some View {
        Button {
            if selected.contains(c.id) { selected.remove(c.id) } else { selected.insert(c.id) }
            Haptics.selection()
        } label: {
            HStack(spacing: Spacing.sm) {
                MerchantAvatar(name: c.merchantName, category: c.category, size: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text(c.merchantName).font(LeverFont.headline).foregroundStyle(LeverColor.ink)
                    Text("\(Money.format(c.latestAmount, code: c.currencyCode))\(c.cycle.shortSuffix) · seen \(c.occurrences)×\(c.nextDate.map { " · next \($0.leverShort)" } ?? "")")
                        .font(LeverFont.caption).foregroundStyle(LeverColor.inkSecondary)
                    if let prev = c.previousAmount, prev < c.latestAmount {
                        Text("Up from \(Money.format(prev, code: c.currencyCode))").font(.caption2.weight(.semibold)).foregroundStyle(LeverColor.opportunity)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    if let annual = c.annualCost { Text("\(Money.format(annual, code: c.currencyCode, compact: true))/yr").font(LeverFont.label).monospacedDigit() }
                    Image(systemName: selected.contains(c.id) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected.contains(c.id) ? LeverColor.money : LeverColor.inkTertiary)
                }
            }
            .leverCard(padding: Spacing.sm, radius: Radius.md)
        }
        .buttonStyle(.plain)
    }
}
