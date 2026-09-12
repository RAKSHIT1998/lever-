import SwiftUI
import StoreKit

/// Shown only after value: free captures used and LEVER has found something. Prices come from StoreKit.
struct PaywallView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Product?
    @State private var purchasing = false
    @State private var message: String?

    private var found: Decimal {
        env.repository.openOpportunities().filter(\.countsAsPotentialSaving).compactMap(\.estimatedSavings).reduce(0, +)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        if found > 0 {
                            Text("LEVER found").font(LeverFont.callout).foregroundStyle(LeverColor.inkSecondary)
                            MoneyAmount(amount: found, currencyCode: env.currencyCode, size: .hero, tint: LeverColor.money)
                            Text("in potential savings across your captures. Unlock continuous protection.").font(LeverFont.body).foregroundStyle(LeverColor.inkSecondary)
                        } else {
                            Text("Unlock continuous protection.").font(LeverFont.display)
                            Text("LEVER keeps watching every purchase you add — for as long as you own it.").font(LeverFont.body).foregroundStyle(LeverColor.inkSecondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        ForEach(["Unlimited captures", "Money leak detection", "Price monitoring", "AI negotiations", "Advanced claim generation", "Family vault (coming)", "Savings history"], id: \.self) { item in
                            HStack(spacing: Spacing.sm) {
                                Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(LeverColor.money)
                                Text(item).font(LeverFont.callout)
                            }
                        }
                    }
                    .leverCard()

                    if env.store.products.isEmpty {
                        if env.store.isLoading { ProgressView().frame(maxWidth: .infinity) }
                        else {
                            VStack(spacing: Spacing.xs) {
                                Text(env.store.lastError ?? "Products aren't available right now.").font(LeverFont.callout).foregroundStyle(LeverColor.inkSecondary)
                                Button("Try again") { Task { await env.store.load() } }.buttonStyle(.secondary)
                            }
                        }
                    } else {
                        VStack(spacing: Spacing.xs) {
                            ForEach(env.store.products, id: \.id) { product in
                                ProductRow(product: product, isSelected: selected?.id == product.id, badge: product.id == ProProduct.yearly.rawValue ? "Best value" : nil) { selected = product }
                            }
                        }
                    }

                    if let message { Text(message).font(LeverFont.caption).foregroundStyle(LeverColor.inkSecondary) }

                    VStack(spacing: Spacing.xs) {
                        Button {
                            guard let selected else { return }
                            purchasing = true
                            Task {
                                let outcome = await env.store.purchase(selected)
                                purchasing = false
                                switch outcome {
                                case .success:
                                    env.analytics.track(selected.subscription?.introductoryOffer != nil ? .trialStarted : .subscriptionStarted, properties: ["product": selected.id])
                                    Haptics.savingConfirmed()
                                    dismiss()
                                case .pending: message = "Purchase pending approval."
                                case .cancelled: break
                                case .failed(let error): message = error
                                }
                            }
                        } label: {
                            if purchasing { ProgressView().tint(.white) } else { Text("Start LEVER Pro") }
                        }
                        .buttonStyle(.money)
                        .disabled(selected == nil || purchasing)
                        .accessibilityIdentifier("paywallStartButton")
                        if let selected {
                            Text(env.store.renewalDescription(for: selected))
                                .font(.caption2).foregroundStyle(LeverColor.inkTertiary).multilineTextAlignment(.center).frame(maxWidth: .infinity)
                        }
                        Button("Continue free") { dismiss() }.buttonStyle(.secondary).accessibilityIdentifier("paywallContinueFree")
                        HStack {
                            Button("Restore purchases") { Task { await env.store.restore(); if env.store.isPro { dismiss() } } }
                            Text("·")
                            if let terms = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/") {
                                Link("Terms", destination: terms)
                            }
                        }
                        .font(LeverFont.caption).foregroundStyle(LeverColor.inkSecondary).frame(maxWidth: .infinity)
                    }
                    Text("Subscriptions renew automatically unless cancelled at least 24 hours before the end of the period. Manage or cancel anytime in your App Store settings.")
                        .font(.caption2).foregroundStyle(LeverColor.inkTertiary)
                }
                .padding(Spacing.md)
            }
            .leverScreenBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Close") { dismiss() } } }
            .task {
                env.analytics.track(.paywallViewed)
                if env.store.products.isEmpty { await env.store.load() }
                selected = env.store.product(.yearly) ?? env.store.products.first
            }
        }
    }
}

struct ProductRow: View {
    let product: Product
    let isSelected: Bool
    var badge: String?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(product.displayName).font(LeverFont.headline).foregroundStyle(LeverColor.ink)
                        if let badge { Text(badge.uppercased()).font(.caption2.weight(.bold)).padding(.horizontal, 6).padding(.vertical, 2).background(LeverColor.moneySoft, in: Capsule()).foregroundStyle(LeverColor.money) }
                    }
                    Text(product.description).font(LeverFont.caption).foregroundStyle(LeverColor.inkSecondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(product.displayPrice).font(.system(.title3, design: .rounded).weight(.semibold)).foregroundStyle(LeverColor.ink)
                    if let period = product.subscription?.subscriptionPeriod {
                        Text(period.unit == .year ? "per year" : period.unit == .month ? "per month" : "per period").font(.caption2).foregroundStyle(LeverColor.inkTertiary)
                    } else { Text("one time").font(.caption2).foregroundStyle(LeverColor.inkTertiary) }
                }
            }
            .padding(Spacing.md)
            .background(LeverColor.surface, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(isSelected ? LeverColor.ink : LeverColor.hairline, lineWidth: isSelected ? 2 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
