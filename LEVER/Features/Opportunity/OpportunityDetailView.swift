import SwiftUI
import MessageUI

struct OpportunityDetailView: View {
    @Environment(AppEnvironment.self) private var env
    @Bindable var opportunity: Opportunity
    var onFinished: (() -> Void)? = nil

    @State private var plan: ActionPlan?
    @State private var showFight = false
    @State private var showNegotiation = false
    @State private var showSavingsSheet = false
    @State private var showWhy = false
    @State private var showDismissConfirm = false
    @State private var copied = false
    @State private var calendarResult: Bool?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                header
                if let plan { actionPlan(plan) } else { ProgressView().frame(maxWidth: .infinity) }
                evidence
                if let purchase = opportunity.purchase {
                    NavigationLink {
                        PurchaseDetailView(purchase: purchase)
                    } label: {
                        PurchaseRow(purchase: purchase).leverCard(padding: Spacing.sm)
                    }
                    .buttonStyle(.plain)
                }
                actions
            }
            .padding(Spacing.md)
            .padding(.bottom, Spacing.xl)
        }
        .leverScreenBackground()
        .navigationTitle(opportunity.type.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task { plan = await env.repository.ensureActionPlan(for: opportunity) }
        .sheet(isPresented: $showFight) {
            if let plan { FightForMeView(opportunity: opportunity, plan: plan) { showFight = false; showSavingsSheet = true } }
        }
        .sheet(isPresented: $showNegotiation) { NegotiationView(opportunity: opportunity) }
        .sheet(isPresented: $showSavingsSheet) {
            SavingsConfirmationSheet(opportunity: opportunity) {
                showSavingsSheet = false
                onFinished?()
            }
        }
        .confirmationDialog("Dismiss this opportunity?", isPresented: $showDismissConfirm, titleVisibility: .visible) {
            Button("Not relevant to me", role: .destructive) {
                env.repository.update(opportunity, status: .dismissed)
                onFinished?()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                MerchantMonogram(name: opportunity.merchantName, category: opportunity.purchase?.merchantCategory ?? .other, size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(opportunity.merchantName).font(LeverFont.headline)
                    LaneTag(lane: opportunity.lane)
                }
                Spacer()
                if let deadline = opportunity.deadline { DeadlineBadge(date: deadline, prefix: "Deadline ") }
            }
            Text(opportunity.title).font(LeverFont.display).fixedSize(horizontal: false, vertical: true)
            if let savings = opportunity.estimatedSavings, savings > 0 {
                VStack(alignment: .leading, spacing: 2) {
                    Text(opportunity.type == .returnDeadline ? "Money at stake" : "Potential saving")
                        .font(LeverFont.caption).foregroundStyle(LeverColor.inkSecondary)
                    MoneyAmount(amount: savings, currencyCode: opportunity.currencyCode, size: .hero, tint: LeverColor.money)
                }
            }
            Text(opportunity.detail).font(LeverFont.body).foregroundStyle(LeverColor.inkSecondary)
            HStack(spacing: Spacing.xs) {
                ConfidenceBadge(confidence: opportunity.confidence)
                Text("Checked \(opportunity.lastCheckedAt.formatted(.relative(presentation: .named)))")
                    .font(LeverFont.caption).foregroundStyle(LeverColor.inkTertiary)
            }
            if opportunity.qualifiesForFightForMe {
                Button {
                    env.analytics.track(.actionStarted, properties: ["type": opportunity.type.rawValue, "mode": "fight"])
                    showFight = true
                } label: {
                    VStack(spacing: 2) {
                        Text("FIGHT FOR ME").font(.system(.headline, design: .rounded).weight(.heavy)).tracking(1.5)
                        Text("Prepare everything. I'll approve before anything is sent.").font(.caption).opacity(0.85)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.money)
                .disabled(plan == nil)
                .accessibilityIdentifier("fightForMeButton")
                .padding(.top, Spacing.xs)
            }
        }
    }

    private func actionPlan(_ plan: ActionPlan) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: "Recommended action")
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(plan.summary).font(LeverFont.headline)
                Text(plan.whyItMatters).font(LeverFont.callout).foregroundStyle(LeverColor.inkSecondary)
                ForEach(Array(plan.steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                        Text("\(index + 1)")
                            .font(.caption.weight(.bold)).monospacedDigit()
                            .frame(width: 22, height: 22)
                            .background(LeverColor.surfaceElevated, in: Circle())
                        Text(step).font(LeverFont.callout)
                    }
                }
                if let message = plan.messageDraft {
                    Divider().padding(.vertical, Spacing.xxs)
                    Text("Message draft").font(LeverFont.label).foregroundStyle(LeverColor.inkSecondary)
                    Text(message).font(LeverFont.callout).textSelection(.enabled)
                        .padding(Spacing.sm)
                        .background(LeverColor.surfaceElevated, in: RoundedRectangle(cornerRadius: Radius.sm))
                    HStack(spacing: Spacing.xs) {
                        Button(copied ? "Copied" : "Copy message") {
                            UIPasteboard.general.string = message
                            copied = true
                            Haptics.actionCompleted()
                            env.analytics.track(.actionStarted, properties: ["type": opportunity.type.rawValue, "mode": "copy"])
                        }
                        .buttonStyle(.compact)
                        ShareLink(item: message) { Text("Share") }.buttonStyle(.compact(LeverColor.inkSecondary))
                        if let url = supportURL {
                            Link(destination: url) { Text("Open \(opportunity.merchantName)") }.buttonStyle(.compact(LeverColor.inkSecondary))
                        }
                    }
                }
                if let script = plan.callScript {
                    DisclosureGroup {
                        Text(script).font(LeverFont.callout).textSelection(.enabled).padding(.top, Spacing.xs)
                    } label: {
                        Label("Call script", systemImage: "phone").font(LeverFont.label).foregroundStyle(LeverColor.inkSecondary)
                    }
                }
                Text("Generated by \(plan.generatedBy). Review before you send anything.")
                    .font(.caption2).foregroundStyle(LeverColor.inkTertiary)
            }
            .leverCard()
        }
    }

    private var evidence: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Button {
                withAnimation(Motion.snappy) { showWhy.toggle() }
            } label: {
                HStack {
                    Label("Why am I seeing this?", systemImage: "questionmark.circle")
                        .font(LeverFont.label).foregroundStyle(LeverColor.ink)
                    Spacer()
                    Image(systemName: showWhy ? "chevron.up" : "chevron.down").font(.caption.weight(.semibold)).foregroundStyle(LeverColor.inkSecondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("whyButton")
            if showWhy {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    ForEach(opportunity.evidence, id: \.persistentModelID) { item in
                        VStack(alignment: .leading, spacing: 3) {
                            EvidenceKindTag(kind: item.kind)
                            Text(item.statement).font(LeverFont.callout)
                            Text("Source: \(item.source) · \(item.checkedAt.leverShort)").font(.caption2).foregroundStyle(LeverColor.inkTertiary)
                        }
                    }
                    if opportunity.evidence.isEmpty {
                        Text(opportunity.recommendedAction).font(LeverFont.callout)
                    }
                }
                .leverCard()
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var actions: some View {
        VStack(spacing: Spacing.xs) {
            if let deadline = opportunity.deadline, opportunity.isActionable {
                Button {
                    Task {
                        let ok = await env.calendar.addDeadline(title: "LEVER: \(opportunity.title)", notes: opportunity.recommendedAction, date: deadline)
                        calendarResult = ok
                        if ok { Haptics.actionCompleted() }
                    }
                } label: {
                    Label(calendarResult == true ? "Added to Calendar" : "Add deadline to Calendar", systemImage: calendarResult == true ? "checkmark.circle.fill" : "calendar.badge.plus")
                }
                .buttonStyle(.secondary)
                .disabled(calendarResult == true)
                if calendarResult == false {
                    Text("Calendar access wasn't granted. You can allow it in Settings → Privacy → Calendars.").font(LeverFont.caption).foregroundStyle(LeverColor.urgent)
                }
            }
            if opportunity.type == .negotiation || opportunity.type == .subscriptionRenewal {
                Button("Prepare negotiation") { showNegotiation = true }.buttonStyle(.secondary)
                    .accessibilityIdentifier("prepareNegotiationButton")
            }
            if opportunity.isActionable {
                Button("Mark resolved") {
                    env.analytics.track(.actionCompleted, properties: ["type": opportunity.type.rawValue])
                    showSavingsSheet = true
                }
                .buttonStyle(.primary)
                .accessibilityIdentifier("markResolvedButton")
                Button("Dismiss") { showDismissConfirm = true }
                    .font(LeverFont.callout.weight(.medium)).foregroundStyle(LeverColor.inkSecondary)
                    .padding(.top, Spacing.xxs)
            } else {
                InsightBanner(symbol: "checkmark.circle.fill", title: "This opportunity is \(opportunity.status.displayName.lowercased()).", tint: LeverColor.inkSecondary)
            }
        }
    }

    private var supportURL: URL? {
        guard let domain = opportunity.purchase?.merchant?.domain ?? MerchantDirectory().entry(named: opportunity.merchantName)?.domain else { return nil }
        return URL(string: "https://\(domain)")
    }
}
