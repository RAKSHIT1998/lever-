import SwiftUI

struct SectionHeader: View {
    let title: String
    var action: (() -> Void)? = nil
    var actionTitle: String = "See all"

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased())
                .font(.caption.weight(.bold))
                .tracking(1.1)
                .foregroundStyle(LeverColor.inkSecondary)
            Spacer()
            if let action {
                Button(actionTitle, action: action)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LeverColor.ink)
            }
        }
        .padding(.horizontal, Spacing.xxs)
    }
}

struct EmptyState: View {
    let symbol: String
    let title: String
    var message: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(LeverColor.inkTertiary)
                .padding(.bottom, Spacing.xs)
            Text(title)
                .font(LeverFont.title)
                .multilineTextAlignment(.center)
                .foregroundStyle(LeverColor.ink)
            if let message {
                Text(message)
                    .font(LeverFont.callout)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(LeverColor.inkSecondary)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.primary)
                    .padding(.top, Spacing.xs)
            }
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity)
    }
}

struct InsightBanner: View {
    let symbol: String
    let title: String
    var message: String? = nil
    var tint: Color = LeverColor.info

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .font(.body.weight(.semibold))
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(LeverFont.headline).foregroundStyle(LeverColor.ink)
                if let message {
                    Text(message).font(LeverFont.callout).foregroundStyle(LeverColor.inkSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Spacing.md)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }
}

struct KeyValueRow: View {
    let key: String
    let value: String
    var confidence: Confidence? = nil
    var mono = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(key).font(LeverFont.callout).foregroundStyle(LeverColor.inkSecondary)
            Spacer()
            HStack(spacing: 6) {
                if let confidence, confidence != .high {
                    Circle().fill(LeverColor.confidence(confidence)).frame(width: 6, height: 6)
                        .accessibilityLabel(confidence.displayName)
                }
                Text(value)
                    .font(mono ? LeverFont.mono : LeverFont.callout.weight(.medium))
                    .foregroundStyle(LeverColor.ink)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(.vertical, 6)
    }
}

struct CheckRow: View {
    let text: String
    var done = true

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? LeverColor.money : LeverColor.inkTertiary)
            Text(text).font(LeverFont.callout).foregroundStyle(LeverColor.ink)
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

struct LoadingSteps: View {
    let steps: [String]
    let currentIndex: Int

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(spacing: Spacing.sm) {
                    Group {
                        if index < currentIndex {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(LeverColor.money)
                        } else if index == currentIndex {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "circle").foregroundStyle(LeverColor.inkTertiary)
                        }
                    }
                    .frame(width: 20)
                    Text(step)
                        .font(LeverFont.callout)
                        .foregroundStyle(index <= currentIndex ? LeverColor.ink : LeverColor.inkTertiary)
                }
                .animation(Motion.gentle, value: currentIndex)
            }
        }
    }
}
