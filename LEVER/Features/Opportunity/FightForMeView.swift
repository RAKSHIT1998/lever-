import SwiftUI

/// Signature feature: LEVER assembles strategy, evidence, message and expected savings. The user approves each send.
struct FightForMeView: View {
    @Environment(AppEnvironment.self) private var env
    let opportunity: Opportunity
    let plan: ActionPlan
    let onResolved: () -> Void

    @State private var approved = false
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text("Your case is ready.").font(LeverFont.display)
                        Text("Nothing has been sent. Review, then act with one tap.").font(LeverFont.callout).foregroundStyle(LeverColor.inkSecondary)
                    }

                    section("Strategy") {
                        Text(plan.summary).font(LeverFont.headline)
                        ForEach(Array(plan.steps.enumerated()), id: \.offset) { index, step in
                            Text("\(index + 1). \(step)").font(LeverFont.callout)
                        }
                    }

                    section("Evidence") {
                        ForEach(opportunity.evidence, id: \.persistentModelID) { item in
                            HStack(alignment: .top, spacing: Spacing.xs) {
                                Image(systemName: item.kind.symbol).foregroundStyle(LeverColor.inkSecondary).frame(width: 18)
                                Text(item.statement).font(LeverFont.callout)
                            }
                        }
                    }

                    if let savings = plan.estimatedSavings ?? opportunity.estimatedSavings, savings > 0 {
                        section("Expected outcome") {
                            MoneyAmount(amount: savings, currencyCode: opportunity.currencyCode, size: .large, tint: LeverColor.money)
                            Text("Potential — counted only when you confirm it happened.").font(LeverFont.caption).foregroundStyle(LeverColor.inkSecondary)
                        }
                    }

                    if let message = plan.messageDraft {
                        section("Message") {
                            Text(message).font(LeverFont.callout).textSelection(.enabled)
                        }
                    }

                    if let deadline = plan.deadline ?? opportunity.deadline {
                        InsightBanner(symbol: "clock.fill", title: "Act before \(deadline.leverMedium)", message: DateMath.relativePhrase(to: deadline).capitalized, tint: LeverColor.urgent)
                    }

                    Toggle(isOn: $approved) {
                        Text("I've reviewed this and approve LEVER preparing it for me.").font(LeverFont.callout)
                    }
                    .tint(LeverColor.money)
                    .accessibilityIdentifier("fightApproveToggle")

                    VStack(spacing: Spacing.xs) {
                        if let message = plan.messageDraft {
                            Button(copied ? "Message copied" : "Copy message") {
                                UIPasteboard.general.string = message
                                copied = true
                                Haptics.actionCompleted()
                            }
                            .buttonStyle(.primary).disabled(!approved)
                            ShareLink(item: message) { Text("Share message").frame(maxWidth: .infinity) }
                                .buttonStyle(.secondary).disabled(!approved)
                            if let mail = mailURL(body: message) {
                                Link(destination: mail) { Text("Open in Mail").frame(maxWidth: .infinity) }
                                    .buttonStyle(.secondary).disabled(!approved)
                            }
                        }
                        if let url = merchantURL {
                            Link(destination: url) { Text("Open \(opportunity.merchantName)").frame(maxWidth: .infinity) }
                                .buttonStyle(.secondary).disabled(!approved)
                        }
                        Button("I did it — record the outcome") {
                            env.repository.update(opportunity, status: .inProgress)
                            onResolved()
                        }
                        .buttonStyle(.money).disabled(!approved)
                        .accessibilityIdentifier("fightRecordOutcomeButton")
                    }
                    Text("LEVER never sends messages, cancels services or spends money on your behalf.")
                        .font(.caption2).foregroundStyle(LeverColor.inkTertiary).frame(maxWidth: .infinity)
                }
                .padding(Spacing.md)
            }
            .leverScreenBackground()
            .navigationTitle("Fight for me")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            SectionHeader(title: title)
            VStack(alignment: .leading, spacing: Spacing.xs) { content() }
                .frame(maxWidth: .infinity, alignment: .leading)
                .leverCard()
        }
    }

    private var merchantURL: URL? {
        guard let domain = opportunity.purchase?.merchant?.domain ?? MerchantDirectory().entry(named: opportunity.merchantName)?.domain else { return nil }
        return URL(string: "https://\(domain)")
    }

    private func mailURL(body: String) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = ""
        components.queryItems = [
            URLQueryItem(name: "subject", value: opportunity.title),
            URLQueryItem(name: "body", value: body),
        ]
        return components.url
    }
}
