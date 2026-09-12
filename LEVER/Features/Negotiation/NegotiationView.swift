import SwiftUI

/// Negotiation assistant: verified inputs in, argument + scripts out. Nothing invented.
struct NegotiationView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    let opportunity: Opportunity

    @State private var currentText: String
    @State private var previousText: String
    @State private var competitorText = ""
    @State private var tenureYears = 0
    @State private var desiredOutcome = "I'd like to keep the service at a fair price."
    @State private var draft: NegotiationDraft?
    @State private var tab = 0

    init(opportunity: Opportunity) {
        self.opportunity = opportunity
        let sub = opportunity.purchase?.subscription
        _currentText = State(initialValue: sub.map { "\($0.price)" } ?? "\(opportunity.purchase?.amount ?? 0)")
        _previousText = State(initialValue: sub?.previousPrice.map { "\($0)" } ?? "")
    }

    private var cycle: BillingCycle { opportunity.purchase?.subscription?.billingCycle ?? .monthly }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    Text("Negotiate with \(opportunity.merchantName)").font(LeverFont.display)
                    Text("Only what you enter here goes into the script. LEVER won't invent customer history or competitor offers.")
                        .font(LeverFont.callout).foregroundStyle(LeverColor.inkSecondary)

                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        input("Current price (\(opportunity.currencyCode)\(cycle.shortSuffix))", text: $currentText)
                        input("Previous price — from your document", text: $previousText)
                        input("Competitor price — only if you've seen one", text: $competitorText)
                        Stepper("Customer for \(tenureYears == 0 ? "— (unknown)" : "\(tenureYears) year\(tenureYears == 1 ? "" : "s")")", value: $tenureYears, in: 0...30)
                            .font(LeverFont.callout)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Desired outcome").font(LeverFont.caption).foregroundStyle(LeverColor.inkSecondary)
                            TextField("", text: $desiredOutcome, axis: .vertical).font(LeverFont.callout)
                                .padding(10).background(LeverColor.surfaceElevated, in: RoundedRectangle(cornerRadius: Radius.sm))
                        }
                    }
                    .leverCard()

                    Button("Build my case") { build() }.buttonStyle(.primary).accessibilityIdentifier("negotiationBuildButton")

                    if let draft {
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            SectionHeader(title: "Position")
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                labelled("Best argument", draft.bestArgument)
                                labelled("Fallback", draft.fallbackArgument)
                                HStack {
                                    if let t = draft.targetPrice { labelled("Target", Money.format(t, code: opportunity.currencyCode) + cycle.shortSuffix) }
                                    Spacer()
                                    if let w = draft.walkAwayPrice { labelled("Walk-away", Money.format(w, code: opportunity.currencyCode) + cycle.shortSuffix) }
                                }
                            }
                            .leverCard()

                            SectionHeader(title: "Scripts")
                            Picker("Channel", selection: $tab) {
                                Text("Email").tag(0)
                                Text("Chat").tag(1)
                                Text("Phone").tag(2)
                            }
                            .pickerStyle(.segmented)
                            let text = [draft.emailDraft, draft.chatDraft, draft.phoneScript][tab]
                            Text(text).font(LeverFont.callout).textSelection(.enabled).leverCard()
                            HStack {
                                Button("Copy") { UIPasteboard.general.string = text; Haptics.actionCompleted() }.buttonStyle(.compact)
                                ShareLink(item: text) { Text("Share") }.buttonStyle(.compact(LeverColor.inkSecondary))
                            }
                        }
                        .transition(.opacity)
                    }
                }
                .padding(Spacing.md)
            }
            .leverScreenBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } } }
        }
    }

    private func input(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(LeverFont.caption).foregroundStyle(LeverColor.inkSecondary)
            TextField("Optional", text: text).keyboardType(.decimalPad).font(LeverFont.callout)
                .padding(10).background(LeverColor.surfaceElevated, in: RoundedRectangle(cornerRadius: Radius.sm))
        }
    }

    private func labelled(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(LeverFont.caption).foregroundStyle(LeverColor.inkSecondary)
            Text(value).font(LeverFont.callout)
        }
    }

    private func build() {
        guard let current = AmountParser.parseDecimal(currentText), current > 0 else { return }
        let input = NegotiationInput(
            merchantName: opportunity.merchantName,
            currencyCode: opportunity.currencyCode,
            currentPrice: current,
            previousPrice: AmountParser.parseDecimal(previousText),
            competitorPrice: AmountParser.parseDecimal(competitorText),
            tenureMonths: tenureYears > 0 ? tenureYears * 12 : nil,
            desiredOutcome: desiredOutcome,
            billingCycle: cycle
        )
        let result = NegotiationAssistant().prepare(input)
        withAnimation(Motion.snappy) { draft = result }
        let model = Negotiation(merchantName: input.merchantName, currentPrice: input.currentPrice, previousPrice: input.previousPrice, competitorPrice: input.competitorPrice, tenureMonths: input.tenureMonths, desiredOutcome: input.desiredOutcome, targetPrice: result.targetPrice, walkAwayPrice: result.walkAwayPrice, bestArgument: result.bestArgument, fallbackArgument: result.fallbackArgument, emailDraft: result.emailDraft, chatDraft: result.chatDraft, phoneScript: result.phoneScript)
        model.opportunity = opportunity
        env.container.mainContext.insert(model)
        try? env.container.mainContext.save()
        env.analytics.track(.actionStarted, properties: ["type": "negotiation"])
    }
}
