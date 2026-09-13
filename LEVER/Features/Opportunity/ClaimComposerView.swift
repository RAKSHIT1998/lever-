import SwiftUI

/// Warranty, return or refund claim: LEVER fills in every fact it has; the user adds the issue and sends it themselves.
struct ClaimComposerView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    let opportunity: Opportunity

    enum Kind: String, CaseIterable, Identifiable {
        case warranty = "Warranty claim", returnRequest = "Return request", refund = "Refund request"
        var id: String { rawValue }
    }

    @State private var kind: Kind
    @State private var issue = ""
    @State private var draft: ClaimDraft?
    @State private var copied = false

    init(opportunity: Opportunity) {
        self.opportunity = opportunity
        switch opportunity.type {
        case .returnDeadline: _kind = State(initialValue: .returnRequest)
        case .refund, .duplicateCharge, .feeDetection, .priceDrop, .travelPriceChange: _kind = State(initialValue: .refund)
        default: _kind = State(initialValue: .warranty)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    Picker("Type", selection: $kind) { ForEach(Kind.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(kind == .warranty ? "What's wrong with it?" : "Reason").font(LeverFont.headline)
                        TextField(kind == .warranty ? "e.g. Battery drains from 100% to 20% in two hours since last week" : "e.g. Doesn't fit / arrived damaged / charged twice", text: $issue, axis: .vertical)
                            .lineLimit(3...6).font(LeverFont.callout)
                            .padding(10).background(LeverColor.surfaceElevated, in: RoundedRectangle(cornerRadius: Radius.sm))
                            .accessibilityIdentifier("claimIssueField")
                        Text("LEVER fills in purchase date, price, order and serial numbers from your document. Unknowns stay as [brackets] for you to complete.")
                            .font(.caption2).foregroundStyle(LeverColor.inkTertiary)
                    }
                    .leverCard()

                    Button("Draft the claim") { draft = make() ; Haptics.actionCompleted() }.buttonStyle(.primary).accessibilityIdentifier("claimDraftButton")

                    if let draft {
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text(draft.subject).font(LeverFont.headline)
                            Text(draft.body).font(LeverFont.callout).textSelection(.enabled)
                        }
                        .leverCard()
                        HStack(spacing: Spacing.xs) {
                            Button(copied ? "Copied" : "Copy") { UIPasteboard.general.string = "\(draft.subject)\n\n\(draft.body)"; copied = true }.buttonStyle(.compact)
                            ShareLink(item: "\(draft.subject)\n\n\(draft.body)") { Text("Share") }.buttonStyle(.compact(LeverColor.inkSecondary))
                            if let mail = mailURL(draft) { Link(destination: mail) { Text("Open in Mail") }.buttonStyle(.compact(LeverColor.inkSecondary)) }
                        }
                        Text("Nothing is sent until you press send in your own mail or chat app.").font(.caption2).foregroundStyle(LeverColor.inkTertiary)
                    }
                }
                .padding(Spacing.md)
            }
            .leverScreenBackground()
            .navigationTitle("Compose claim")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } } }
        }
    }

    private func make() -> ClaimDraft {
        let snapshot = OpportunitySnapshot(opportunity)
        let generator = ClaimGenerator()
        let trimmed = issue.trimmingCharacters(in: .whitespacesAndNewlines)
        switch kind {
        case .warranty: return generator.warrantyClaim(for: snapshot, issue: trimmed.isEmpty ? nil : trimmed)
        case .returnRequest:
            var d = generator.returnRequest(for: snapshot)
            if !trimmed.isEmpty { d.body = d.body.replacingOccurrences(of: "[reason for return]", with: trimmed) }
            return d
        case .refund:
            var d = generator.refundRequest(for: snapshot)
            if !trimmed.isEmpty { d.body = d.body.replacingOccurrences(of: "Details: \(opportunity.detail)", with: "Details: \(trimmed)") }
            return d
        }
    }

    private func mailURL(_ draft: ClaimDraft) -> URL? {
        var c = URLComponents()
        c.scheme = "mailto"
        c.path = ""
        c.queryItems = [URLQueryItem(name: "subject", value: draft.subject), URLQueryItem(name: "body", value: draft.body)]
        return c.url
    }
}
