import SwiftUI
import UniformTypeIdentifiers
import Photos

/// "How LEVER knows" — every way spending reaches the app, with honest status and one-tap setup.
struct SourcesView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var showStatementImporter = false
    @State private var statementResult: (transactions: [StatementTransaction], text: String, source: String)?
    @State private var statementError: String?
    @State private var walletStatus: WalletTransactionSource.Status?
    @State private var walletBusy = false
    @State private var priceCheckResult: String?
    @State private var showScreenshots = false

    private var trackedPages: Int { env.repository.allPurchases().filter { $0.productURL != nil }.count }

    var body: some View {
        @Bindable var settings = env.settings
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("How LEVER knows").font(LeverFont.display)
                    Text("LEVER doesn't watch your bank account. Spending reaches it through the channels below — each one on this iPhone, each one your choice.")
                        .font(LeverFont.callout).foregroundStyle(LeverColor.inkSecondary)
                }

                source(symbol: "viewfinder", title: "Camera, Photos & Share Sheet", status: .on, detail: "Scan a receipt, pick a screenshot, or share anything from Mail, Safari, Files or Messages to LEVER.") {
                    Button("Open Capture") { env.router.selectedTab = .capture }.buttonStyle(.compact)
                }

                source(symbol: "rectangle.dashed.badge.record", title: "Screenshot watcher", status: settings.screenshotWatchEnabled ? .on : .available, detail: "When you screenshot a confirmation, renewal email or booking, LEVER notices on next open and offers to read it. Nothing is read until you tap.") {
                    Toggle("Watch new screenshots", isOn: Binding(get: { settings.screenshotWatchEnabled }, set: { on in
                        Task {
                            if on {
                                let access = await env.screenshots.requestAccess()
                                settings.screenshotWatchEnabled = access != .denied
                                settings.lastScreenshotCheck = .now
                            } else {
                                settings.screenshotWatchEnabled = false
                            }
                            env.refreshScreenshotCount()
                        }
                    }))
                    .tint(LeverColor.money)
                    .font(LeverFont.callout)
                    if settings.screenshotWatchEnabled && env.pendingScreenshotCount > 0 {
                        Button("Review \(env.pendingScreenshotCount) new screenshot\(env.pendingScreenshotCount == 1 ? "" : "s")") { showScreenshots = true }.buttonStyle(.compact)
                    }
                }

                source(symbol: "building.columns", title: "Bank & card statements", status: .available, detail: "Import a CSV or PDF statement. LEVER finds merchants that charge on a rhythm and turns them into watched subscriptions — the fastest way to see everything you're paying for.") {
                    Button("Import a statement") { showStatementImporter = true }.buttonStyle(.compact)
                        .accessibilityIdentifier("importStatementButton")
                    if let statementError { Text(statementError).font(LeverFont.caption).foregroundStyle(LeverColor.urgent) }
                }

                source(symbol: "wallet.pass", title: "Apple Wallet transactions", status: walletStatusKind, detail: walletDetail) {
                    Button(walletBusy ? "Connecting…" : (settings.walletConnected ? "Sync now" : "Connect Wallet")) {
                        Task { await connectWallet() }
                    }
                    .buttonStyle(.compact)
                    .disabled(walletBusy || walletUnavailable)
                }

                source(symbol: "tag", title: "Price tracking", status: settings.priceTrackingEnabled ? .on : .available, detail: "Paste a product link on any purchase and LEVER re-reads that page's listed price about once a day. Standard page metadata only — no scraping, no logins.") {
                    Toggle("Check tracked pages daily", isOn: $settings.priceTrackingEnabled).tint(LeverColor.money).font(LeverFont.callout)
                    HStack {
                        Text("\(trackedPages) page\(trackedPages == 1 ? "" : "s") tracked").font(LeverFont.caption).foregroundStyle(LeverColor.inkSecondary)
                        Spacer()
                        Button("Check now") {
                            Task {
                                let n = await env.repository.checkTrackedPrices(using: env.priceMonitor)
                                priceCheckResult = n == 0 ? "No price changes found." : "\(n) price\(n == 1 ? "" : "s") updated."
                            }
                        }
                        .buttonStyle(.compact(LeverColor.inkSecondary)).disabled(trackedPages == 0)
                    }
                    if let priceCheckResult { Text(priceCheckResult).font(LeverFont.caption).foregroundStyle(LeverColor.inkSecondary) }
                }

                source(symbol: "envelope", title: "Email (Gmail)", status: env.gmail.isConnected ? .on : .available, detail: env.gmail.isConfigured ? "Scan the last 90 days of receipts, orders and renewals. Read-only, parsed on this iPhone." : "Order confirmations and renewals live in your inbox. Share one from Mail today, or connect Gmail for a 90-day scan (needs a one-time OAuth client ID).") {
                    NavigationLink { EmailImportView() } label: { Text(env.gmail.isConnected ? "Scan inbox" : "Set up email import") }
                        .buttonStyle(.compact)
                        .accessibilityIdentifier("emailImportLink")
                }

                source(symbol: "bell.badge", title: "SMS bank alerts", status: .notPossible, detail: "iOS doesn't let apps read messages. Long-press a bank SMS → Share → LEVER, or screenshot it and let the watcher catch it.") {
                    EmptyView()
                }

                Text("Everything above runs on this iPhone. Nothing is uploaded, sold or shared.")
                    .font(.caption2).foregroundStyle(LeverColor.inkTertiary).frame(maxWidth: .infinity)
            }
            .padding(Spacing.md)
        }
        .leverScreenBackground()
        .navigationTitle("Sources")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $showStatementImporter, allowedContentTypes: [.commaSeparatedText, .pdf, .plainText, .tabSeparatedText], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first { Task { await importStatement(url) } }
        }
        .navigationDestination(isPresented: Binding(get: { statementResult != nil }, set: { if !$0 { statementResult = nil } })) {
            if let r = statementResult {
                StatementReviewView(transactions: r.transactions, source: r.source, statementText: r.text) { _ in statementResult = nil }
            }
        }
        .sheet(isPresented: $showScreenshots) { ScreenshotPickerSheet() }
        .task { if walletStatus == nil { walletStatus = env.wallet.status } }
    }

    // MARK: - Actions

    private func importStatement(_ url: URL) async {
        statementError = nil
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { statementError = "Couldn't open that file."; return }
        var text: String
        if url.pathExtension.lowercased() == "pdf" {
            guard let recognized = try? await OCRService().extractText(fromPDF: data) else { statementError = "Couldn't read that PDF."; return }
            text = recognized.joined
        } else {
            text = String(decoding: data, as: UTF8.self)
        }
        let transactions = StatementImporter().parse(text, defaultCurrency: env.currencyCode)
        guard transactions.count >= 2 else { statementError = "LEVER couldn't find dated transactions with amounts in that file. CSV exports from your bank work best."; return }
        statementResult = (transactions, text, "Statement · \(url.lastPathComponent)")
    }

    private func connectWallet() async {
        walletBusy = true
        defer { walletBusy = false }
        let status = await env.wallet.requestAccess()
        walletStatus = status
        guard status == .authorized else { return }
        env.settings.walletConnected = true
        if let transactions = try? await env.wallet.recentTransactions(), !transactions.isEmpty {
            env.settings.lastWalletSync = .now
            statementResult = (transactions, "", "Apple Wallet")
        }
    }

    private var walletUnavailable: Bool {
        if case .unavailable = walletStatus ?? .notDetermined { return true }
        return false
    }

    private var walletStatusKind: SourceStatus {
        switch walletStatus ?? .notDetermined {
        case .authorized: .on
        case .unavailable: .notPossible
        case .denied: .available
        case .notDetermined: .available
        }
    }

    private var walletDetail: String {
        switch walletStatus ?? .notDetermined {
        case .unavailable(let reason): "Apple Card and Apple Cash transactions via FinanceKit. \(reason)"
        case .denied: "Access was declined. You can allow it in Settings → Privacy & Security → Wallet."
        default: "Apple Card, Apple Cash and supported cards share transactions through Apple's FinanceKit — read on-device, with your permission, and analysed for repeating charges."
        }
    }

    // MARK: - Row

    enum SourceStatus { case on, available, notPossible }

    private func source<Content: View>(symbol: String, title: String, status: SourceStatus, detail: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: symbol).font(.body.weight(.semibold)).foregroundStyle(LeverColor.ink).frame(width: 26)
                Text(title).font(LeverFont.headline)
                Spacer()
                statusPill(status)
            }
            Text(detail).font(LeverFont.callout).foregroundStyle(LeverColor.inkSecondary).fixedSize(horizontal: false, vertical: true)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .leverCard()
    }

    private func statusPill(_ status: SourceStatus) -> some View {
        let (text, color): (String, Color) = switch status {
        case .on: ("ON", LeverColor.money)
        case .available: ("AVAILABLE", LeverColor.inkSecondary)
        case .notPossible: ("NOT ON iOS", LeverColor.inkTertiary)
        }
        return Text(text).font(.caption2.weight(.bold)).tracking(0.6).foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 4).background(color.opacity(0.12), in: Capsule())
    }
}

/// Thumbnails of screenshots taken since the last check. Tap one to read it.
struct ScreenshotPickerSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var assets: [PHAsset] = []
    @State private var thumbnails: [String: UIImage] = [:]
    @State private var loading: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                if assets.isEmpty {
                    EmptyState(symbol: "rectangle.dashed", title: "No new screenshots", message: "LEVER checks for screenshots taken since you last looked.")
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: Spacing.xs)], spacing: Spacing.xs) {
                        ForEach(assets, id: \.localIdentifier) { asset in
                            Button {
                                loading = asset.localIdentifier
                                Task {
                                    if let image = await env.screenshots.image(for: asset) {
                                        env.router.pendingScreenshot = image
                                        env.router.selectedTab = .capture
                                        dismiss()
                                    }
                                    loading = nil
                                }
                            } label: {
                                ZStack {
                                    RoundedRectangle(cornerRadius: Radius.sm).fill(LeverColor.surfaceElevated)
                                    if let thumb = thumbnails[asset.localIdentifier] { Image(uiImage: thumb).resizable().scaledToFill() }
                                    if loading == asset.localIdentifier { ProgressView() }
                                }
                                .frame(height: 180)
                                .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                            }
                            .buttonStyle(.plain)
                            .task { thumbnails[asset.localIdentifier] = await env.screenshots.image(for: asset, maxDimension: 300) }
                        }
                    }
                    .padding(Spacing.md)
                }
            }
            .leverScreenBackground()
            .navigationTitle("New screenshots")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Mark seen") {
                        env.settings.lastScreenshotCheck = .now
                        env.refreshScreenshotCount()
                        dismiss()
                    }
                }
            }
            .task { assets = env.screenshots.newScreenshots(since: env.settings.lastScreenshotCheck) }
        }
    }
}
