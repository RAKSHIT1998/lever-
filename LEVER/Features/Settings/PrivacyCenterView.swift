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
                Label(env.intelligence.processesOnDevice ? "Text recognition and understanding run on this iPhone." : "Documents are sent to \(env.intelligence.name).", systemImage: env.intelligence.processesOnDevice ? "iphone" : "cloud")
                    .font(LeverFont.callout)
                Toggle("Allow cloud intelligence", isOn: $settings.cloudAIEnabled)
                    .disabled(true)
                Text("Cloud processing isn't available in this version. When it is, it will be off by default, opt-in, and clearly indicated while running. LEVER never uploads documents silently.")
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
