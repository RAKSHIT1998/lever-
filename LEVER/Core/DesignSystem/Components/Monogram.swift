import SwiftUI

/// Merchant identity without logos: a tinted disc with the merchant's initials. Deterministic colour per name.
struct MerchantMonogram: View {
    let name: String
    var category: MerchantCategory = .other
    var size: CGFloat = 40

    private var initials: String {
        let words = name.split(separator: " ").filter { $0.first?.isLetter ?? false }
        if words.count >= 2, let a = words[0].first, let b = words[1].first { return String([a, b]).uppercased() }
        return String(name.prefix(1)).uppercased()
    }

    private var tint: Color {
        switch category {
        case .streaming: Color(red: 0.86, green: 0.25, blue: 0.30)
        case .software: Color(red: 0.36, green: 0.42, blue: 0.90)
        case .electronics: Color(red: 0.20, green: 0.24, blue: 0.30)
        case .travel: Color(red: 0.13, green: 0.55, blue: 0.75)
        case .insurance: Color(red: 0.45, green: 0.35, blue: 0.70)
        case .telecom: Color(red: 0.90, green: 0.35, blue: 0.15)
        case .utilities: Color(red: 0.85, green: 0.62, blue: 0.10)
        case .fashion: Color(red: 0.75, green: 0.30, blue: 0.55)
        case .groceries: Color(red: 0.25, green: 0.60, blue: 0.35)
        case .home: Color(red: 0.55, green: 0.45, blue: 0.30)
        case .automotive: Color(red: 0.30, green: 0.35, blue: 0.40)
        case .health: Color(red: 0.90, green: 0.40, blue: 0.40)
        case .retail, .other: Self.stableHueColor(for: name)
        }
    }

    /// Deterministic across launches (String.hashValue is randomly seeded per process).
    private static func stableHueColor(for name: String) -> Color {
        let sum = name.lowercased().unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return Color(hue: Double(sum % 360) / 360, saturation: 0.45, brightness: 0.55)
    }

    var body: some View {
        ZStack {
            Circle().fill(tint.opacity(0.14))
            Circle().strokeBorder(tint.opacity(0.25), lineWidth: 1)
            Text(initials)
                .font(.system(size: size * 0.36, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Compact metric used in hero panels and summary rows.
struct HeroStat: View {
    let label: String
    let value: String
    var onInk = true

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.caption2.weight(.bold)).tracking(0.8)
                .foregroundStyle(onInk ? LeverColor.onInkSecondary : LeverColor.inkSecondary)
            Text(value)
                .font(.system(.callout, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(onInk ? LeverColor.onInk : LeverColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// "On-device · Private" style reassurance chip.
struct TrustChip: View {
    let symbol: String
    let text: String

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(LeverColor.inkSecondary)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(LeverColor.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(LeverColor.hairline))
    }
}
