import SwiftUI

/// The moment after a first scan: "I FOUND SOMETHING." — then the specific loss LEVER can prevent.
struct MagicMomentView: View {
    let purchase: Purchase
    let opportunities: [Opportunity]
    let onDone: () -> Void

    @State private var revealed = false
    @State private var showDetail: Opportunity?

    private var headline: Opportunity? { opportunities.first }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Spacer()
            if let headline {
                Text("I found something.")
                    .font(LeverFont.hero(40))
                    .foregroundStyle(LeverColor.ink)
                    .accessibilityIdentifier("magicHeadline")
                if revealed {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        LaneTag(lane: headline.lane)
                        Text(headline.title)
                            .font(LeverFont.title)
                            .fixedSize(horizontal: false, vertical: true)
                        if let amount = headline.estimatedSavings, amount > 0 {
                            Text(headline.type == .returnDeadline ? "Potential loss" : "Potential saving")
                                .font(LeverFont.caption).foregroundStyle(LeverColor.inkSecondary)
                            MoneyAmount(amount: amount, currencyCode: headline.currencyCode, size: .hero, tint: headline.type == .returnDeadline ? LeverColor.urgent : LeverColor.money)
                        }
                        Text(headline.detail).font(LeverFont.callout).foregroundStyle(LeverColor.inkSecondary)
                        if opportunities.count > 1 {
                            Text("+ \(opportunities.count - 1) more found")
                                .font(LeverFont.label).foregroundStyle(LeverColor.inkSecondary)
                        }
                    }
                    .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
                }
            } else {
                Text("Saved and protected.")
                    .font(LeverFont.hero(40))
                if revealed {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text(purchase.title).font(LeverFont.title)
                        MoneyAmount(amount: purchase.amount, currencyCode: purchase.currencyCode, size: .large)
                        Text("No money leak yet. LEVER will keep checking this purchase for deadlines, renewals and price drops.")
                            .font(LeverFont.callout).foregroundStyle(LeverColor.inkSecondary)
                        VStack(alignment: .leading, spacing: 0) {
                            CheckRow(text: "Receipt stored on this iPhone")
                            CheckRow(text: "Deadlines checked")
                            CheckRow(text: purchase.warranties.isEmpty ? "No warranty found in document" : "Warranty tracked", done: !purchase.warranties.isEmpty)
                        }
                    }
                    .transition(.opacity)
                }
            }
            Spacer()
            if revealed {
                VStack(spacing: Spacing.xs) {
                    if let headline {
                        Button(headline.type == .returnDeadline ? "Protect my purchase" : "Show me how") { showDetail = headline }
                            .buttonStyle(.money)
                            .accessibilityIdentifier("magicPrimaryButton")
                    }
                    Button(headline == nil ? "Done" : "Later", action: onDone)
                        .buttonStyle(.secondary)
                        .accessibilityIdentifier("magicDoneButton")
                }
            }
        }
        .padding(Spacing.lg)
        .task {
            try? await Task.sleep(for: .milliseconds(650))
            withAnimation(Motion.reveal) { revealed = true }
        }
        .navigationDestination(item: $showDetail) { opportunity in
            OpportunityDetailView(opportunity: opportunity, onFinished: onDone)
        }
    }
}
