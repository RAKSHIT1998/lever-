import SwiftUI

struct PurchaseDetailView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @Bindable var purchase: Purchase

    @State private var showPriceSheet = false
    @State private var showWarrantySheet = false
    @State private var showDeleteConfirm = false
    @State private var showEdit = false
    @State private var shareURL: URL?
    @State private var selectedOpportunity: Opportunity?
    @State private var previewDocument: StoredDocument?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                header
                leverCheck
                if !purchase.openOpportunities.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        SectionHeader(title: "Potential opportunities")
                        ForEach(OpportunityRanker.rank(purchase.openOpportunities) { $0.priorityScore }) { o in
                            Button { selectedOpportunity = o } label: {
                                HStack {
                                    Circle().fill(LeverColor.lane(o.lane)).frame(width: 8, height: 8)
                                    Text(o.title).font(LeverFont.callout).foregroundStyle(LeverColor.ink).multilineTextAlignment(.leading)
                                    Spacer()
                                    if let s = o.estimatedSavings, s > 0 { MoneyAmount(amount: s, currencyCode: o.currencyCode, size: .small, tint: LeverColor.money, compact: true) }
                                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(LeverColor.inkTertiary)
                                }
                                .leverCard(padding: Spacing.sm)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                details
                coverage
                if let sub = purchase.subscription { subscription(sub) }
                if let estimate = resaleEstimate { resale(estimate) }
                priceHistory
                documents
                timeline
                familySection
                Button("Delete purchase", role: .destructive) { showDeleteConfirm = true }
                    .font(LeverFont.callout.weight(.medium)).frame(maxWidth: .infinity)
            }
            .padding(Spacing.md)
            .padding(.bottom, Spacing.xl)
        }
        .leverScreenBackground()
        .navigationTitle(purchase.merchantName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { showEdit = true }.accessibilityIdentifier("purchaseEditButton")
            }
        }
        .sheet(isPresented: $showEdit) { EditPurchaseSheet(purchase: purchase) }
        .sheet(item: $shareURL) { url in ShareSheet(items: [url]) }
        .navigationDestination(item: $selectedOpportunity) { OpportunityDetailView(opportunity: $0) }
        .sheet(isPresented: $showPriceSheet) { RecordPriceSheet(purchase: purchase) }
        .sheet(isPresented: $showWarrantySheet) { AddWarrantySheet(purchase: purchase) }
        .sheet(item: $previewDocument) { DocumentPreview(document: $0) }
        .confirmationDialog("Delete this purchase and its documents?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task { await env.repository.delete(purchase); dismiss() }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.sm) {
                MerchantAvatar(name: purchase.merchantName, category: purchase.merchantCategory, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(purchase.title).font(LeverFont.title3).lineLimit(2)
                    Text(purchase.merchantName).font(LeverFont.caption).foregroundStyle(LeverColor.inkSecondary)
                }
            }
            MoneyAmount(amount: purchase.amount, currencyCode: purchase.currencyCode, size: .hero)
            HStack(spacing: Spacing.xs) {
                Label(purchase.documentType.displayName, systemImage: purchase.documentType.symbol)
                if let date = purchase.purchaseDate { Text("·"); Text("Purchased \(date.leverMedium)") }
            }
            .font(LeverFont.caption).foregroundStyle(LeverColor.inkSecondary)
        }
    }

    private var leverCheck: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            SectionHeader(title: "LEVER check")
            VStack(alignment: .leading, spacing: 0) {
                CheckRow(text: purchase.documents.contains { $0.kind != .text } ? "Receipt stored" : "Text stored (no image)", done: !purchase.documents.isEmpty)
                CheckRow(text: purchase.warranties.isEmpty ? "No warranty found — add one if you have it" : "Warranty tracked", done: !purchase.warranties.isEmpty)
                CheckRow(text: purchase.returnWindow?.deadline != nil ? "Return window checked" : "Return window not confirmed", done: purchase.returnWindow?.deadline != nil)
                CheckRow(text: purchase.warranties.contains { $0.type == .creditCard } ? "Purchase protection recorded" : "Purchase protection not checked", done: purchase.warranties.contains { $0.type == .creditCard })
                CheckRow(text: purchase.latestPriceObservation != nil ? "Current price checked \(purchase.latestPriceObservation?.observedAt.leverShort ?? "")" : "Current price not checked", done: purchase.latestPriceObservation != nil)
            }
            .leverCard(padding: Spacing.sm)
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            SectionHeader(title: "Details")
            VStack(spacing: 0) {
                KeyValueRow(key: "Merchant", value: purchase.merchantName)
                Divider()
                KeyValueRow(key: "Category", value: purchase.merchantCategory.displayName)
                if let order = purchase.orderNumber { Divider(); KeyValueRow(key: "Order", value: order, mono: true) }
                if let inv = purchase.invoiceNumber { Divider(); KeyValueRow(key: "Invoice", value: inv, mono: true) }
                if let ref = purchase.referenceNumber { Divider(); KeyValueRow(key: "Reference", value: ref, mono: true) }
                if let serial = purchase.serialNumber { Divider(); KeyValueRow(key: "Serial", value: serial, mono: true) }
                if let policy = purchase.policyNumber { Divider(); KeyValueRow(key: "Policy", value: policy, mono: true) }
                if let pay = purchase.paymentMethod { Divider(); KeyValueRow(key: "Paid with", value: pay) }
                if let service = purchase.serviceDate { Divider(); KeyValueRow(key: "Service date", value: service.leverMedium) }
                if let rw = purchase.returnWindow {
                    Divider()
                    KeyValueRow(key: "Return by", value: rw.deadline?.leverMedium ?? "Not confirmed", confidence: rw.confidence)
                    Text(rw.policySource).font(.caption2).foregroundStyle(LeverColor.inkTertiary).frame(maxWidth: .infinity, alignment: .trailing)
                }
                if !purchase.items.isEmpty {
                    Divider()
                    ForEach(purchase.items, id: \.persistentModelID) { item in
                        KeyValueRow(key: item.quantity > 1 ? "\(item.name) ×\(item.quantity)" : item.name, value: item.lineTotal.map { Money.format($0, code: purchase.currencyCode) } ?? "—")
                    }
                }
            }
            .leverCard(padding: Spacing.sm)
        }
    }

    private var coverage: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            SectionHeader(title: "Coverage", action: { showWarrantySheet = true }, actionTitle: "Add")
            if purchase.warranties.isEmpty {
                Text("No warranty, extended cover or card protection recorded yet.").font(LeverFont.callout).foregroundStyle(LeverColor.inkSecondary).leverCard()
            } else {
                ForEach(purchase.warranties, id: \.persistentModelID) { w in
                    HStack(alignment: .top) {
                        Image(systemName: "shield.checkered").foregroundStyle(w.isActive ? LeverColor.money : LeverColor.inkTertiary)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(w.provider) · \(w.type.displayName)").font(LeverFont.headline)
                            if let end = w.endDate {
                                Text(w.isActive ? "Until \(end.leverMedium) · \(w.daysRemaining() ?? 0) days left" : "Ended \(end.leverMedium)").font(LeverFont.caption).foregroundStyle(LeverColor.inkSecondary)
                            } else {
                                Text("End date not confirmed").font(LeverFont.caption).foregroundStyle(LeverColor.inkSecondary)
                            }
                            if let summary = w.coverageSummary { Text(summary).font(LeverFont.caption).foregroundStyle(LeverColor.inkSecondary) }
                            HStack(spacing: 6) {
                                ConfidenceBadge(confidence: w.confidence)
                                Text(w.source).font(.caption2).foregroundStyle(LeverColor.inkTertiary)
                            }
                        }
                        Spacer()
                    }
                    .leverCard(padding: Spacing.sm)
                    .contextMenu {
                        Button("Remove", role: .destructive) {
                            env.container.mainContext.delete(w)
                            try? env.container.mainContext.save()
                            Task { await env.repository.refreshOpportunities(for: purchase) }
                        }
                    }
                }
            }
        }
    }

    private func subscription(_ sub: Subscription) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            SectionHeader(title: "Subscription")
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack {
                    MoneyAmount(amount: sub.price, currencyCode: sub.currencyCode, size: .medium)
                    Text(sub.billingCycle.shortSuffix).foregroundStyle(LeverColor.inkSecondary)
                    Spacer()
                    if let annual = sub.annualCost { Text("\(Money.format(annual, code: sub.currencyCode))/yr").font(LeverFont.caption).foregroundStyle(LeverColor.inkSecondary) }
                }
                if let next = sub.nextBillingDate { KeyValueRow(key: "Next billing", value: next.leverMedium) }
                if let prev = sub.previousPrice { KeyValueRow(key: "Previous price", value: Money.format(prev, code: sub.currencyCode)) }
                KeyValueRow(key: "Status", value: sub.status.displayName)
                Text(sub.status == .markedUnused ? "You've marked this subscription as unused." : "LEVER can't see usage — tell it if you've stopped using this.")
                    .font(LeverFont.caption).foregroundStyle(LeverColor.inkSecondary)
                HStack {
                    Button(sub.status == .markedUnused ? "I use this" : "Mark as unused") {
                        sub.status = sub.status == .markedUnused ? .active : .markedUnused
                        try? env.container.mainContext.save()
                        Task { await env.repository.refreshOpportunities(for: purchase); env.repository.publishSnapshot() }
                    }
                    .buttonStyle(.compact)
                    .accessibilityIdentifier("markUnusedButton")
                    if let manage = MerchantDirectory.manageURL(for: purchase.merchantName) {
                        Link(destination: manage) { Text("Manage") }.buttonStyle(.compact(LeverColor.inkSecondary))
                    }
                    Button(sub.status == .cancelled ? "Reactivate" : "Mark cancelled") {
                        sub.status = sub.status == .cancelled ? .active : .cancelled
                        try? env.container.mainContext.save()
                        Task { await env.repository.refreshOpportunities(for: purchase); await env.repository.scheduleReminders(for: purchase) }
                    }
                    .buttonStyle(.compact(LeverColor.inkSecondary))
                }
            }
            .leverCard()
        }
    }

    private var familySection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            SectionHeader(title: "Family")
            VStack(alignment: .leading, spacing: Spacing.sm) {
                if let by = purchase.sharedBy {
                    Label("Shared with you by \(by)", systemImage: "person.2.fill").font(LeverFont.callout)
                } else if purchase.householdID != nil {
                    Label("In your household vault", systemImage: "person.2.fill").font(LeverFont.callout)
                } else {
                    Text("Warranties, insurance and big purchases are family business. Send this record to a household member's LEVER.")
                        .font(LeverFont.callout).foregroundStyle(LeverColor.inkSecondary)
                }
                Button {
                    // Built on tap, never in `body`: exporting marks the purchase as shared and saves.
                    let bundle = env.repository.shareBundle(for: purchase)
                    let url = FileManager.default.temporaryDirectory.appendingPathComponent(PurchaseTransferCodec.fileName(for: bundle))
                    if let data = try? PurchaseTransferCodec.encode(bundle), (try? data.write(to: url, options: .atomic)) != nil {
                        shareURL = url
                    }
                } label: {
                    Label("Share with family", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                }
                .buttonStyle(.secondary)
                .accessibilityIdentifier("shareWithFamilyButton")
                Text("Sent as a .leverpurchase file over AirDrop, Messages or Files — receipts included, nothing via a server.")
                    .font(.caption2).foregroundStyle(LeverColor.inkTertiary)
            }
            .leverCard()
        }
    }

    private var resaleEstimate: ResaleEstimate? {
        guard purchase.subscription == nil, purchase.amount >= 5_000, let date = purchase.purchaseDate else { return nil }
        return ResaleEstimator.estimate(price: purchase.amount, purchaseDate: date, title: purchase.title, category: purchase.merchantCategory)
    }

    private func resale(_ e: ResaleEstimate) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            SectionHeader(title: "Estimated resale value")
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(alignment: .lastTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Today").font(LeverFont.caption).foregroundStyle(LeverColor.inkSecondary)
                        MoneyAmount(amount: e.valueNow, currencyCode: purchase.currencyCode, size: .medium)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("In 6 months").font(LeverFont.caption).foregroundStyle(LeverColor.inkSecondary)
                        MoneyAmount(amount: e.valueInSixMonths, currencyCode: purchase.currencyCode, size: .medium, tint: LeverColor.inkSecondary)
                    }
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(LeverColor.surfaceElevated)
                        Capsule().fill(LeverColor.money.opacity(0.7)).frame(width: geo.size.width * CGFloat(min(1, NSDecimalNumber(decimal: e.valueNow / max(purchase.amount, 1)).doubleValue)))
                    }
                }
                .frame(height: 6)
                HStack(spacing: 6) {
                    ConfidenceBadge(confidence: e.confidence)
                    Text("\(e.deviceClass.displayName) · \(e.ageMonths) months old").font(.caption2).foregroundStyle(LeverColor.inkTertiary)
                }
                Text(e.method + ". Real offers depend on condition and demand.").font(.caption2).foregroundStyle(LeverColor.inkTertiary)
            }
            .leverCard()
        }
    }

    private var priceHistory: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            SectionHeader(title: "Price", action: { showPriceSheet = true }, actionTitle: "Record a price")
            VStack(alignment: .leading, spacing: Spacing.xs) {
                if purchase.priceObservations.isEmpty {
                    Text("Seen this cheaper? Record the price and LEVER will tell you if it's worth chasing.").font(LeverFont.callout).foregroundStyle(LeverColor.inkSecondary)
                } else {
                    ForEach(purchase.priceObservations.sorted { $0.observedAt > $1.observedAt }, id: \.persistentModelID) { obs in
                        HStack {
                            Text(obs.observedAt.leverShort).font(LeverFont.caption).foregroundStyle(LeverColor.inkSecondary)
                            Spacer()
                            MoneyAmount(amount: obs.observedPrice, currencyCode: obs.currencyCode, size: .small, tint: obs.observedPrice < purchase.amount ? LeverColor.money : LeverColor.ink)
                            Text(obs.source).font(.caption2).foregroundStyle(LeverColor.inkTertiary)
                        }
                    }
                }
                if let urlString = purchase.productURL, let url = URL(string: urlString) {
                    Link(destination: url) { Label("Open product page", systemImage: "safari").font(LeverFont.label) }
                }
            }
            .leverCard()
        }
    }

    private var documents: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            SectionHeader(title: "Documents")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.xs) {
                    ForEach(purchase.documents, id: \.persistentModelID) { doc in
                        Button { previewDocument = doc } label: {
                            VStack(spacing: 6) {
                                DocumentImage(document: doc, files: env.files).frame(width: 96, height: 120).clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                                Text(doc.kind.rawValue.uppercased()).font(.caption2.weight(.bold)).foregroundStyle(LeverColor.inkTertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            SectionHeader(title: "Timeline")
            VStack(alignment: .leading, spacing: 0) {
                ForEach(PurchaseTimeline.events(for: purchase), id: \.title) { event in
                    HStack(alignment: .top, spacing: Spacing.sm) {
                        VStack { Circle().fill(event.date <= .now ? LeverColor.ink : LeverColor.hairline).frame(width: 8, height: 8).padding(.top, 6); Rectangle().fill(LeverColor.hairline).frame(width: 1) }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.title).font(LeverFont.callout)
                            Text(event.date.leverMedium).font(LeverFont.caption).foregroundStyle(LeverColor.inkSecondary)
                        }
                        .padding(.bottom, Spacing.sm)
                        Spacer()
                    }
                }
            }
            .leverCard()
        }
    }
}

enum PurchaseTimeline {
    struct Event { let title: String; let date: Date }

    @MainActor
    static func events(for p: Purchase) -> [Event] {
        var events: [Event] = []
        if let d = p.purchaseDate { events.append(Event(title: "Purchased from \(p.merchantName)", date: d)) }
        events.append(Event(title: "Captured in LEVER", date: p.createdAt))
        if let d = p.returnWindow?.deadline { events.append(Event(title: "Return window closes", date: d)) }
        for w in p.warranties { if let d = w.endDate { events.append(Event(title: "\(w.provider) coverage ends", date: d)) } }
        if let d = p.subscription?.nextBillingDate { events.append(Event(title: "Next renewal", date: d)) }
        if let d = p.serviceDate { events.append(Event(title: "Service / travel date", date: d)) }
        for s in p.savingsEvents where s.status == .confirmed { events.append(Event(title: "\(s.kind.displayName): \(Money.format(s.amount, code: s.currencyCode))", date: s.confirmedAt ?? s.date)) }
        return events.sorted { $0.date < $1.date }
    }
}

struct DocumentImage: View {
    let document: StoredDocument
    let files: DocumentFileStore

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.sm).fill(LeverColor.surfaceElevated)
            if document.kind == .image, let name = document.fileName, let data = files.read(name), let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: document.kind == .pdf ? "doc.richtext" : "text.alignleft").font(.title2).foregroundStyle(LeverColor.inkSecondary)
            }
        }
    }
}

struct DocumentPreview: View {
    @Environment(AppEnvironment.self) private var env
    let document: StoredDocument

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    if document.kind == .image, let name = document.fileName, let data = env.files.read(name), let image = UIImage(data: data) {
                        Image(uiImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: Radius.md))
                    }
                    if let text = document.rawText, !text.isEmpty {
                        Text(text).font(LeverFont.mono).textSelection(.enabled).leverCard()
                    }
                }
                .padding(Spacing.md)
            }
            .leverScreenBackground()
            .navigationTitle(document.kind.rawValue.capitalized)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct RecordPriceSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    let purchase: Purchase
    @State private var priceText = ""
    @State private var urlText: String
    @State private var checking = false
    @State private var checkMessage: String?

    init(purchase: Purchase) {
        self.purchase = purchase
        _urlText = State(initialValue: purchase.productURL ?? "")
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("Record the price you saw for \(purchase.title). LEVER compares it with what you paid.").font(LeverFont.callout).foregroundStyle(LeverColor.inkSecondary)
                TextField("Current price (\(purchase.currencyCode))", text: $priceText).keyboardType(.decimalPad).font(LeverFont.hero(34)).accessibilityIdentifier("recordPriceField")
                TextField("Product link (optional)", text: $urlText).keyboardType(.URL).textInputAutocapitalization(.never).font(LeverFont.callout)
                    .padding(10).background(LeverColor.surfaceElevated, in: RoundedRectangle(cornerRadius: Radius.sm))
                if let url = URL(string: urlText), env.priceMonitor.supportsAutomaticTracking(for: url) {
                    Button {
                        checking = true
                        Task {
                            if let price = try? await env.priceMonitor.fetchCurrentPrice(for: url) {
                                priceText = "\(price)"
                                checkMessage = "Read \(Money.format(price, code: purchase.currencyCode)) from the page."
                            } else {
                                checkMessage = "Couldn't find a listed price on that page. Enter it manually."
                            }
                            checking = false
                        }
                    } label: {
                        Label(checking ? "Reading page…" : "Read price from page", systemImage: "safari")
                    }
                    .buttonStyle(.compact(LeverColor.inkSecondary)).disabled(checking)
                }
                if let checkMessage { Text(checkMessage).font(LeverFont.caption).foregroundStyle(LeverColor.inkSecondary) }
                Text("With a link saved, LEVER re-reads the page's listed price about once a day and tells you if it drops.").font(.caption2).foregroundStyle(LeverColor.inkTertiary)
                Spacer()
                Button("Save price") {
                    guard let price = AmountParser.parseDecimal(priceText), price > 0 else { return }
                    Task {
                        await env.repository.recordPrice(price, url: urlText.isEmpty ? nil : urlText, for: purchase)
                        dismiss()
                    }
                }
                .buttonStyle(.primary)
                .disabled((AmountParser.parseDecimal(priceText) ?? 0) <= 0)
                .accessibilityIdentifier("recordPriceSave")
            }
            .padding(Spacing.md)
            .leverScreenBackground()
            .navigationTitle("Record a price")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } } }
        }
        .presentationDetents([.medium])
    }
}

struct AddWarrantySheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    let purchase: Purchase
    @State private var provider: String
    @State private var type: WarrantyType = .manufacturer
    @State private var months = 12
    @State private var endDate: Date
    @State private var useEndDate = false
    @State private var summary = ""

    init(purchase: Purchase) {
        self.purchase = purchase
        _provider = State(initialValue: purchase.merchantName)
        _endDate = State(initialValue: DateMath.adding(months: 12, to: purchase.purchaseDate ?? .now) ?? .now)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Provider", text: $provider)
                Picker("Type", selection: $type) { ForEach(WarrantyType.allCases, id: \.self) { Text($0.displayName).tag($0) } }
                Toggle("I know the end date", isOn: $useEndDate)
                if useEndDate { DatePicker("Ends", selection: $endDate, displayedComponents: .date) }
                else { Stepper("\(months) months from purchase", value: $months, in: 1...120) }
                TextField("Coverage notes (optional)", text: $summary, axis: .vertical)
            }
            .scrollContentBackground(.hidden)
            .leverScreenBackground()
            .navigationTitle("Add coverage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") {
                        let end = useEndDate ? endDate : DateMath.adding(months: months, to: purchase.purchaseDate ?? .now)
                        let w = Warranty(provider: provider, type: type, startDate: purchase.purchaseDate, endDate: end, coverageSummary: summary.isEmpty ? nil : summary, source: "Entered by you", confidence: .high)
                        w.purchase = purchase
                        env.container.mainContext.insert(w)
                        try? env.container.mainContext.save()
                        Task {
                            await env.repository.refreshOpportunities(for: purchase)
                            await env.repository.scheduleReminders(for: purchase)
                            env.repository.publishSnapshot()
                        }
                        dismiss()
                    }
                    .disabled(provider.isEmpty)
                }
            }
        }
    }
}
