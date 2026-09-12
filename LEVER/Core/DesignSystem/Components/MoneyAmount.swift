import SwiftUI

struct MoneyAmount: View {
    enum Size { case hero, large, medium, small }

    let amount: Decimal
    let currencyCode: String
    var size: Size = .medium
    var tint: Color = LeverColor.ink
    var compact = false

    private var font: Font {
        switch size {
        case .hero: LeverFont.hero()
        case .large: LeverFont.hero(34)
        case .medium: .system(.title3, design: .rounded).weight(.semibold)
        case .small: .system(.subheadline, design: .rounded).weight(.semibold)
        }
    }

    var body: some View {
        Text(Money.format(amount, code: currencyCode, compact: compact))
            .font(font)
            .foregroundStyle(tint)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .contentTransition(.numericText())
            .accessibilityLabel(Money.format(amount, code: currencyCode))
    }
}
