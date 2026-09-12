import SwiftUI

/// Five screens, no personal questions, straight to the first scan.
struct OnboardingView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var page = 0
    @State private var showCapture = false
    @State private var notificationsResult: Bool?

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                promise.tag(0)
                watches.tag(1)
                firstScan.tag(2)
                notifications.tag(3)
                ready.tag(4)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(Motion.snappy, value: page)

            HStack(spacing: 6) {
                ForEach(0..<5, id: \.self) { index in
                    Capsule()
                        .fill(index == page ? LeverColor.ink : LeverColor.hairline)
                        .frame(width: index == page ? 18 : 6, height: 6)
                        .animation(Motion.gentle, value: page)
                }
            }
            .padding(.bottom, Spacing.lg)
            .accessibilityHidden(true)
        }
        .leverScreenBackground()
        .fullScreenCover(isPresented: $showCapture) {
            NavigationStack {
                CaptureView(embeddedInOnboarding: true) {
                    showCapture = false
                    page = 3
                }
            }
        }
    }

    private func screen<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Spacer()
            content()
            Spacer()
        }
        .padding(.horizontal, Spacing.lg)
        .frame(maxWidth: .infinity)
    }

    private var promise: some View {
        screen {
            LeakStackIllustration()
                .padding(.bottom, Spacing.sm)
            Text("LEVER")
                .font(.caption.weight(.heavy)).tracking(2).foregroundStyle(LeverColor.inkSecondary)
            Text("What if you stopped leaving money on the table?")
                .font(LeverFont.hero(38))
                .foregroundStyle(LeverColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("Receipts, renewals, bookings, warranties. LEVER reads the fine print and finds the money you're about to lose.")
                .font(LeverFont.body).foregroundStyle(LeverColor.inkSecondary)
            Button("Continue") { page = 1 }.buttonStyle(.primary).accessibilityIdentifier("onboardingContinue")
        }
    }

    private var watches: some View {
        screen {
            Text("LEVER watches your purchases for")
                .font(LeverFont.display).foregroundStyle(LeverColor.ink)
            VStack(alignment: .leading, spacing: Spacing.sm) {
                ForEach([("arrow.uturn.backward.circle.fill", "Returns"), ("banknote.fill", "Refunds"), ("arrow.down.right.circle.fill", "Price drops"), ("arrow.triangle.2.circlepath", "Renewals"), ("shield.checkered", "Warranties"), ("bubble.left.and.text.bubble.right.fill", "Negotiations")], id: \.1) { symbol, title in
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: symbol).foregroundStyle(LeverColor.money).frame(width: 24)
                        Text(title).font(LeverFont.title)
                    }
                }
            }
            Button("Continue") { page = 2 }.buttonStyle(.primary).accessibilityIdentifier("onboardingContinue2")
        }
    }

    private var firstScan: some View {
        screen {
            Text("Show me your first purchase.")
                .font(LeverFont.display).foregroundStyle(LeverColor.ink)
            Text("A receipt, a screenshot of a renewal email, a booking confirmation — anything. Everything is read on this iPhone.")
                .font(LeverFont.body).foregroundStyle(LeverColor.inkSecondary)
            Button {
                showCapture = true
            } label: {
                Label("Scan something", systemImage: "viewfinder")
            }
            .buttonStyle(.primary)
            .accessibilityIdentifier("onboardingScan")
            Button("I'll do it later") { page = 3 }
                .accessibilityIdentifier("onboardingLater")
                .font(LeverFont.callout.weight(.medium))
                .foregroundStyle(LeverColor.inkSecondary)
                .frame(maxWidth: .infinity)
        }
    }

    private var notifications: some View {
        screen {
            Text("Deadlines don't wait.")
                .font(LeverFont.display).foregroundStyle(LeverColor.ink)
            Text("LEVER only notifies you about your money: a return window closing, a renewal you might not want, a warranty about to end. Never \"come back to the app\".")
                .font(LeverFont.body).foregroundStyle(LeverColor.inkSecondary)
            if let notificationsResult {
                InsightBanner(symbol: notificationsResult ? "bell.badge.fill" : "bell.slash.fill", title: notificationsResult ? "Reminders on" : "Reminders off", message: notificationsResult ? "You'll hear from LEVER only when money is at stake." : "You can turn these on later in Settings.", tint: notificationsResult ? LeverColor.money : LeverColor.inkSecondary)
            }
            Button(notificationsResult == nil ? "Turn on reminders" : "Continue") {
                if notificationsResult == nil {
                    Task {
                        let granted = await env.notifications.requestAuthorization()
                        env.settings.notificationsEnabled = granted
                        notificationsResult = granted
                        if granted { await env.repository.rescheduleAllReminders() }
                    }
                } else {
                    page = 4
                }
            }
            .buttonStyle(.primary)
            .accessibilityIdentifier("onboardingNotifications")
            if notificationsResult == nil {
                Button("Not now") { page = 4 }
                    .accessibilityIdentifier("onboardingNotNow")
                    .font(LeverFont.callout.weight(.medium))
                    .foregroundStyle(LeverColor.inkSecondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var ready: some View {
        let open = env.repository.openOpportunities()
        return screen {
            if let first = open.first {
                LaneTag(lane: first.lane)
                Text(first.title).font(LeverFont.display).foregroundStyle(LeverColor.ink)
                if let savings = first.estimatedSavings, savings > 0 {
                    MoneyAmount(amount: savings, currencyCode: first.currencyCode, size: .hero, tint: LeverColor.money)
                }
                Text(first.detail).font(LeverFont.body).foregroundStyle(LeverColor.inkSecondary)
            } else {
                Text("Your money deserves a second look.")
                    .font(LeverFont.display).foregroundStyle(LeverColor.ink)
                Text("Scan anything you've paid for and LEVER will tell you what it finds. The first three captures are free.")
                    .font(LeverFont.body).foregroundStyle(LeverColor.inkSecondary)
            }
            Button(open.isEmpty ? "Open LEVER" : "Show me") {
                env.settings.hasCompletedOnboarding = true
                try? env.container.mainContext.save()
            }
            .buttonStyle(.primary)
            .accessibilityIdentifier("onboardingFinish")
        }
    }
}


/// Three tilted mini-cards showing the kinds of leaks LEVER catches. Pure decoration — sample copy only.
struct LeakStackIllustration: View {
    @State private var shown = false

    private let cards: [(String, String, String, Color)] = [
        ("arrow.triangle.2.circlepath", "Netflix renews tomorrow", "Save ₹3,600/yr", LeverColor.opportunity),
        ("airplane", "Hotel price dropped", "Recover ₹7,400", LeverColor.money),
        ("shield.checkered", "MacBook warranty ends in 21 days", "₹1,49,990 protected", LeverColor.protection),
    ]

    var body: some View {
        ZStack {
            ForEach(Array(cards.enumerated()), id: \.offset) { index, card in
                HStack(spacing: Spacing.sm) {
                    ZStack {
                        Circle().fill(card.3.opacity(0.14))
                        Image(systemName: card.0).font(.footnote.weight(.semibold)).foregroundStyle(card.3)
                    }
                    .frame(width: 32, height: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(card.1).font(.footnote.weight(.semibold)).foregroundStyle(LeverColor.ink).lineLimit(1)
                        Text(card.2).font(.caption2.weight(.semibold)).foregroundStyle(card.3)
                    }
                    Spacer(minLength: 0)
                }
                .padding(Spacing.sm)
                .frame(width: 280)
                .background(LeverColor.surface, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(LeverColor.hairline))
                .shadow(color: .black.opacity(0.08), radius: 16, y: 8)
                .rotationEffect(.degrees(shown ? Double(index - 1) * 2.5 : 0))
                .offset(x: shown ? Double(index - 1) * 10 : 0, y: shown ? Double(index - 1) * 58 : 0)
                .opacity(shown ? 1 : 0)
                .animation(Motion.reveal.delay(Double(index) * 0.08), value: shown)
            }
        }
        .frame(height: 200)
        .frame(maxWidth: .infinity)
        .onAppear { shown = true }
        .accessibilityHidden(true)
    }
}
