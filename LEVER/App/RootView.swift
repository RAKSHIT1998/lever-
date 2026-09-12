import SwiftUI

struct RootView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        @Bindable var router = env.router
        Group {
            if !env.settings.hasCompletedOnboarding {
                OnboardingView()
                    .transition(.opacity)
            } else if !env.isUnlocked {
                LockScreenView()
                    .transition(.opacity)
            } else {
                MainTabView()
                    .transition(.opacity)
            }
        }
        .animation(Motion.gentle, value: env.settings.hasCompletedOnboarding)
        .animation(Motion.gentle, value: env.isUnlocked)
        .sheet(isPresented: $router.showPaywall) {
            PaywallView()
        }
        .sheet(isPresented: $router.showSettings) {
            SettingsView()
        }
    }
}

struct MainTabView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        @Bindable var router = env.router
        TabView(selection: $router.selectedTab) {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(AppTab.home)
            CaptureView()
                .tabItem { Label("Capture", systemImage: "viewfinder") }
                .tag(AppTab.capture)
                .badge(env.pendingInboxCount)
            VaultView()
                .tabItem { Label("Vault", systemImage: "archivebox.fill") }
                .tag(AppTab.vault)
            SavingsView()
                .tabItem { Label("Savings", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(AppTab.savings)
        }
        .tint(LeverColor.ink)
    }
}

/// Biometric gate shown when "Require Face ID" is enabled.
struct LockScreenView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var failed = false

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()
            Image(systemName: "lock.fill")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(LeverColor.inkSecondary)
            Text("LEVER is locked")
                .font(LeverFont.title)
            Text("Your purchases, documents and savings are protected.")
                .font(LeverFont.callout)
                .foregroundStyle(LeverColor.inkSecondary)
                .multilineTextAlignment(.center)
            if failed {
                Text("Couldn't verify. Try again.")
                    .font(LeverFont.caption)
                    .foregroundStyle(LeverColor.urgent)
            }
            Spacer()
            Button("Unlock with \(env.biometrics.biometryName)") { Task { await unlock() } }
                .buttonStyle(.primary)
                .padding(.horizontal, Spacing.lg)
                .padding(.bottom, Spacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .leverScreenBackground()
        .task { await unlock() }
    }

    private func unlock() async {
        let ok = await env.biometrics.authenticate(reason: "Unlock your LEVER vault")
        env.isUnlocked = ok
        failed = !ok
    }
}

/// Top-right avatar/settings entry used on every tab.
struct ProfileButton: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        Button {
            env.router.showSettings = true
        } label: {
            ZStack {
                Circle().fill(LeverColor.surfaceElevated)
                Image(systemName: "person.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(LeverColor.inkSecondary)
            }
            .frame(width: 34, height: 34)
            .overlay(alignment: .topTrailing) {
                if env.store.isPro {
                    Circle().fill(LeverColor.money).frame(width: 9, height: 9).offset(x: 1, y: -1)
                }
            }
        }
        .accessibilityLabel("Profile and settings")
        .accessibilityIdentifier("profileButton")
    }
}
