import SwiftUI

/// The Home feed card. Merchant identity, plain-language title, one number, one action.
struct OpportunityCard: View {
    let opportunity: Opportunity
    let action: () -> Void

    private var lane: OpportunityLane { opportunity.lane }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                MerchantMonogram(name: opportunity.merchantName, category: opportunity.purchase?.merchantCategory ?? .other, size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(opportunity.merchantName)
                        .font(LeverFont.headline).foregroundStyle(LeverColor.ink).lineLimit(1)
                    LaneTag(lane: lane)
                }
                Spacer()
                if let deadline = opportunity.deadline {
                    DeadlineBadge(date: deadline)
                }
            }

            Text(opportunity.title)
                .font(LeverFont.title3)
                .foregroundStyle(LeverColor.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)

            Text(opportunity.detail)
                .font(LeverFont.callout)
                .foregroundStyle(LeverColor.inkSecondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            Divider().padding(.vertical, Spacing.xxs)

            HStack(alignment: .lastTextBaseline) {
                if let savings = opportunity.estimatedSavings, savings > 0 {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(savingsLabel)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(LeverColor.inkSecondary)
                        MoneyAmount(amount: savings, currencyCode: opportunity.currencyCode, size: .large, tint: lane == .urgent ? LeverColor.ink : LeverColor.money)
                    }
                } else {
                    ConfidenceBadge(confidence: opportunity.confidence)
                }
                Spacer()
                Button(actionTitle, action: action)
                    .buttonStyle(.compact(LeverColor.lane(lane)))
            }
        }
        .leverCard(padding: Spacing.lg)
        .contentShape(RoundedRectangle(cornerRadius: Radius.lg))
        .onTapGesture(perform: action)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private var savingsLabel: String {
        switch opportunity.type {
        case .priceDrop, .refund, .travelPriceChange, .claimOpportunity: "Potential recovery"
        case .resale: "Value at risk of eroding"
        case .returnDeadline: "Money at stake"
        case .warrantyExpiration, .purchaseProtection, .insuranceOpportunity: "Value protected"
        default: "Potential saving"
        }
    }

    private var actionTitle: String {
        switch opportunity.type {
        case .subscriptionRenewal, .negotiation, .feeDetection, .duplicateCharge: "Fix it"
        case .priceDrop, .travelPriceChange, .cheaperAlternative, .refund: "Check options"
        case .warrantyExpiration: "Open warranty"
        case .returnDeadline: "Protect it"
        case .resale: "See estimate"
        default: "Review"
        }
    }
}

struct SavingsCard: View {
    let title: String
    let amount: Decimal
    let currencyCode: String
    var tint: Color = LeverColor.ink
    var symbol: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                if let symbol {
                    Image(systemName: symbol).font(.caption2.weight(.semibold)).foregroundStyle(tint == LeverColor.ink ? LeverColor.inkTertiary : tint)
                }
                Text(title.uppercased())
                    .font(.caption2.weight(.bold)).tracking(0.6)
                    .foregroundStyle(LeverColor.inkSecondary)
            }
            MoneyAmount(amount: amount, currencyCode: currencyCode, size: .medium, tint: tint, compact: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .leverCard(padding: Spacing.sm, radius: Radius.md)
    }
}

struct PurchaseRow: View {
    let purchase: Purchase

    var body: some View {
        HStack(spacing: Spacing.sm) {
            MerchantMonogram(name: purchase.merchantName, category: purchase.merchantCategory, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(purchase.title)
                    .font(LeverFont.headline)
                    .foregroundStyle(LeverColor.ink)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(purchase.merchantName)
                    if let date = purchase.purchaseDate {
                        Text("·")
                        Text(date.leverShort)
                    }
                }
                .font(LeverFont.caption)
                .foregroundStyle(LeverColor.inkSecondary)
                .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                MoneyAmount(amount: purchase.amount, currencyCode: purchase.currencyCode, size: .small)
                if purchase.potentialSavings > 0 {
                    Text("+\(Money.format(purchase.potentialSavings, code: purchase.currencyCode, compact: true)) possible")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(LeverColor.money)
                } else if purchase.hasActiveProtection {
                    Label("Protected", systemImage: "shield.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(LeverColor.inkTertiary)
                } else if let sub = purchase.subscription {
                    Text(sub.billingCycle.displayName)
                        .font(.caption2)
                        .foregroundStyle(LeverColor.inkTertiary)
                }
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

struct DocumentThumbnail: View {
    let purchase: Purchase
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(LeverColor.surfaceElevated)
            Image(systemName: symbol)
                .font(.system(size: size * 0.4, weight: .medium))
                .foregroundStyle(LeverColor.inkSecondary)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var symbol: String {
        switch purchase.merchantCategory {
        case .electronics: "laptopcomputer"
        case .streaming: "play.rectangle.fill"
        case .software: "app.badge"
        case .travel: "airplane"
        case .insurance: "umbrella.fill"
        case .utilities: "bolt.fill"
        case .telecom: "antenna.radiowaves.left.and.right"
        case .fashion: "tshirt.fill"
        case .home: "house.fill"
        case .automotive: "car.fill"
        case .health: "heart.fill"
        case .groceries: "cart.fill"
        case .retail, .other: purchase.documentType.symbol
        }
    }
}

struct LeverCard<Content: View>: View {
    var title: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if let title {
                Text(title).font(LeverFont.headline).foregroundStyle(LeverColor.ink)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .leverCard()
    }
}

struct BottomSheet<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(title).font(LeverFont.title).foregroundStyle(LeverColor.ink)
            content
        }
        .padding(Spacing.lg)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(LeverColor.background)
    }
}
