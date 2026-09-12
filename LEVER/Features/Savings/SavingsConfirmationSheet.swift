import SwiftUI

/// "Did LEVER actually save you ₹3,600?" — savings only count when the user says so.
struct SavingsConfirmationSheet: View {
    @Environment(AppEnvironment.self) private var env
    let opportunity: Opportunity
    let onDone: () -> Void

    @State private var amountText: String
    @State private var kind: SavingsKind

    init(opportunity: Opportunity, onDone: @escaping () -> Void) {
        self.opportunity = opportunity
        self.onDone = onDone
        _amountText = State(initialValue: opportunity.estimatedSavings.map { "\($0)" } ?? "")
        _kind = State(initialValue: Self.defaultKind(for: opportunity.type))
    }

    static func defaultKind(for type: OpportunityType) -> SavingsKind {
        switch type {
        case .priceDrop, .refund, .duplicateCharge, .travelPriceChange, .claimOpportunity: .recovered
        case .subscriptionRenewal, .feeDetection, .cheaperAlternative: .avoided
        case .negotiation: .negotiated
        case .warrantyExpiration, .purchaseProtection, .insuranceOpportunity, .returnDeadline: .protected
        case .maintenance, .unknown: .saved
        }
    }

    private var amount: Decimal? { AmountParser.parseDecimal(amountText) }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(question).font(LeverFont.display).fixedSize(horizontal: false, vertical: true)
                    Text("Only confirmed savings count towards your total. Be honest — it's your scoreboard.")
                        .font(LeverFont.callout).foregroundStyle(LeverColor.inkSecondary)
                }

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Amount (\(opportunity.currencyCode))").font(LeverFont.caption).foregroundStyle(LeverColor.inkSecondary)
                    TextField("0", text: $amountText)
                        .keyboardType(.decimalPad)
                        .font(LeverFont.hero(34))
                        .accessibilityIdentifier("savingsAmountField")
                    Picker("Type", selection: $kind) {
                        ForEach(SavingsKind.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                .leverCard()

                Spacer()

                VStack(spacing: Spacing.xs) {
                    Button("Yes, I saved it") {
                        guard let amount, amount > 0 else { return }
                        let event = env.repository.proposeSaving(for: opportunity, amount: amount, kind: kind)
                        env.repository.confirmSaving(event, amount: amount)
                        Haptics.savingConfirmed()
                        onDone()
                    }
                    .buttonStyle(.money)
                    .disabled((amount ?? 0) <= 0)
                    .accessibilityIdentifier("savingsYesButton")
                    Button("Not yet") {
                        if let amount, amount > 0 { env.repository.proposeSaving(for: opportunity, amount: amount, kind: kind) }
                        env.repository.update(opportunity, status: .inProgress)
                        onDone()
                    }
                    .buttonStyle(.secondary)
                    .accessibilityIdentifier("savingsNotYetButton")
                    Button("No, nothing saved") {
                        for pending in opportunity.savingsEvents where pending.status == .pending { env.repository.rejectSaving(pending) }
                        env.repository.update(opportunity, status: .resolved)
                        onDone()
                    }
                    .font(LeverFont.callout.weight(.medium)).foregroundStyle(LeverColor.inkSecondary)
                }
            }
            .padding(Spacing.md)
            .leverScreenBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Later", action: onDone) } }
        }
        .presentationDetents([.large])
    }

    private var question: String {
        if let savings = opportunity.estimatedSavings, savings > 0 {
            return "Did LEVER actually save you \(Money.format(savings, code: opportunity.currencyCode))?"
        }
        return "Did this save or protect any money?"
    }
}
