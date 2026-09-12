import SwiftUI

struct ConfidenceBadge: View {
    let confidence: Confidence

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(LeverColor.confidence(confidence)).frame(width: 6, height: 6)
            Text(confidence.displayName)
        }
        .font(LeverFont.caption)
        .foregroundStyle(LeverColor.inkSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(LeverColor.surfaceElevated, in: Capsule())
        .accessibilityLabel(confidence.displayName)
    }
}

struct DeadlineBadge: View {
    let date: Date
    var prefix: String = ""

    private var days: Int { DateMath.days(from: .now, to: date) }

    private var tint: Color {
        switch days {
        case ..<0: LeverColor.inkTertiary
        case 0...2: LeverColor.urgent
        case 3...7: LeverColor.opportunity
        default: LeverColor.inkSecondary
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "clock")
            Text("\(prefix)\(DateMath.relativePhrase(to: date))")
        }
        .font(LeverFont.caption)
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tint.opacity(0.12), in: Capsule())
    }
}

struct LaneTag: View {
    let lane: OpportunityLane

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(LeverColor.lane(lane)).frame(width: 8, height: 8)
            Text(lane.displayName.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(0.8)
                .foregroundStyle(LeverColor.inkSecondary)
        }
    }
}

struct EvidenceKindTag: View {
    let kind: EvidenceKind

    var body: some View {
        Label(kind.displayName, systemImage: kind.symbol)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(LeverColor.inkSecondary)
            .labelStyle(.titleAndIcon)
    }
}
