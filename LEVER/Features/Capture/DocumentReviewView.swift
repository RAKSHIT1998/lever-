import SwiftUI

/// "I found:" — the confirmation screen. Every field is editable; low-confidence fields are flagged.
struct DocumentReviewView: View {
    @State private var doc: PurchaseDocument
    let sourceDescription: String
    let onConfirm: (PurchaseDocument) -> Void
    let onCancel: () -> Void
    /// When set, shows "Re-read with AI"; returns the improved document and how many fields changed.
    var onReread: (() async -> (PurchaseDocument, Int))? = nil
    @State private var rereading = false
    @State private var rereadNote: String?

    @State private var editing = false
    @State private var amountText: String
    @State private var hasPurchaseDate: Bool
    @State private var purchaseDate: Date
    @State private var hasReturnDeadline: Bool
    @State private var returnDeadline: Date
    @State private var hasRenewal: Bool
    @State private var renewalDate: Date
    @State private var warrantyMonths: Int
    @State private var isSubscription: Bool
    @State private var cycle: BillingCycle

    init(document: PurchaseDocument, sourceDescription: String, startEditing: Bool = false, onReread: (() async -> (PurchaseDocument, Int))? = nil, onConfirm: @escaping (PurchaseDocument) -> Void, onCancel: @escaping () -> Void) {
        _doc = State(initialValue: document)
        self.sourceDescription = sourceDescription
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        self.onReread = onReread
        _amountText = State(initialValue: document.amount.map { "\($0)" } ?? "")
        _hasPurchaseDate = State(initialValue: document.purchaseDate != nil)
        _purchaseDate = State(initialValue: document.purchaseDate ?? .now)
        _hasReturnDeadline = State(initialValue: document.returnDeadline != nil)
        _returnDeadline = State(initialValue: document.returnDeadline ?? DateMath.adding(days: 14, to: .now) ?? .now)
        _hasRenewal = State(initialValue: document.renewalDate != nil || document.subscription?.nextBillingDate != nil)
        _renewalDate = State(initialValue: document.subscription?.nextBillingDate ?? document.renewalDate ?? DateMath.adding(days: 30, to: .now) ?? .now)
        _warrantyMonths = State(initialValue: document.warranties.first?.months ?? 0)
        _isSubscription = State(initialValue: document.subscription != nil)
        _cycle = State(initialValue: document.subscription?.billingCycle ?? .monthly)
        _editing = State(initialValue: startEditing || !document.hasUsableCore)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(doc.hasUsableCore && !editing ? "I found:" : (doc.hasUsableCore ? "Check the details." : "Tell me about it."))
                        .font(LeverFont.display)
                    HStack(spacing: 6) {
                        Text(sourceDescription)
                        Text("·")
                        Text(doc.processedOnDevice ? "Read on this iPhone" : doc.providerName)
                        Text("·")
                        ConfidenceBadge(confidence: doc.overallConfidence)
                    }
                    .font(LeverFont.caption).foregroundStyle(LeverColor.inkSecondary)
                }

                if !doc.fieldsNeedingVerification.isEmpty && !editing {
                    InsightBanner(symbol: "eye", title: "Worth a quick check", message: "Fields marked with a dot were read with lower confidence. Tap Edit to correct anything.", tint: LeverColor.opportunity)
                }

                if let onReread, !editing {
                    Button {
                        rereading = true
                        Task {
                            let (improved, changed) = await onReread()
                            load(improved)
                            rereadNote = changed == 0 ? "Gemini agreed with the on-device read." : "Gemini updated \(changed) field\(changed == 1 ? "" : "s") — dots mark what to double-check."
                            rereading = false
                            if changed > 0 { Haptics.actionCompleted() }
                        }
                    } label: {
                        HStack {
                            Label(rereading ? "Re-reading with Gemini…" : "Re-read with AI", systemImage: "sparkles")
                            Spacer()
                            if rereading { ProgressView().controlSize(.small) }
                        }
                    }
                    .buttonStyle(.secondary)
                    .disabled(rereading)
                    .accessibilityIdentifier("rereadButton")
                    if let rereadNote { Text(rereadNote).font(LeverFont.caption).foregroundStyle(LeverColor.inkSecondary) }
                }

                if editing { editor } else { summary }

                if !doc.rawText.isEmpty {
                    DisclosureGroup {
                        Text(doc.rawText).font(LeverFont.mono).foregroundStyle(LeverColor.inkSecondary).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } label: {
                        Text("Recognised text").font(LeverFont.label).foregroundStyle(LeverColor.inkSecondary)
                    }
                    .leverCard(padding: Spacing.sm)
                }

                VStack(spacing: Spacing.xs) {
                    Button(editing ? "Save changes" : "Looks right") {
                        if editing { applyEdits() }
                        onConfirm(doc)
                    }
                    .buttonStyle(.primary)
                    .disabled(editing && (doc.merchant ?? "").isEmpty && amountText.isEmpty)
                    .accessibilityIdentifier("reviewConfirmButton")
                    Button(editing ? "Back to summary" : "Edit") {
                        if editing { applyEdits() }
                        withAnimation(Motion.snappy) { editing.toggle() }
                    }
                    .buttonStyle(.secondary)
                    .accessibilityIdentifier("reviewEditButton")
                    Button("Discard", role: .destructive, action: onCancel)
                        .font(LeverFont.callout.weight(.medium))
                        .padding(.top, Spacing.xs)
                }
            }
            .padding(Spacing.md)
            .padding(.bottom, Spacing.xl)
        }
    }

    private var summary: some View {
        VStack(spacing: 0) {
            KeyValueRow(key: "Type", value: doc.documentType.displayName, confidence: doc.confidence(for: "documentType"))
            Divider()
            KeyValueRow(key: "Merchant", value: doc.merchant ?? "Not found", confidence: doc.merchant == nil ? .low : doc.confidence(for: "merchant"))
            if let title = doc.productTitle, title != doc.merchant {
                Divider()
                KeyValueRow(key: "Item", value: title, confidence: doc.confidence(for: "productTitle"))
            }
            Divider()
            KeyValueRow(key: "Total", value: doc.amount.map { Money.format($0, code: doc.currencyCode) } ?? "Not found", confidence: doc.amount == nil ? .low : doc.confidence(for: "amount"))
            Divider()
            KeyValueRow(key: "Purchase date", value: doc.purchaseDate?.leverMedium ?? "Not found", confidence: doc.purchaseDate == nil ? .low : doc.confidence(for: "purchaseDate"))
            if let sub = doc.subscription {
                Divider()
                KeyValueRow(key: "Billing", value: sub.billingCycle.displayName, confidence: doc.confidence(for: "subscription"))
                if let next = sub.nextBillingDate ?? doc.renewalDate {
                    Divider()
                    KeyValueRow(key: "Renews", value: next.leverMedium, confidence: doc.confidence(for: "renewalDate"))
                }
                if let previous = sub.previousPrice {
                    Divider()
                    KeyValueRow(key: "Previous price", value: Money.format(previous, code: doc.currencyCode), confidence: .medium)
                }
            }
            if let deadline = doc.returnDeadline {
                Divider()
                KeyValueRow(key: "Return deadline", value: deadline.leverMedium, confidence: doc.confidence(for: "returnDeadline"))
            } else if doc.documentType == .receipt || doc.documentType == .orderConfirmation || doc.documentType == .invoice {
                Divider()
                KeyValueRow(key: "Return deadline", value: "Deadline not confirmed", confidence: .low)
            }
            if let warranty = doc.warranties.first {
                Divider()
                KeyValueRow(key: "Warranty", value: warranty.months.map { "\($0) months" } ?? warranty.endDate.map { "Until \($0.leverShort)" } ?? "Mentioned", confidence: warranty.confidence)
            }
            if let order = doc.orderNumber { Divider(); KeyValueRow(key: "Order", value: order, mono: true) }
            if let ref = doc.referenceNumber { Divider(); KeyValueRow(key: "Reference", value: ref, mono: true) }
            if let serial = doc.serialNumber { Divider(); KeyValueRow(key: "Serial", value: serial, mono: true) }
            if let policy = doc.policyNumber { Divider(); KeyValueRow(key: "Policy", value: policy, mono: true) }
            if let payment = doc.paymentMethod { Divider(); KeyValueRow(key: "Paid with", value: payment, confidence: doc.confidence(for: "paymentMethod")) }
            if !doc.items.isEmpty {
                Divider()
                KeyValueRow(key: "Items", value: "\(doc.items.count) line\(doc.items.count == 1 ? "" : "s")")
            }
        }
        .leverCard(padding: Spacing.sm)
        .padding(.horizontal, 0)
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Picker("Type", selection: $doc.documentType) {
                ForEach(DocumentType.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.menu)

            field("Merchant") {
                TextField("e.g. Amazon", text: Binding(get: { doc.merchant ?? "" }, set: { doc.merchant = $0.isEmpty ? nil : $0 }))
                    .accessibilityIdentifier("editMerchant")
            }
            field("Item") {
                TextField("What did you buy?", text: Binding(get: { doc.productTitle ?? "" }, set: { doc.productTitle = $0.isEmpty ? nil : $0 }))
            }
            field("Total (\(doc.currencyCode))") {
                TextField("0", text: $amountText).keyboardType(.decimalPad).accessibilityIdentifier("editAmount")
            }
            Toggle("Purchase date known", isOn: $hasPurchaseDate)
            if hasPurchaseDate {
                DatePicker("Purchase date", selection: $purchaseDate, displayedComponents: .date)
            }
            Toggle("Return deadline known", isOn: $hasReturnDeadline)
            if hasReturnDeadline {
                DatePicker("Return by", selection: $returnDeadline, displayedComponents: .date)
            }
            Toggle("This is a subscription", isOn: $isSubscription)
            if isSubscription {
                Picker("Billing cycle", selection: $cycle) {
                    ForEach(BillingCycle.allCases.filter { $0 != .unknown }, id: \.self) { Text($0.displayName).tag($0) }
                }
                Toggle("Renewal date known", isOn: $hasRenewal)
                if hasRenewal {
                    DatePicker("Renews on", selection: $renewalDate, displayedComponents: .date)
                }
            }
            Stepper("Warranty: \(warrantyMonths == 0 ? "none" : "\(warrantyMonths) months")", value: $warrantyMonths, in: 0...120, step: 6)
            field("Order / reference number") {
                TextField("Optional", text: Binding(get: { doc.orderNumber ?? "" }, set: { doc.orderNumber = $0.isEmpty ? nil : $0 }))
            }
            field("Serial number") {
                TextField("Optional", text: Binding(get: { doc.serialNumber ?? "" }, set: { doc.serialNumber = $0.isEmpty ? nil : $0 }))
            }
        }
        .font(LeverFont.callout)
        .leverCard()
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(LeverFont.caption).foregroundStyle(LeverColor.inkSecondary)
            content()
                .textFieldStyle(.plain)
                .padding(10)
                .background(LeverColor.surfaceElevated, in: RoundedRectangle(cornerRadius: Radius.sm))
        }
    }

    /// Replace the document and re-seed the editor's field states.
    private func load(_ d: PurchaseDocument) {
        doc = d
        amountText = d.amount.map { "\($0)" } ?? ""
        hasPurchaseDate = d.purchaseDate != nil
        purchaseDate = d.purchaseDate ?? purchaseDate
        hasReturnDeadline = d.returnDeadline != nil
        returnDeadline = d.returnDeadline ?? returnDeadline
        hasRenewal = d.renewalDate != nil || d.subscription?.nextBillingDate != nil
        renewalDate = d.subscription?.nextBillingDate ?? d.renewalDate ?? renewalDate
        warrantyMonths = d.warranties.first?.months ?? 0
        isSubscription = d.subscription != nil
        cycle = d.subscription?.billingCycle ?? cycle
    }

    private func applyEdits() {
        doc.amount = AmountParser.parseDecimal(amountText)
        doc.purchaseDate = hasPurchaseDate ? purchaseDate : nil
        doc.returnDeadline = hasReturnDeadline ? returnDeadline : nil
        if isSubscription {
            doc.subscription = PurchaseDocument.SubscriptionInfo(billingCycle: cycle, nextBillingDate: hasRenewal ? renewalDate : nil, previousPrice: doc.subscription?.previousPrice)
            doc.renewalDate = hasRenewal ? renewalDate : nil
            if doc.documentType == .receipt || doc.documentType == .unknown { doc.documentType = .subscription }
        } else {
            doc.subscription = nil
        }
        if warrantyMonths > 0 {
            let end = doc.purchaseDate.flatMap { DateMath.adding(months: warrantyMonths, to: $0) }
            doc.warranties = [PurchaseDocument.WarrantyInfo(provider: doc.merchant ?? "Manufacturer", type: .manufacturer, months: warrantyMonths, endDate: end, source: "Entered by you", confidence: .high)]
        } else {
            doc.warranties = []
        }
        // User-entered values are trusted.
        for key in ["merchant", "amount", "purchaseDate", "returnDeadline", "renewalDate", "subscription", "warranty", "productTitle"] {
            doc.fieldConfidences[key] = 1.0
        }
        doc.overallConfidence = .high
        doc.providerName = doc.providerName.contains("manually") ? doc.providerName : "\(doc.providerName) + your edits"
    }
}
