import SwiftUI
import SwiftData

struct VaultView: View {
    @Environment(AppEnvironment.self) private var env
    @Query(sort: \Purchase.createdAt, order: .reverse) private var purchases: [Purchase]
    @State private var category: VaultCategory = .all
    @State private var sort: VaultSort = .recent
    @State private var query = ""
    @State private var selected: Purchase?
    @State private var showManualEntry = false

    private var filtered: [Purchase] {
        sort.apply(VaultFilter.apply(purchases, category: category, query: query))
    }

    private func count(_ c: VaultCategory) -> Int { purchases.filter { VaultFilter.matches($0, category: c) }.count }

    var body: some View {
        NavigationStack {
            Group {
                if purchases.isEmpty {
                    VStack(spacing: 0) {
                        EmptyState(symbol: "archivebox", title: "Your purchase history will live here.", message: "Every receipt becomes a long-lived record: return window, warranty, price history, claims.", actionTitle: "Scan a purchase") {
                            env.router.selectedTab = .capture
                        }
                        Button("Or add one by hand") { showManualEntry = true }
                            .font(LeverFont.callout.weight(.medium)).foregroundStyle(LeverColor.inkSecondary)
                    }
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: Spacing.sm) {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: Spacing.xs) {
                                    ForEach(VaultCategory.allCases.filter { $0 == .all || count($0) > 0 }) { item in
                                        Button {
                                            withAnimation(Motion.gentle) { category = item }
                                            Haptics.selection()
                                        } label: {
                                            HStack(spacing: 5) {
                                                Text(item.displayName)
                                                Text("\(count(item))").font(.caption2.weight(.bold)).opacity(0.7)
                                            }
                                            .font(LeverFont.label)
                                            .padding(.horizontal, 12).padding(.vertical, 7)
                                            .background(category == item ? LeverColor.ink : LeverColor.surface, in: Capsule())
                                            .foregroundStyle(category == item ? LeverColor.background : LeverColor.ink)
                                            .overlay(Capsule().strokeBorder(LeverColor.hairline))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, Spacing.md)
                            }
                            HStack {
                                Text("\(filtered.count) record\(filtered.count == 1 ? "" : "s") · \(Money.format(filtered.map(\.amount).reduce(0, +), code: env.currencyCode, compact: true))")
                                    .font(LeverFont.caption).foregroundStyle(LeverColor.inkSecondary)
                                Spacer()
                                Menu {
                                    Picker("Sort", selection: $sort) { ForEach(VaultSort.allCases) { Text($0.title).tag($0) } }
                                } label: {
                                    Label(sort.title, systemImage: "arrow.up.arrow.down").font(LeverFont.caption.weight(.semibold)).foregroundStyle(LeverColor.ink)
                                }
                            }
                            .padding(.horizontal, Spacing.md)
                            if filtered.isEmpty {
                                Text("Nothing matches \"\(query)\".").font(LeverFont.callout).foregroundStyle(LeverColor.inkSecondary).padding(Spacing.md)
                            }
                            ForEach(filtered) { purchase in
                                Button { selected = purchase } label: { PurchaseCard(purchase: purchase) }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("vaultRow")
                                    .contextMenu {
                                        Button(role: .destructive) { Task { await env.repository.delete(purchase) } } label: { Label("Delete", systemImage: "trash") }
                                    }
                                    .padding(.horizontal, Spacing.md)
                            }
                        }
                        .padding(.vertical, Spacing.xs)
                        .padding(.bottom, Spacing.xl)
                    }
                    .searchable(text: $query, prompt: "MacBook, Amazon, warranty, expires this month…")
                }
            }
            .leverScreenBackground()
            .navigationTitle("Vault")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showManualEntry = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add a purchase manually")
                        .accessibilityIdentifier("vaultAddButton")
                }
                ToolbarItem(placement: .topBarTrailing) { ProfileButton() }
            }
            .sheet(isPresented: $showManualEntry) { ManualPurchaseSheet() }
            .navigationDestination(item: $selected) { PurchaseDetailView(purchase: $0) }
            .onChange(of: env.router.pendingPurchaseID) { _, id in
                guard let id, let match = purchases.first(where: { $0.id == id }) else { return }
                selected = match
                env.router.pendingPurchaseID = nil
            }
        }
    }
}

/// Pure filtering so search semantics are testable: text, amounts, and phrases like "expires this month".
enum VaultFilter {
    @MainActor
    static func apply(_ purchases: [Purchase], category: VaultCategory, query: String, now: Date = .now) -> [Purchase] {
        var result = purchases.filter { matches($0, category: category) }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return result }

        if q.contains("expir") || q.contains("this month") || q.contains("ending") {
            let monthEnd = Calendar.current.date(byAdding: .month, value: 1, to: DateMath.startOfMonth(for: now)) ?? now
            result = result.filter { p in
                p.warranties.contains { ($0.endDate ?? .distantPast) >= now && ($0.endDate ?? .distantFuture) < monthEnd }
                    || ((p.returnWindow?.deadline ?? .distantPast) >= now && (p.returnWindow?.deadline ?? .distantFuture) < monthEnd)
                    || ((p.subscription?.nextBillingDate ?? .distantPast) >= now && (p.subscription?.nextBillingDate ?? .distantFuture) < monthEnd)
            }
            return result
        }
        if q.contains("subscription") { return result.filter { $0.subscription != nil } }
        if q.contains("warrant") { return result.filter { !$0.warranties.isEmpty } }
        if let amount = AmountParser.parseDecimal(q.replacingOccurrences(of: "₹", with: "").replacingOccurrences(of: "rs", with: "").replacingOccurrences(of: "$", with: "")), amount > 0 {
            return result.filter { abs($0.amount - amount) <= max(1, amount * Decimal(sign: .plus, exponent: -2, significand: 2)) }
        }
        return result.filter { p in
            p.title.lowercased().contains(q) || p.merchantName.lowercased().contains(q)
                || p.tags.contains { $0.contains(q) } || (p.orderNumber?.lowercased().contains(q) ?? false)
                || p.items.contains { $0.name.lowercased().contains(q) }
                || p.documents.contains { ($0.rawText ?? "").lowercased().contains(q) }
        }
    }

    @MainActor
    static func matches(_ p: Purchase, category: VaultCategory) -> Bool {
        switch category {
        case .all: true
        case .purchases: p.subscription == nil && !p.isBill && !p.isTravel && p.documentType != .insurance
        case .subscriptions: p.subscription != nil && p.documentType != .insurance
        case .bills: p.isBill
        case .warranties: !p.warranties.isEmpty
        case .travel: p.isTravel
        case .insurance: p.documentType == .insurance || p.merchantCategory == .insurance
        case .family: p.householdID != nil || p.sharedBy != nil
        case .documents: !p.documents.isEmpty
        }
    }
}


/// No document? Type it in. Uses the same review screen, so the purchase graph and rules are identical.
struct ManualPurchaseSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Group {
                if saving {
                    ProcessingView(step: 3)
                } else {
                    DocumentReviewView(document: blank, sourceDescription: "Entered by hand", startEditing: true) { doc in
                        saving = true
                        Task {
                            _ = try? await env.repository.save(document: doc, files: [])
                            env.settings.capturesUsed += 1
                            Haptics.scanSucceeded()
                            dismiss()
                        }
                    } onCancel: { dismiss() }
                }
            }
            .leverScreenBackground()
            .navigationTitle("Add purchase")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var blank: PurchaseDocument {
        var doc = PurchaseDocument(rawText: "", currencyCode: env.currencyCode)
        doc.documentType = .receipt
        doc.purchaseDate = .now
        doc.providerName = "Entered manually"
        doc.fieldConfidences = ["purchaseDate": 1.0]
        return doc
    }
}


enum VaultSort: String, CaseIterable, Identifiable {
    case recent, amount, nextEvent, name
    var id: String { rawValue }
    var title: String {
        switch self {
        case .recent: "Newest"
        case .amount: "Highest amount"
        case .nextEvent: "Next deadline"
        case .name: "Name"
        }
    }

    @MainActor
    func apply(_ items: [Purchase]) -> [Purchase] {
        switch self {
        case .recent: items.sorted { ($0.purchaseDate ?? $0.createdAt) > ($1.purchaseDate ?? $1.createdAt) }
        case .amount: items.sorted { $0.amount > $1.amount }
        case .name: items.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .nextEvent: items.sorted { (Self.next($0) ?? .distantFuture) < (Self.next($1) ?? .distantFuture) }
        }
    }

    @MainActor
    private static func next(_ p: Purchase) -> Date? {
        let now = Date.now
        var dates: [Date] = []
        if let d = p.returnWindow?.deadline, d >= now { dates.append(d) }
        if let d = p.subscription?.nextBillingDate, p.subscription?.status != .cancelled, d >= now { dates.append(d) }
        dates += p.warranties.compactMap(\.endDate).filter { $0 >= now }
        return dates.min()
    }
}
