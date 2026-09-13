import SwiftUI
import SwiftData
import Charts

/// Where the money goes — from everything LEVER has seen (receipts, statements, UPI logs). Honest about scope.
struct SpendingView: View {
    @Environment(AppEnvironment.self) private var env
    @Query private var purchases: [Purchase]
    @State private var monthsBack = 0

    private var calendar: Calendar { .current }
    private var selectedMonthStart: Date { calendar.date(byAdding: .month, value: -monthsBack, to: DateMath.startOfMonth()) ?? .now }
    private var selectedMonthEnd: Date { calendar.date(byAdding: .month, value: 1, to: selectedMonthStart) ?? .now }

    private var inCurrency: [Purchase] { purchases.filter { $0.currencyCode == env.currencyCode && $0.purchaseDate != nil } }
    private var inMonth: [Purchase] { inCurrency.filter { ($0.purchaseDate ?? .distantPast) >= selectedMonthStart && ($0.purchaseDate ?? .distantPast) < selectedMonthEnd } }
    private var monthTotal: Decimal { inMonth.map(\.amount).reduce(0, +) }

    struct MonthBar: Identifiable { let id: Date; let label: String; let total: Double; let index: Int }
    private var months: [MonthBar] {
        (0..<6).reversed().compactMap { back in
            guard let start = calendar.date(byAdding: .month, value: -back, to: DateMath.startOfMonth()), let end = calendar.date(byAdding: .month, value: 1, to: start) else { return nil }
            let total = inCurrency.filter { ($0.purchaseDate ?? .distantPast) >= start && ($0.purchaseDate ?? .distantPast) < end }.map { NSDecimalNumber(decimal: $0.amount).doubleValue }.reduce(0, +)
            return MonthBar(id: start, label: start.formatted(.dateTime.month(.abbreviated)), total: total, index: back)
        }
    }

    struct Slice: Identifiable { let id: String; let amount: Decimal; let count: Int }
    private var byCategory: [Slice] {
        Dictionary(grouping: inMonth) { $0.merchantCategory.displayName }.map { Slice(id: $0.key, amount: $0.value.map(\.amount).reduce(0, +), count: $0.value.count) }.sorted { $0.amount > $1.amount }
    }
    private var byMerchant: [Slice] {
        Dictionary(grouping: inMonth) { $0.merchantName }.map { Slice(id: $0.key, amount: $0.value.map(\.amount).reduce(0, +), count: $0.value.count) }.sorted { $0.amount > $1.amount }
    }
    private var upiShare: Decimal { inMonth.filter { $0.paymentMethod?.uppercased().contains("UPI") ?? false }.map(\.amount).reduce(0, +) }
    private var recurringShare: Decimal { inMonth.filter { $0.subscription != nil }.map(\.amount).reduce(0, +) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(DateMath.monthTitle(for: selectedMonthStart).uppercased()).font(.caption2.weight(.bold)).tracking(1.1).foregroundStyle(LeverColor.inkSecondary)
                    MoneyAmount(amount: monthTotal, currencyCode: env.currencyCode, size: .hero)
                    Text("\(inMonth.count) payment\(inMonth.count == 1 ? "" : "s") LEVER has seen").font(LeverFont.callout).foregroundStyle(LeverColor.inkSecondary)
                }

                Chart(months) { m in
                    BarMark(x: .value("Month", m.label), y: .value("Spent", m.total))
                        .foregroundStyle(m.index == monthsBack ? LeverColor.ink : LeverColor.ink.opacity(0.25))
                        .cornerRadius(6)
                }
                .chartYAxis(.hidden)
                .chartXAxis { AxisMarks { _ in AxisValueLabel().font(.caption2).foregroundStyle(LeverColor.inkSecondary) } }
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        Rectangle().fill(.clear).contentShape(Rectangle()).onTapGesture { location in
                            let origin = geo[proxy.plotFrame!].origin
                            if let label: String = proxy.value(atX: location.x - origin.x), let m = months.first(where: { $0.label == label }) { withAnimation(Motion.gentle) { monthsBack = m.index } }
                        }
                    }
                }
                .frame(height: 140)
                .leverCard()

                if inMonth.isEmpty {
                    InsightBanner(symbol: "tray", title: "Nothing recorded for this month", message: "Scan receipts, log UPI payments with Scan & Pay, or import a statement and this fills in.", tint: LeverColor.inkSecondary)
                } else {
                    HStack(spacing: Spacing.xs) {
                        SavingsCard(title: "Recurring", amount: recurringShare, currencyCode: env.currencyCode, symbol: "arrow.triangle.2.circlepath")
                        SavingsCard(title: "UPI / QR", amount: upiShare, currencyCode: env.currencyCode, symbol: "qrcode")
                        SavingsCard(title: "Other", amount: monthTotal - recurringShare - upiShare, currencyCode: env.currencyCode, symbol: "creditcard")
                    }
                    breakdown("By category", byCategory)
                    breakdown("Top merchants", Array(byMerchant.prefix(8)))
                }
                Text("Only what LEVER has captured — not your whole bank account. The more you scan, log and import, the truer this gets.")
                    .font(.caption2).foregroundStyle(LeverColor.inkTertiary)
            }
            .padding(Spacing.md)
        }
        .leverScreenBackground()
        .navigationTitle("Spending")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func breakdown(_ title: String, _ slices: [Slice]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            SectionHeader(title: title)
            VStack(spacing: Spacing.sm) {
                ForEach(slices) { s in
                    let fraction = monthTotal > 0 ? NSDecimalNumber(decimal: s.amount / monthTotal).doubleValue : 0
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            if title == "Top merchants" { MerchantAvatar(name: s.id, size: 24) }
                            Text(s.id).font(LeverFont.callout)
                            Text("· \(s.count)").font(LeverFont.caption).foregroundStyle(LeverColor.inkTertiary)
                            Spacer()
                            Text(Money.format(s.amount, code: env.currencyCode, compact: true)).font(LeverFont.label).monospacedDigit()
                            Text("\(Int((fraction * 100).rounded()))%").font(LeverFont.caption).foregroundStyle(LeverColor.inkSecondary).frame(width: 36, alignment: .trailing)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(LeverColor.surfaceElevated)
                                Capsule().fill(LeverColor.ink.opacity(0.75)).frame(width: max(4, geo.size.width * fraction))
                            }
                        }
                        .frame(height: 5)
                    }
                }
            }
            .leverCard()
        }
    }
}
