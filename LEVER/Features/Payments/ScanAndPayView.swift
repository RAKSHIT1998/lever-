import SwiftUI
import VisionKit
@preconcurrency import Vision
import PhotosUI

/// Scan a merchant QR, pay with your own app, and LEVER logs the spend on the way back. Works for UPI (India)
/// with app hand-off, and for EMVCo rails (PIX, PayNow, PromptPay, DuitNow, QRIS) with copy-code + manual log.
struct ScanAndPayView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var request: PaymentRequest?
    @State private var amountText = ""
    @State private var manualPayload = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var scanning = true
    @State private var error: String?
    @State private var copied = false

    private var region: PaymentRegion { env.paymentRegion }
    private var scannerAvailable: Bool { DataScannerViewController.isSupported && DataScannerViewController.isAvailable }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                if let request { requestCard(request) } else { scannerSection }

                if request == nil {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        SectionHeader(title: "No camera? Other ways")
                        HStack(spacing: Spacing.xs) {
                            PhotosPicker(selection: $photoItem, matching: .images) {
                                SourceTile(symbol: "qrcode.viewfinder", title: "QR from photo")
                            }
                            .buttonStyle(.plain)
                            Button { scanning = false } label: { SourceTile(symbol: "keyboard", title: region.usesUPIURL ? "Type UPI ID" : "Paste code") }.buttonStyle(.plain)
                        }
                        if !scanning {
                            TextField(region.usesUPIURL ? "merchant@bank or upi://pay?… link" : "Paste the QR code text", text: $manualPayload, axis: .vertical)
                                .textInputAutocapitalization(.never).autocorrectionDisabled().font(LeverFont.mono).lineLimit(1...4)
                                .padding(10).background(LeverColor.surface, in: RoundedRectangle(cornerRadius: Radius.sm))
                                .accessibilityIdentifier("payManualField")
                            Button("Continue") { handle(payload: manualPayload) }.buttonStyle(.primary)
                                .disabled(manualPayload.trimmingCharacters(in: .whitespaces).count < 3)
                                .accessibilityIdentifier("payManualContinue")
                        }
                    }
                }
                if let error { InsightBanner(symbol: "exclamationmark.triangle.fill", title: error, tint: LeverColor.urgent) }

                Text("LEVER never moves money. It reads the merchant's QR, opens your \(region.railName) app to pay, and logs the spend when you're back — so every tap-to-pay ends up in your vault.")
                    .font(.caption2).foregroundStyle(LeverColor.inkTertiary)
            }
            .padding(Spacing.md)
        }
        .leverScreenBackground()
        .navigationTitle("Scan & Pay · \(region.railName)")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            photoItem = nil
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let payload = await Self.detectQR(in: data) { handle(payload: payload) }
                else { error = "No QR code found in that photo." }
            }
        }
    }

    @ViewBuilder
    private var scannerSection: some View {
        if scannerAvailable && scanning {
            QRScannerView { payload in handle(payload: payload) }
                .frame(height: 360)
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(LeverColor.hairline))
            Text("Point at the shop's \(region.railName) QR.").font(LeverFont.callout).foregroundStyle(LeverColor.inkSecondary).frame(maxWidth: .infinity)
        } else if scanning {
            InsightBanner(symbol: "camera.metering.unknown", title: "Live scanning isn't available here", message: "Use a photo of the QR or type the \(region.usesUPIURL ? "UPI ID" : "code") below.", tint: LeverColor.inkSecondary)
        }
    }

    private func requestCard(_ r: PaymentRequest) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                MerchantAvatar(name: r.merchantName ?? r.payeeAddress ?? "?", size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.merchantName ?? "Unknown merchant").font(LeverFont.title3)
                    if let payee = r.payeeAddress { Text(payee).font(LeverFont.mono).foregroundStyle(LeverColor.inkSecondary) }
                    Text("\(r.rail)\(r.countryCode.map { " · \($0)" } ?? "")").font(LeverFont.caption).foregroundStyle(LeverColor.inkTertiary)
                }
                Spacer()
            }
            if let amount = r.amount {
                HStack { Text("Amount").font(LeverFont.caption).foregroundStyle(LeverColor.inkSecondary); Spacer(); MoneyAmount(amount: amount, currencyCode: r.currencyCode, size: .large) }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Amount (\(r.currencyCode))").font(LeverFont.caption).foregroundStyle(LeverColor.inkSecondary)
                    TextField("0", text: $amountText).keyboardType(.decimalPad).font(LeverFont.hero(34)).accessibilityIdentifier("payAmountField")
                }
            }
            if let note = r.note, !note.isEmpty { Text(note).font(LeverFont.callout).foregroundStyle(LeverColor.inkSecondary) }
            Divider()
            if region.usesUPIURL && r.rail == "UPI" {
                Text("Pay with").font(LeverFont.label).foregroundStyle(LeverColor.inkSecondary)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.xs) {
                    ForEach(installedApps(for: r)) { app in
                        Button {
                            pay(r, with: app)
                        } label: {
                            Text(app.name).font(LeverFont.label).frame(maxWidth: .infinity).padding(.vertical, 12)
                                .background(LeverColor.ink, in: RoundedRectangle(cornerRadius: Radius.sm)).foregroundStyle(LeverColor.background)
                        }
                        .accessibilityIdentifier("payWith-\(app.scheme ?? "any")")
                    }
                }
            } else {
                Button {
                    UIPasteboard.general.string = r.rawPayload
                    copied = true
                    Haptics.actionCompleted()
                    env.pendingPayment = PendingPayment(request: r, amount: effectiveAmount(r), appName: region.apps.first?.name ?? "bank app", startedAt: .now)
                } label: { Label(copied ? "Code copied — paste it in your \(region.railName) app" : "Copy \(r.rail) code", systemImage: "doc.on.doc") }
                .buttonStyle(.primary)
                Button("I've paid this — log it") { env.pendingPayment = PendingPayment(request: r, amount: effectiveAmount(r), appName: region.apps.first?.name ?? "bank app", startedAt: .now); env.router.showPaymentLog = true }
                    .buttonStyle(.secondary)
            }
            Button("Scan something else") { request = nil; amountText = ""; scanning = true; copied = false }
                .font(LeverFont.callout.weight(.medium)).foregroundStyle(LeverColor.inkSecondary).frame(maxWidth: .infinity)
        }
        .leverCard()
    }

    private func effectiveAmount(_ r: PaymentRequest) -> Decimal? { r.amount ?? AmountParser.parseDecimal(amountText) }

    private func installedApps(for r: PaymentRequest) -> [PaymentApp] {
        let apps = region.apps.filter { app in
            guard let scheme = app.scheme, let url = URL(string: "\(scheme)://") else { return false }
            return UIApplication.shared.canOpenURL(url) || scheme == "upi"
        }
        return apps.isEmpty ? region.apps.filter { $0.scheme == "upi" } : apps
    }

    private func pay(_ r: PaymentRequest, with app: PaymentApp) {
        guard let template = app.template, let url = PaymentQRParser.upiURL(for: r, template: template, amount: effectiveAmount(r)) else { return }
        env.pendingPayment = PendingPayment(request: r, amount: effectiveAmount(r), appName: app.name, startedAt: .now)
        env.analytics.track(.actionStarted, properties: ["type": "scanAndPay", "app": app.name])
        UIApplication.shared.open(url) { ok in
            if !ok { Task { @MainActor in error = "\(app.name) didn't open. Try another app."; env.pendingPayment = nil } }
        }
    }

    private func handle(payload: String) {
        var text = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        // A bare VPA typed by hand becomes a UPI request.
        if region.usesUPIURL, text.contains("@"), !text.contains("://") { text = "upi://pay?pa=\(text)&cu=INR" }
        guard let parsed = PaymentQRParser.parse(text, defaultCurrency: region.currencyCode), parsed.isPayable else {
            error = "That doesn't look like a \(region.railName) payment code."
            return
        }
        error = nil
        request = parsed
        Haptics.scanSucceeded()
    }

    static func detectQR(in imageData: Data) async -> String? {
        guard let image = UIImage(data: imageData), let cg = image.cgImage else { return nil }
        return await withCheckedContinuation { continuation in
            let request = VNDetectBarcodesRequest { req, _ in
                let payload = (req.results as? [VNBarcodeObservation])?.first { $0.symbology == .qr }?.payloadStringValue
                continuation.resume(returning: payload)
            }
            request.symbologies = [.qr]
            DispatchQueue.global(qos: .userInitiated).async {
                do { try VNImageRequestHandler(cgImage: cg, orientation: CGImagePropertyOrientation(image.imageOrientation)).perform([request]) }
                catch { continuation.resume(returning: nil) }
            }
        }
    }
}

/// Live QR scanning with VisionKit. Calls back once per distinct payload.
struct QRScannerView: UIViewControllerRepresentable {
    var onPayload: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])], qualityLevel: .balanced, recognizesMultipleItems: false, isHighFrameRateTrackingEnabled: false, isHighlightingEnabled: true)
        vc.delegate = context.coordinator
        try? vc.startScanning()
        return vc
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}
    static func dismantleUIViewController(_ uiViewController: DataScannerViewController, coordinator: Coordinator) { uiViewController.stopScanning() }
    func makeCoordinator() -> Coordinator { Coordinator(onPayload: onPayload) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onPayload: (String) -> Void
        var last: String?
        init(onPayload: @escaping (String) -> Void) { self.onPayload = onPayload }
        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in addedItems { if case .barcode(let code) = item, let payload = code.payloadStringValue, payload != last { last = payload; onPayload(payload) } }
        }
    }
}

/// A payment the user just started from LEVER; confirmed (or not) when they come back.
struct PendingPayment: Identifiable, Equatable {
    var id: String { "\(request.payeeAddress ?? request.merchantName ?? "")-\(startedAt.timeIntervalSince1970)" }
    var request: PaymentRequest
    var amount: Decimal?
    var appName: String
    var startedAt: Date
}

/// "Did the ₹499 payment to Blue Tokai go through?" — the moment LEVER captures a spend at the source.
struct PaymentLogSheet: View {
    @Environment(AppEnvironment.self) private var env
    let pending: PendingPayment
    let onDone: () -> Void
    @State private var amountText: String
    @State private var note: String

    init(pending: PendingPayment, onDone: @escaping () -> Void) {
        self.pending = pending
        self.onDone = onDone
        _amountText = State(initialValue: pending.amount.map { "\($0)" } ?? "")
        _note = State(initialValue: pending.request.note ?? "")
    }

    private var amount: Decimal? { AmountParser.parseDecimal(amountText) }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Did the payment go through?").font(LeverFont.display)
                    Text("\(pending.request.merchantName ?? pending.request.payeeAddress ?? "Merchant") via \(pending.appName). Logging it keeps your spending honest and lets LEVER watch for duplicates and refunds.")
                        .font(LeverFont.callout).foregroundStyle(LeverColor.inkSecondary)
                }
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Amount (\(pending.request.currencyCode))").font(LeverFont.caption).foregroundStyle(LeverColor.inkSecondary)
                    TextField("0", text: $amountText).keyboardType(.decimalPad).font(LeverFont.hero(34)).accessibilityIdentifier("logAmountField")
                    TextField("What was it for? (optional)", text: $note).font(LeverFont.callout)
                        .padding(10).background(LeverColor.surfaceElevated, in: RoundedRectangle(cornerRadius: Radius.sm))
                }
                .leverCard()
                Spacer()
                Button("Yes, log \(amount.map { Money.format($0, code: pending.request.currencyCode) } ?? "it")") {
                    guard let amount, amount > 0 else { return }
                    Task {
                        await env.repository.logPayment(pending, amount: amount, note: note.isEmpty ? nil : note)
                        Haptics.savingConfirmed()
                        onDone()
                    }
                }
                .buttonStyle(.money).disabled((amount ?? 0) <= 0).accessibilityIdentifier("logPaymentYes")
                Button("No, it didn't happen", action: onDone).buttonStyle(.secondary)
            }
            .padding(Spacing.md)
            .leverScreenBackground()
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.large])
    }
}
