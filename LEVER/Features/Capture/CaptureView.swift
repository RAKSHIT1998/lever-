import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct CaptureView: View {
    @Environment(AppEnvironment.self) private var env
    var embeddedInOnboarding = false
    var onFinished: (() -> Void)? = nil

    @State private var model: CaptureViewModel?
    @State private var showScanner = false
    @State private var showFileImporter = false
    @State private var pasteRequest: PasteRequest?
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showScreenshots = false

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                Color.clear
            }
        }
        .task {
            if model == nil { model = CaptureViewModel(env: env) }
            env.refreshInboxCount()
        }
    }

    @ViewBuilder
    private func content(_ model: CaptureViewModel) -> some View {
        NavigationStack {
            ZStack {
                switch model.phase {
                case .idle:
                    idle(model)
                case .processing(let step):
                    ProcessingView(step: step)
                case .review:
                    if let doc = model.document {
                        DocumentReviewView(document: doc, sourceDescription: model.rawInputDescription) { edited in
                            model.document = edited
                            Task { await model.confirmAndSave() }
                        } onCancel: {
                            model.reset()
                        }
                    }
                case .saving:
                    ProcessingView(step: 3)
                case .result:
                    if let purchase = model.savedPurchase {
                        MagicMomentView(purchase: purchase, opportunities: model.foundOpportunities) {
                            finishFlow(model)
                        }
                    }
                case .statement(let transactions, let text):
                    StatementReviewView(transactions: transactions, source: "Statement · \(model.rawInputDescription)", statementText: text) { _ in
                        finishFlow(model)
                    }
                case .failed(let message):
                    failure(message, model)
                }
            }
            .leverScreenBackground()
            .navigationTitle(model.phase == .idle ? "Capture" : "")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if embeddedInOnboarding {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Close") { onFinished?() }
                    }
                } else {
                    ToolbarItem(placement: .topBarTrailing) { ProfileButton() }
                }
            }
            .fullScreenCover(isPresented: $showScanner) {
                DocumentScannerView { images in
                    showScanner = false
                    Task { await model.process(images: images) }
                } onCancel: {
                    showScanner = false
                }
                .ignoresSafeArea()
            }
            .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.pdf, .image, .plainText, .emailMessage, .commaSeparatedText, .tabSeparatedText], allowsMultipleSelection: false) { result in
                if case .success(let urls) = result, let url = urls.first {
                    Task { await model.process(fileURL: url) }
                }
            }
            .sheet(item: $pasteRequest) { request in
                PasteSheetView(initialText: request.text) { text in
                    pasteRequest = nil
                    Task { await model.process(text: text) }
                } onCancel: {
                    pasteRequest = nil
                }
            }
            .sheet(isPresented: $showScreenshots) { ScreenshotPickerSheet() }
            .onChange(of: env.router.pendingScreenshot) { _, image in
                guard let image else { return }
                env.router.pendingScreenshot = nil
                Task { await model.process(images: [image]) }
            }
            .onAppear {
                if let image = env.router.pendingScreenshot {
                    env.router.pendingScreenshot = nil
                    Task { await model.process(images: [image]) }
                }
            }
            .onChange(of: photoItems) { _, items in
                guard let item = items.first else { return }
                photoItems = []
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        await model.process(images: [image])
                    }
                }
            }
        }
    }

    private func finishFlow(_ model: CaptureViewModel) {
        model.reset()
        if embeddedInOnboarding {
            onFinished?()
        } else {
            env.router.selectedTab = .home
            maybeShowPaywall()
        }
    }

    /// Value first, paywall second: shown only after the free captures are used and LEVER has found something.
    private func maybeShowPaywall() {
        guard !env.store.isPro, env.settings.capturesUsed >= AppSettings.freeCaptureLimit else { return }
        env.settings.paywallSeenAt = .now
        env.router.showPaywall = true
    }

    // MARK: - Idle

    private func idle(_ model: CaptureViewModel) -> some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                if !model.canCapture {
                    limitReached
                } else {
                    Button {
                        guard model.canCapture else { return }
                        if DocumentScannerView.isSupported { showScanner = true } else { showFileImporter = true }
                    } label: {
                        VStack(spacing: Spacing.sm) {
                            ZStack {
                                Circle().strokeBorder(LeverColor.hairline, lineWidth: 1).frame(width: 212, height: 212)
                                Circle().strokeBorder(LeverColor.hairline, lineWidth: 1).frame(width: 170, height: 170)
                                Circle()
                                    .fill(LinearGradient(colors: [LeverColor.inkPanelTop, LeverColor.inkPanelBottom], startPoint: .top, endPoint: .bottom))
                                    .frame(width: 128, height: 128)
                                Image(systemName: "viewfinder")
                                    .font(.system(size: 48, weight: .light))
                                    .foregroundStyle(LeverColor.onInk)
                            }
                            .shadow(color: .black.opacity(0.18), radius: 24, y: 12)
                            Text("Scan a receipt, bill or screen")
                                .font(LeverFont.headline)
                                .foregroundStyle(LeverColor.ink)
                            Text("Read on this iPhone. Nothing is uploaded.")
                                .font(LeverFont.caption)
                                .foregroundStyle(LeverColor.inkSecondary)
                        }
                        .padding(.vertical, Spacing.xl)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("captureCameraButton")
                    .accessibilityLabel("Scan a document with the camera")
                }

                if env.pendingInboxCount > 0 {
                    inbox(model)
                }
                if env.pendingScreenshotCount > 0 {
                    Button { showScreenshots = true } label: {
                        InsightBanner(symbol: "rectangle.dashed.badge.record", title: "\(env.pendingScreenshotCount) new screenshot\(env.pendingScreenshotCount == 1 ? "" : "s")", message: "Tap to see if any are receipts, renewals or bookings.", tint: LeverColor.money)
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    SectionHeader(title: "Or choose")
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.xs) {
                        PhotosPicker(selection: $photoItems, maxSelectionCount: 1, matching: .any(of: [.images, .screenshots])) {
                            SourceTile(symbol: "photo.on.rectangle", title: "Photo")
                        }
                        .disabled(!model.canCapture)
                        PhotosPicker(selection: $photoItems, maxSelectionCount: 1, matching: .screenshots) {
                            SourceTile(symbol: "rectangle.dashed.badge.record", title: "Screenshot")
                        }
                        .disabled(!model.canCapture)
                        Button { showFileImporter = true } label: { SourceTile(symbol: "doc.richtext", title: "PDF") }
                            .disabled(!model.canCapture)
                        Button { showFileImporter = true } label: { SourceTile(symbol: "building.columns", title: "Statement", hint: "CSV · PDF") }
                            .disabled(!model.canCapture)
                            .accessibilityIdentifier("captureStatementButton")
                        Button { pasteRequest = PasteRequest(text: Self.pasteFixture ?? UIPasteboard.general.string ?? "") } label: { SourceTile(symbol: "doc.on.clipboard", title: "Paste text") }
                            .disabled(!model.canCapture)
                            .accessibilityIdentifier("capturePasteButton")
                        SourceTile(symbol: "square.and.arrow.up", title: "Share Sheet", hint: "From any app")
                    }
                    .buttonStyle(.plain)
                }

                if !env.store.isPro {
                    Text(model.remainingFree > 0 ? "\(model.remainingFree) free capture\(model.remainingFree == 1 ? "" : "s") left" : "Free captures used")
                        .font(LeverFont.caption)
                        .foregroundStyle(LeverColor.inkTertiary)
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, Spacing.xl)
        }
    }

    private var limitReached: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "lock.shield").font(.system(size: 36, weight: .light)).foregroundStyle(LeverColor.inkSecondary)
            Text("You've used your free captures.").font(LeverFont.title).multilineTextAlignment(.center)
            Text("LEVER Pro unlocks unlimited captures and continuous protection.").font(LeverFont.callout).foregroundStyle(LeverColor.inkSecondary).multilineTextAlignment(.center)
            Button("See LEVER Pro") { env.router.showPaywall = true }.buttonStyle(.primary)
        }
        .padding(Spacing.lg)
        .leverCard()
    }

    private func inbox(_ model: CaptureViewModel) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: "Shared to LEVER")
            ForEach(env.inbox.pending()) { item in
                Button {
                    Task { await model.process(inbox: item) }
                } label: {
                    HStack {
                        Image(systemName: item.kind == .pdf ? "doc.richtext" : item.kind == .image ? "photo" : item.kind == .transfer ? "person.2.fill" : "text.alignleft")
                            .foregroundStyle(LeverColor.inkSecondary)
                        VStack(alignment: .leading) {
                            Text(item.kind == .url ? "Link" : item.kind == .transfer ? "Shared by family" : item.kind.rawValue.capitalized).font(LeverFont.headline)
                            Text(item.createdAt.formatted(.relative(presentation: .named))).font(LeverFont.caption).foregroundStyle(LeverColor.inkSecondary)
                        }
                        Spacer()
                        Text("Review").font(LeverFont.label).foregroundStyle(LeverColor.money)
                    }
                    .leverCard(padding: Spacing.sm)
                }
                .buttonStyle(.plain)
                .disabled(!model.canCapture)
                .swipeActions {
                    Button("Discard", role: .destructive) { env.inbox.consume(item); env.refreshInboxCount() }
                }
            }
        }
    }

    private func failure(_ message: String, _ model: CaptureViewModel) -> some View {
        VStack(spacing: Spacing.lg) {
            Spacer()
            Image(systemName: "text.viewfinder").font(.system(size: 40, weight: .light)).foregroundStyle(LeverColor.inkSecondary)
            Text("LEVER couldn't confidently read this.").font(LeverFont.title).multilineTextAlignment(.center)
            Text(message).font(LeverFont.callout).foregroundStyle(LeverColor.inkSecondary).multilineTextAlignment(.center)
            Spacer()
            VStack(spacing: Spacing.xs) {
                Button("Try again") { model.reset() }.buttonStyle(.primary)
                Button("Enter manually") { model.startManualEntry() }.buttonStyle(.secondary)
                Button("Save document only") { Task { await model.saveDocumentOnly() } }
                    .font(LeverFont.callout.weight(.medium)).foregroundStyle(LeverColor.inkSecondary)
                    .padding(.top, Spacing.xs)
            }
        }
        .padding(Spacing.lg)
    }
}

extension CaptureView {
    /// UI tests pass `-paste-fixture statement` to pre-fill the paste sheet deterministically (typing multi-line text is flaky).
    static var pasteFixture: String? {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-ui-testing"), let i = args.firstIndex(of: "-paste-fixture"), i + 1 < args.count else { return nil }
        switch args[i + 1] {
        case "statement":
            return """
            Account Statement
            Date,Narration,Withdrawal Amt,Deposit Amt
            01/06/2026,UPI-NETFLIX.COM,1199.00,
            01/07/2026,UPI-NETFLIX.COM,1199.00,
            01/08/2026,UPI-NETFLIX.COM,1499.00,
            03/08/2026,UPI-SPOTIFY,119.00,
            01/07/2026,UPI-SPOTIFY,119.00,
            """
        default:
            return nil
        }
    }
}

/// Sheet payload — item-based presentation guarantees the sheet sees the text it was opened with.
struct PasteRequest: Identifiable {
    let id = UUID()
    let text: String
}

/// Owns its own text state so the Analyse button's enabled state always matches what's in the editor.
struct PasteSheetView: View {
    @State private var text: String
    let onAnalyse: (String) -> Void
    let onCancel: () -> Void

    init(initialText: String, onAnalyse: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        _text = State(initialValue: initialText)
        self.onAnalyse = onAnalyse
        self.onCancel = onCancel
    }

    private var isValid: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 4 }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Paste an email, receipt, confirmation or a bank statement. A product link works too.")
                    .font(LeverFont.callout).foregroundStyle(LeverColor.inkSecondary)
                TextEditor(text: $text)
                    .font(LeverFont.mono)
                    .scrollContentBackground(.hidden)
                    .padding(Spacing.sm)
                    .frame(minHeight: 220)
                    .background(LeverColor.surface, in: RoundedRectangle(cornerRadius: Radius.md))
                    .accessibilityIdentifier("pasteTextEditor")
                Button("Analyse") { onAnalyse(text) }
                    .buttonStyle(.primary)
                    .disabled(!isValid)
                    .accessibilityIdentifier("pasteAnalyseButton")
            }
            .padding(Spacing.md)
            .leverScreenBackground()
            .navigationTitle("Paste text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancel", action: onCancel) } }
        }
    }
}

struct SourceTile: View {
    let symbol: String
    let title: String
    var hint: String? = nil

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 20, weight: .medium)).foregroundStyle(LeverColor.ink)
            Text(title).font(LeverFont.caption).foregroundStyle(LeverColor.ink)
            if let hint { Text(hint).font(.caption2).foregroundStyle(LeverColor.inkTertiary) }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.md)
        .leverCard(padding: Spacing.xs)
        .contentShape(Rectangle())
    }
}

struct ProcessingView: View {
    let step: Int

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Spacer()
            Text("LEVER is reading.")
                .font(LeverFont.display)
            LoadingSteps(steps: CaptureViewModel.steps, currentIndex: step)
                .leverCard(padding: Spacing.lg)
            Spacer()
            Spacer()
        }
        .padding(Spacing.lg)
        .accessibilityIdentifier("processingView")
    }
}
