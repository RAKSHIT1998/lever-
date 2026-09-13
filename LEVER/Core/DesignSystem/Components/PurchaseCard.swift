import SwiftUI

/// The Vault card: identity, amount, and the one thing that matters next about this purchase.
struct PurchaseCard: View {
    let purchase: Purchase

    private var nextEvent: (String, Date, Color)? {
        let now = Date.now
        var events: [(String, Date, Color)] = []
        if let d = purchase.returnWindow?.deadline, d >= now { events.append(("Return closes", d, LeverColor.urgent)) }
        if let s = purchase.subscription, s.status != .cancelled, let d = s.nextBillingDate, d >= now { events.append(("Renews", d, LeverColor.opportunity)) }
        for w in purchase.warranties { if let d = w.endDate, d >= now { events.append(("Warranty ends", d, LeverColor.protection)) } }
        return events.min { $0.1 < $1.1 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .top, spacing: Spacing.sm) {
                MerchantAvatar(name: purchase.merchantName, category: purchase.merchantCategory, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(purchase.title).font(LeverFont.headline).foregroundStyle(LeverColor.ink).lineLimit(2)
                    Text([purchase.merchantName, purchase.purchaseDate?.leverShort].compactMap { $0 }.joined(separator: " · "))
                        .font(LeverFont.caption).foregroundStyle(LeverColor.inkSecondary).lineLimit(1)
                }
                Spacer(minLength: Spacing.xs)
                VStack(alignment: .trailing, spacing: 2) {
                    MoneyAmount(amount: purchase.amount, currencyCode: purchase.currencyCode, size: .medium)
                    if let s = purchase.subscription { Text(s.billingCycle.shortSuffix.replacingOccurrences(of: "/", with: "per ")).font(.caption2).foregroundStyle(LeverColor.inkTertiary) }
                }
            }
            // At most two chips so nothing truncates: the next thing that matters, then money.
            let chips = chipModels
            if !chips.isEmpty {
                HStack(spacing: 6) {
                    ForEach(chips.prefix(2), id: \.text) { c in chip(symbol: c.symbol, text: c.text, tint: c.tint) }
                    Spacer(minLength: 0)
                }
            }
        }
        .leverCard(padding: Spacing.md, radius: Radius.lg)
        .contentShape(RoundedRectangle(cornerRadius: Radius.lg))
        .accessibilityElement(children: .combine)
    }

    private struct ChipModel { let symbol: String; let text: String; let tint: Color }

    private var chipModels: [ChipModel] {
        var out: [ChipModel] = []
        if let (label, date, tint) = nextEvent { out.append(.init(symbol: "clock", text: "\(label) \(DateMath.relativePhrase(to: date))", tint: tint)) }
        if purchase.potentialSavings > 0 {
            out.append(.init(symbol: "sparkles", text: "\(Money.format(purchase.potentialSavings, code: purchase.currencyCode, compact: true)) possible", tint: LeverColor.money))
        } else if purchase.hasActiveProtection && nextEvent == nil {
            out.append(.init(symbol: "shield.fill", text: "Protected", tint: LeverColor.inkSecondary))
        }
        if purchase.sharedBy != nil || purchase.householdID != nil {
            out.append(.init(symbol: "person.2.fill", text: purchase.sharedBy.map { "From \($0)" } ?? "Family", tint: LeverColor.info))
        }
        if out.isEmpty { out.append(.init(symbol: purchase.documentType.symbol, text: purchase.documentType.displayName, tint: LeverColor.inkTertiary)) }
        return out
    }

    private func chip(symbol: String, text: String, tint: Color) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(tint.opacity(0.10), in: Capsule())
            .lineLimit(1)
    }
}

/// Square quick-action card used on Home.
struct QuickActionCard: View {
    let symbol: String
    let title: String
    let subtitle: String
    var tint: Color = LeverColor.ink
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(tint.opacity(tint == LeverColor.ink ? 1 : 0.12))
                    Image(systemName: symbol).font(.body.weight(.semibold)).foregroundStyle(tint == LeverColor.ink ? LeverColor.background : tint)
                }
                .frame(width: 34, height: 34)
                Spacer(minLength: 0)
                Text(title).font(LeverFont.headline).foregroundStyle(LeverColor.ink).lineLimit(1)
                Text(subtitle).font(.caption2).foregroundStyle(LeverColor.inkSecondary).lineLimit(2).multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, minHeight: 118, alignment: .leading)
            .leverCard(padding: Spacing.sm, radius: Radius.md)
        }
        .buttonStyle(.plain)
    }
}
