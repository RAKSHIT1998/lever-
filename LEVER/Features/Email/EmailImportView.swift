import SwiftUI

/// Connect Gmail, scan the last 90 days for purchase-like mail, review what LEVER read, import what's real.
struct EmailImportView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var clientID: String = ""
    @State private var busy = false
    @State private var error: String?
    @State private var candidates: [Candidate] = []
    @State private var selected: Set<String> = []
    @State private var scanned = false
    @State private var imported = 0

    struct Candidate: Identifiable {
        let id: String
        let message: EmailMessage
        let document: PurchaseDocument
        let alreadyInVault: Bool
    }

    private var gmail: GmailImportSource { env.gmail }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("Email import").font(LeverFont.display)
                    Text("Order confirmations, receipts and renewal notices live in your inbox. LEVER can read the last 90 days — read-only, purchase-related searches only, parsed on this iPhone.")
                        .font(LeverFont.callout).foregroundStyle(LeverColor.inkSecondary)
                }

                if !gmail.isConfigured { setup } else { connection }

                if let error { InsightBanner(symbol: "exclamationmark.triangle.fill", title: error, tint: LeverColor.urgent) }

                if scanned {
                    if candidates.isEmpty {
                        InsightBanner(symbol: "tray", title: "No purchase-like emails found", message: "LEVER searched for receipts, orders, renewals and bookings in the last 90 days.", tint: LeverColor.inkSecondary)
                    } else {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text("\(candidates.count) purchase\(candidates.count == 1 ? "" : "s") found").font(LeverFont.title3)
                            Text("Uncheck anything that isn't yours or is already tracked. Low-confidence reads are marked.").font(LeverFont.callout).foregroundStyle(LeverColor.inkSecondary)
                        }
                        ForEach(candidates) { candidate in row(candidate) }
                        Button {
                            Task { await importSelected() }
                        } label: {
                            if busy { ProgressView().tint(LeverColor.background) } else { Text("Import \(selected.count) purchase\(selected.count == 1 ? "" : "s")") }
                        }
                        .buttonStyle(.money).disabled(selected.isEmpty || busy)
                        if imported > 0 { Text("Imported \(imported). They're in your Vault and being watched.").font(LeverFont.caption).foregroundStyle(LeverColor.money) }
                    }
                }
            }
            .padding(Spacing.md)
        }
        .leverScreenBackground()
        .navigationTitle("Email")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { clientID = gmail.clientID ?? "" }
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("One-time developer setup").font(LeverFont.headline)
            Text("Gmail access needs an OAuth client ID from Google Cloud (APIs & Services → Credentials → OAuth client ID → iOS, bundle ID com.rakshit1998.lever, with the Gmail API enabled). Paste it here; it's stored in the Keychain.")
                .font(LeverFont.callout).foregroundStyle(LeverColor.inkSecondary)
            TextField("xxxxxxxx.apps.googleusercontent.com", text: $clientID)
                .textInputAutocapitalization(.never).autocorrectionDisabled().font(LeverFont.mono)
                .padding(10).background(LeverColor.surfaceElevated, in: RoundedRectangle(cornerRadius: Radius.sm))
            Button("Save client ID") { gmail.clientID = clientID.trimmingCharacters(in: .whitespaces); error = nil }
                .buttonStyle(.compact).disabled(!clientID.contains(".apps.googleusercontent.com"))
        }
        .leverCard()
    }

    private var connection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Image(systemName: "envelope.fill").foregroundStyle(LeverColor.ink)
                VStack(alignment: .leading, spacing: 2) {
                    Text(gmail.isConnected ? (gmail.accountLabel ?? "Gmail connected") : "Gmail not connected").font(LeverFont.headline)
                    Text(gmail.isConnected ? "Read-only access. Disconnect any time." : "You'll sign in with Google and approve read-only access.").font(LeverFont.caption).foregroundStyle(LeverColor.inkSecondary)
                }
                Spacer()
            }
            HStack {
                if gmail.isConnected {
                    Button(busy ? "Scanning…" : "Scan last 90 days") { Task { await scan() } }.buttonStyle(.compact).disabled(busy)
                        .accessibilityIdentifier("emailScanButton")
                    Button("Disconnect") { gmail.disconnect(); candidates = []; scanned = false }.buttonStyle(.compact(LeverColor.inkSecondary))
                } else {
                    Button(busy ? "Connecting…" : "Connect Gmail") { Task { await connect() } }.buttonStyle(.compact).disabled(busy)
                        .accessibilityIdentifier("emailConnectButton")
                    Button("Change client ID") { gmail.clientID = nil; clientID = "" }.buttonStyle(.compact(LeverColor.inkSecondary))
                }
            }
        }
        .leverCard()
    }

    private func row(_ c: Candidate) -> some View {
        Button {
            if selected.contains(c.id) { selected.remove(c.id) } else { selected.insert(c.id) }
        } label: {
            HStack(alignment: .top, spacing: Spacing.sm) {
                MerchantMonogram(name: c.document.merchant ?? "?", category: c.document.merchantCategory, size: 38)
                VStack(alignment: .leading, spacing: 3) {
                    Text(c.document.displayTitle).font(LeverFont.headline).foregroundStyle(LeverColor.ink).lineLimit(2)
                    Text("\(c.message.subject) · \(c.message.date.leverShort)").font(LeverFont.caption).foregroundStyle(LeverColor.inkSecondary).lineLimit(1)
                    HStack(spacing: 6) {
                        ConfidenceBadge(confidence: c.document.overallConfidence)
                        if c.alreadyInVault { Text("Already in vault").font(.caption2.weight(.semibold)).foregroundStyle(LeverColor.inkTertiary) }
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    if let amount = c.document.amount { MoneyAmount(amount: amount, currencyCode: c.document.currencyCode, size: .small) }
                    Image(systemName: selected.contains(c.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(selected.contains(c.id) ? LeverColor.money : LeverColor.inkTertiary)
                }
            }
            .leverCard(padding: Spacing.sm, radius: Radius.md)
        }
        .buttonStyle(.plain)
    }

    private func connect() async {
        busy = true; error = nil
        do { try await gmail.connect() } catch { self.error = error.localizedDescription }
        busy = false
    }

    private func scan() async {
        busy = true; error = nil; imported = 0
        do {
            let messages = try await gmail.fetchCandidateMessages(days: 90)
            let existingOrders = Set(env.repository.allPurchases().compactMap(\.orderNumber))
            var found: [Candidate] = []
            for message in messages {
                guard let doc = try? await env.intelligence.extractDocument(from: .text(message.bodyText), currencyCode: env.currencyCode), doc.amount != nil, doc.merchant != nil else { continue }
                let dup = doc.orderNumber.map { existingOrders.contains($0) } ?? false
                found.append(Candidate(id: message.id, message: message, document: doc, alreadyInVault: dup))
            }
            candidates = found
            selected = Set(found.filter { !$0.alreadyInVault && $0.document.overallConfidence != .low }.map(\.id))
            scanned = true
        } catch { self.error = error.localizedDescription }
        busy = false
    }

    private func importSelected() async {
        busy = true
        var count = 0
        for c in candidates where selected.contains(c.id) {
            if (try? await env.repository.save(document: c.document, files: [])) != nil { count += 1 }
        }
        env.settings.capturesUsed += count
        imported = count
        candidates.removeAll { selected.contains($0.id) }
        selected = []
        busy = false
        if count > 0 { Haptics.scanSucceeded() }
    }
}
