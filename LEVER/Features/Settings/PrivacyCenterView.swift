import SwiftUI
import SwiftData

/// "What's stored, what's processed, what's shared" — and the delete-everything switch.
struct PrivacyCenterView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @Query private var purchases: [Purchase]
    @Query private var documents: [StoredDocument]
    @Query private var savings: [SavingsEvent]
    @State private var showDeleteConfirm = false
    @State private var exportURL: URL?
    @State private var deleted = false
    @State private var geminiKey = GeminiIntelligenceProvider.storedKey ?? ""
    @State private var geminiModel = GeminiIntelligenceProvider.storedModel
    @State private var geminiStatus: String?
    @State private var testingKey = false

    private func testGemini() async {
        testingKey = true
        defer { testingKey = false }
        let provider = GeminiIntelligenceProvider(apiKey: geminiKey.trimmingCharacters(in: .whitespaces), model: geminiModel.trimmingCharacters(in: .whitespaces))
        do {
            let e = try await provider.extract(text: "Amazon.in Order Confirmation\nOrder Total ₹1,499.00\nOrder date: 12 Sep 2026")
            geminiStatus = e.amount == 1499 ? "Works — read ₹1,499 from a test receipt." : "Works, but the test read looked off (amount \(e.amount.map { "\($0)" } ?? "nil")). Try another model."
        } catch {
            geminiStatus = error.localizedDescription
        }
    }

    var body: some View {
        @Bindable var settings = env.settings
        List {
            Section("What's stored on this iPhone") {
                LabeledContent("Purchases", value: "\(purchases.count)")
                LabeledContent("Documents", value: "\(documents.count) · \(ByteCountFormatter.string(fromByteCount: env.files.totalBytes, countStyle: .file))")
                LabeledContent("Savings records", value: "\(savings.count)")
                Text("Stored in an encrypted, Data Protection–backed database. Documents are protected until you unlock the device.").font(.caption2).foregroundStyle(LeverColor.inkTertiary)
            }

            Section("What's processed by AI") {
                Label(settings.cloudAIEnabled && geminiKey.isEmpty == false ? "On-device first; Gemini fills gaps when the local read is unsure." : "Text recognition and understanding run entirely on this iPhone.", systemImage: settings.cloudAIEnabled && !geminiKey.isEmpty ? "cloud" : "iphone")
                    .font(LeverFont.callout)
                Toggle("Cloud intelligence (Google Gemini, free tier)", isOn: Binding(get: { settings.cloudAIEnabled }, set: { on in settings.cloudAIEnabled = on; settings.cloudAIDecisionMade = true; env.cloudFlag?.isEnabled = on && !geminiKey.isEmpty }))
                if settings.cloudAIEnabled {
                    SecureField("Gemini API key", text: $geminiKey)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().font(LeverFont.mono)
                        .onChange(of: geminiKey) { _, new in
                            GeminiIntelligenceProvider.storedKey = new.trimmingCharacters(in: .whitespaces)
                            env.cloudFlag?.isEnabled = !new.isEmpty
                            geminiStatus = nil
                        }
                    TextField("Model", text: $geminiModel)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().font(LeverFont.mono)
                        .onChange(of: geminiModel) { _, new in GeminiIntelligenceProvider.storedModel = new.trimmingCharacters(in: .whitespaces) }
                    HStack {
                        Link("Get a free key", destination: URL(string: "https://aistudio.google.com/apikey")!)
                        Spacer()
                        Button(testingKey ? "Testing…" : "Test key") { Task { await testGemini() } }.disabled(geminiKey.isEmpty || testingKey)
                    }
                    if let geminiStatus { Text(geminiStatus).font(LeverFont.caption).foregroundStyle(geminiStatus.hasPrefix("Works") ? LeverColor.money : LeverColor.urgent) }
                }
                Text("What's sent: only the recognised text of a document, only when the on-device parser is unsure, only while this is on. Never images, PDFs, statements or your vault. Your key stays in the Keychain. Google's free tier may use inputs to improve its models — read their terms before enabling.")
                    .font(.caption2).foregroundStyle(LeverColor.inkTertiary)
            }

            Section("Merchant logos & rates") {
                Toggle("Show merchant logos", isOn: Binding(get: { settings.showMerchantLogos }, set: { settings.showMerchantLogos = $0 }))
                Text("Merchant names (e.g. \"Croma\") are matched to a website via Clearbit's free lookup and the site's icon is fetched from Google/DuckDuckGo favicon services — never amounts or documents. Exchange rates for other-currency totals come from the European Central Bank via frankfurter.dev, with no data sent.")
                    .font(.caption2).foregroundStyle(LeverColor.inkTertiary)
            }

            Section("What's shared") {
                Label("Nothing is sold. No personal data leaves the device.", systemImage: "hand.raised.fill").font(LeverFont.callout)
                Toggle("Anonymous product analytics", isOn: Binding(get: { settings.analyticsEnabled }, set: { settings.analyticsEnabled = $0; env.analytics.isEnabled = $0 }))
                Text("Event names only (e.g. capture_completed). Never merchants, amounts, text or images. Currently logged locally.")
                    .font(.caption2).foregroundStyle(LeverColor.inkTertiary)
                LabeledContent("Widgets see", value: "Totals and short titles")
            }

            Section("Your data") {
                Button {
                    if let data = env.repository.exportJSON() {
                        let url = FileManager.default.temporaryDirectory.appendingPathComponent("LEVER-export.json")
                        try? data.write(to: url, options: [.atomic, .completeFileProtection])
                        exportURL = url
                    }
                } label: { Label("Export everything (JSON)", systemImage: "square.and.arrow.up") }
                Button(role: .destructive) { showDeleteConfirm = true } label: { Label("Delete everything", systemImage: "trash") }
                    .accessibilityIdentifier("deleteEverythingButton")
            }
        }
        .scrollContentBackground(.hidden)
        .leverScreenBackground()
        .navigationTitle("Privacy Center")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $exportURL) { url in ShareSheet(items: [url]) }
        .confirmationDialog("Delete every purchase, document, saving and setting from this iPhone?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete everything", role: .destructive) {
                Task {
                    await env.repository.deleteEverything()
                    env.settings.hasCompletedOnboarding = true
                    deleted = true
                    dismiss()
                }
            }
        } message: {
            Text("This can't be undone. Reminders and widgets are cleared too.")
        }
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
