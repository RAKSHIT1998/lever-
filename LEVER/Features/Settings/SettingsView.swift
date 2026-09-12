import SwiftUI

struct SettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var biometricError: String?

    var body: some View {
        @Bindable var settings = env.settings
        NavigationStack {
            List {
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(env.store.isPro ? "LEVER Pro" : "LEVER Free").font(LeverFont.headline)
                            Text(env.store.isPro ? "Unlimited captures and continuous protection." : "\(EntitlementResolver.remainingFreeCaptures(capturesUsed: settings.capturesUsed)) free captures left").font(LeverFont.caption).foregroundStyle(LeverColor.inkSecondary)
                        }
                        Spacer()
                        if !env.store.isPro {
                            Button("Upgrade") { dismiss(); env.router.showPaywall = true }.buttonStyle(.compact)
                        }
                    }
                    if env.store.isPro {
                        Button("Manage subscription") {
                            if let url = URL(string: "https://apps.apple.com/account/subscriptions") { UIApplication.shared.open(url) }
                        }
                    }
                    Button("Restore purchases") { Task { await env.store.restore() } }
                }

                Section("Protection") {
                    Toggle("Money deadline reminders", isOn: Binding(
                        get: { settings.notificationsEnabled },
                        set: { on in
                            Task {
                                if on {
                                    let granted = await env.notifications.requestAuthorization()
                                    settings.notificationsEnabled = granted
                                    if granted { await env.repository.rescheduleAllReminders() }
                                } else {
                                    settings.notificationsEnabled = false
                                    await env.notifications.cancelAll()
                                }
                            }
                        }))
                    Toggle("Require \(env.biometrics.biometryName)", isOn: Binding(
                        get: { settings.requireBiometrics },
                        set: { on in
                            Task {
                                if on {
                                    guard env.biometrics.isAvailable else { biometricError = "\(env.biometrics.biometryName) isn't set up on this device."; return }
                                    let ok = await env.biometrics.authenticate(reason: "Confirm to lock LEVER")
                                    settings.requireBiometrics = ok
                                    if !ok { biometricError = "Couldn't verify." }
                                } else {
                                    settings.requireBiometrics = false
                                }
                            }
                        }))
                    .accessibilityIdentifier("requireBiometricsToggle")
                    if let biometricError { Text(biometricError).font(LeverFont.caption).foregroundStyle(LeverColor.urgent) }
                }

                Section("Sources") {
                    NavigationLink("How LEVER knows what you spend") { SourcesView() }
                        .accessibilityIdentifier("sourcesLink")
                }

                Section("Privacy") {
                    NavigationLink("Privacy Center") { PrivacyCenterView() }
                        .accessibilityIdentifier("privacyCenterLink")
                }

                Section("Preferences") {
                    Picker("Currency", selection: Binding(get: { env.repository.profile().currencyCode }, set: { env.repository.profile().currencyCode = $0; try? env.container.mainContext.save(); env.repository.publishSnapshot() })) {
                        ForEach(["INR", "USD", "EUR", "GBP", "AED", "SGD", "AUD", "CAD"], id: \.self) { Text("\($0) \(Money.symbol(for: $0))").tag($0) }
                    }
                    Text("Used for new captures when the document doesn't state a currency.").font(.caption2).foregroundStyle(LeverColor.inkTertiary)
                }

                Section("About") {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                    LabeledContent("Intelligence", value: env.intelligence.processesOnDevice ? "On-device" : env.intelligence.name)
                    Text("LEVER helps you identify opportunities to save or recover money. It isn't a financial or legal adviser; verify policies with the merchant and check your local rules.")
                        .font(.caption2).foregroundStyle(LeverColor.inkTertiary)
                }

                #if DEBUG
                Section("Debug") {
                    Button("Load sample data") { SampleDataSeeder.seedIfNeeded(env.repository, force: true) }
                    Toggle("Simulate Pro", isOn: Binding(get: { env.store.debugOverridePro ?? false }, set: { env.store.debugOverridePro = $0 ? true : nil }))
                    Button("Reset onboarding") { settings.hasCompletedOnboarding = false; dismiss() }
                }
                #endif
            }
            .scrollContentBackground(.hidden)
            .leverScreenBackground()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}
