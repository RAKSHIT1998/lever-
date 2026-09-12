import SwiftUI

/// LEVER's visual language: warm off-white paper, deep ink, one confident green for money, restrained signals.
enum LeverColor {
    static let background = Color(light: Color(red: 0.970, green: 0.975, blue: 0.980), dark: Color(red: 0.055, green: 0.060, blue: 0.070))
    static let surface = Color(light: .white, dark: Color(red: 0.105, green: 0.110, blue: 0.125))
    static let surfaceElevated = Color(light: Color(red: 0.955, green: 0.960, blue: 0.968), dark: Color(red: 0.150, green: 0.155, blue: 0.170))
    static let ink = Color(light: Color(red: 0.08, green: 0.09, blue: 0.11), dark: Color(red: 0.95, green: 0.95, blue: 0.96))
    static let inkSecondary = Color(light: Color(red: 0.42, green: 0.44, blue: 0.48), dark: Color(red: 0.62, green: 0.64, blue: 0.68))
    static let inkTertiary = Color(light: Color(red: 0.62, green: 0.64, blue: 0.68), dark: Color(red: 0.42, green: 0.44, blue: 0.48))
    static let hairline = Color(light: Color.black.opacity(0.07), dark: Color.white.opacity(0.09))
    static let inkPanelTop = Color(light: Color(red: 0.12, green: 0.13, blue: 0.16), dark: Color(red: 0.16, green: 0.17, blue: 0.20))
    static let inkPanelBottom = Color(light: Color(red: 0.06, green: 0.07, blue: 0.09), dark: Color(red: 0.09, green: 0.10, blue: 0.12))
    static let onInk = Color(red: 0.96, green: 0.96, blue: 0.95)
    static let onInkSecondary = Color(red: 0.96, green: 0.96, blue: 0.95).opacity(0.62)

    /// Money green — the only saturated brand colour.
    static let money = Color(light: Color(red: 0.11, green: 0.60, blue: 0.30), dark: Color(red: 0.30, green: 0.85, blue: 0.48))
    static let moneySoft = Color(light: Color(red: 0.11, green: 0.60, blue: 0.30).opacity(0.10), dark: Color(red: 0.30, green: 0.85, blue: 0.48).opacity(0.14))

    static let urgent = Color(light: Color(red: 0.86, green: 0.22, blue: 0.20), dark: Color(red: 1.0, green: 0.42, blue: 0.38))
    static let opportunity = Color(light: Color(red: 0.93, green: 0.50, blue: 0.12), dark: Color(red: 1.0, green: 0.62, blue: 0.28))
    static let protection = Color(light: Color(red: 0.82, green: 0.66, blue: 0.10), dark: Color(red: 0.98, green: 0.80, blue: 0.30))
    static let info = Color(light: Color(red: 0.20, green: 0.42, blue: 0.85), dark: Color(red: 0.45, green: 0.62, blue: 1.0))

    static func lane(_ lane: OpportunityLane) -> Color {
        switch lane {
        case .urgent: urgent
        case .opportunity: opportunity
        case .protection: protection
        }
    }

    static func confidence(_ confidence: Confidence) -> Color {
        switch confidence {
        case .high: money
        case .medium: opportunity
        case .low: inkTertiary
        }
    }
}

extension Color {
    init(light: Color, dark: Color) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }
}

enum Spacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
}

enum Radius {
    static let sm: CGFloat = 12
    static let md: CGFloat = 18
    static let lg: CGFloat = 24
    static let pill: CGFloat = 999
}

enum LeverFont {
    /// Hero money numbers — rounded, tight, unmistakable.
    static func hero(_ size: CGFloat = 52) -> Font { .system(size: size, weight: .bold, design: .rounded) }
    static let display = Font.system(.largeTitle, design: .rounded).weight(.bold)
    static let title = Font.system(.title2, design: .rounded).weight(.semibold)
    static let title3 = Font.system(.title3, design: .rounded).weight(.semibold)
    static let headline = Font.system(.headline, design: .default).weight(.semibold)
    static let body = Font.system(.body)
    static let callout = Font.system(.callout)
    static let caption = Font.system(.caption).weight(.medium)
    static let label = Font.system(.footnote).weight(.semibold)
    static let mono = Font.system(.footnote, design: .monospaced)
}

struct LeverCardStyle: ViewModifier {
    var padding: CGFloat = Spacing.md
    var elevated = false
    var radius: CGFloat = Radius.lg
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(elevated ? LeverColor.surfaceElevated : LeverColor.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(LeverColor.hairline, lineWidth: 1))
            // Soft, wide shadow in light mode gives paper-like depth; dark mode relies on surface contrast.
            .shadow(color: scheme == .dark ? .clear : Color.black.opacity(0.05), radius: 18, y: 8)
            .shadow(color: scheme == .dark ? .clear : Color.black.opacity(0.03), radius: 2, y: 1)
    }
}

/// Deep ink panel used for the Home hero — the one place LEVER goes dark-on-light for emphasis.
struct InkPanelStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(Spacing.lg)
            .background(
                LinearGradient(colors: [LeverColor.inkPanelTop, LeverColor.inkPanelBottom], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            )
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.18), radius: 24, y: 12)
    }
}

extension View {
    func leverCard(padding: CGFloat = Spacing.md, elevated: Bool = false, radius: CGFloat = Radius.lg) -> some View {
        modifier(LeverCardStyle(padding: padding, elevated: elevated, radius: radius))
    }

    func inkPanel() -> some View { modifier(InkPanelStyle()) }

    func leverScreenBackground() -> some View {
        background(LeverColor.background.ignoresSafeArea())
    }
}

/// Subtle motion — LEVER animates like a well-made instrument, not a game.
enum Motion {
    static let snappy = Animation.spring(response: 0.35, dampingFraction: 0.85)
    static let gentle = Animation.easeOut(duration: 0.25)
    static let reveal = Animation.spring(response: 0.6, dampingFraction: 0.8)
}


/// Cards fade/slide in one after another on first appearance — quiet, not showy.
struct StaggeredAppear: ViewModifier {
    let index: Int
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 14)
            .onAppear {
                guard !shown else { return }
                withAnimation(Motion.reveal.delay(Double(min(index, 5)) * 0.06)) { shown = true }
            }
    }
}

extension View {
    func staggeredAppear(index: Int) -> some View { modifier(StaggeredAppear(index: index)) }
}
