import SwiftUI

/// Correct anything LEVER read wrong, or add what a receipt never said (return deadline, serial number).
struct EditPurchaseSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    let purchase: Purchase

    @State private var title: String
    @State private var merchant: String
    @State private var amountText: String
    @State private var hasDate: Bool
    @State private var date: Date
    @State private var hasReturn: Bool
    @State private var returnDeadline: Date
    @State private var orderNumber: String
    @State private var serialNumber: String
    @State private var notes: String
    @State private var saving = false

    init(purchase: Purchase) {
        self.purchase = purchase
        _title = State(initialValue: purchase.title)
        _merchant = State(initialValue: purchase.merchantName)
        _amountText = State(initialValue: "\(purchase.amount)")
        _hasDate = State(initialValue: purchase.purchaseDate != nil)
        _date = State(initialValue: purchase.purchaseDate ?? .now)
        _hasReturn = State(initialValue: purchase.returnWindow?.deadline != nil)
        _returnDeadline = State(initialValue: purchase.returnWindow?.deadline ?? DateMath.adding(days: 14, to: purchase.purchaseDate ?? .now) ?? .now)
        _orderNumber = State(initialValue: purchase.orderNumber ?? "")
        _serialNumber = State(initialValue: purchase.serialNumber ?? "")
        _notes = State(initialValue: purchase.notes ?? "")
    }

    private var amount: Decimal? { AmountParser.parseDecimal(amountText) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Purchase") {
                    TextField("Item", text: $title).accessibilityIdentifier("editTitle")
                    TextField("Merchant", text: $merchant)
                    HStack {
                        Text(Money.symbol(for: purchase.currencyCode)).foregroundStyle(LeverColor.inkSecondary)
                        TextField("Amount", text: $amountText).keyboardType(.decimalPad).accessibilityIdentifier("editAmountField")
                    }
                    Toggle("Purchase date known", isOn: $hasDate)
                    if hasDate { DatePicker("Purchased", selection: $date, displayedComponents: .date) }
                }
                Section {
                    Toggle("Return deadline", isOn: $hasReturn)
                    if hasReturn { DatePicker("Return by", selection: $returnDeadline, in: (purchase.purchaseDate ?? .distantPast)..., displayedComponents: .date) }
                } footer: {
                    Text(purchase.returnWindow.map { "Currently: \($0.policySource)." } ?? "LEVER only sets return deadlines it can source. Set one here if you know the policy.")
                }
                Section("Identifiers") {
                    TextField("Order number", text: $orderNumber).font(LeverFont.mono)
                    TextField("Serial number", text: $serialNumber).font(LeverFont.mono)
                }
                Section("Notes") {
                    TextField("Anything worth remembering", text: $notes, axis: .vertical).lineLimit(2...5)
                }
            }
            .scrollContentBackground(.hidden)
            .leverScreenBackground()
            .navigationTitle("Edit purchase")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(saving ? "Saving…" : "Save") {
                        guard let amount else { return }
                        saving = true
                        let edits = PurchaseRepository.PurchaseEdits(
                            title: title.trimmingCharacters(in: .whitespaces), merchantName: merchant.trimmingCharacters(in: .whitespaces), amount: amount,
                            purchaseDate: hasDate ? date : nil, returnDeadline: hasReturn ? returnDeadline : nil,
                            orderNumber: orderNumber.isEmpty ? nil : orderNumber, serialNumber: serialNumber.isEmpty ? nil : serialNumber, notes: notes.isEmpty ? nil : notes
                        )
                        Task {
                            await env.repository.apply(edits, to: purchase)
                            Haptics.actionCompleted()
                            dismiss()
                        }
                    }
                    .disabled(saving || amount == nil || title.trimmingCharacters(in: .whitespaces).isEmpty || merchant.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityIdentifier("editSaveButton")
                }
            }
        }
    }
}
