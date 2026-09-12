import SwiftUI
import SwiftData

@main
struct LEVERApp: App {
    @State private var environment = AppEnvironment.live()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment)
                .modelContainer(environment.container)
                .tint(LeverColor.ink)
                .onOpenURL { url in
                    environment.handle(url: url)
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        if let url = IntentRouter.pendingURL {
                            IntentRouter.pendingURL = nil
                            environment.handle(url: url)
                        }
                        environment.refreshInboxCount()
                        if environment.settings.requireBiometrics && !environment.launchedForUITests { environment.isUnlocked = false }
                        Task { await environment.repository.refreshAllOpportunities() }
                    }
                }
                .task {
                    environment.analytics.track(.appOpen)
                    #if DEBUG
                    if !environment.launchedForUITests {
                        SampleDataSeeder.seedIfNeeded(environment.repository)
                    }
                    #endif
                    environment.refreshInboxCount()
                    if environment.settings.requireBiometrics && !environment.launchedForUITests { environment.isUnlocked = false }
                    await environment.store.load()
                    await environment.repository.refreshAllOpportunities()
                }
        }
    }
}

extension AppEnvironment {
    /// Deep links: lever://capture, lever://inbox, lever://savings, lever://opportunity/<uuid>, lever://purchase/<uuid>
    func handle(url: URL) {
        guard url.scheme == AppGroup.urlScheme else { return }
        let host = url.host ?? ""
        let id = url.pathComponents.dropFirst().first.flatMap(UUID.init)
        switch host {
        case "capture", "inbox": router.selectedTab = .capture
        case "savings": router.selectedTab = .savings
        case "vault": router.selectedTab = .vault
        case "opportunity":
            router.selectedTab = .home
            if let id { router.pendingOpportunityID = id }
        case "purchase":
            router.selectedTab = .vault
            if let id { router.pendingPurchaseID = id }
        default: router.selectedTab = .home
        }
    }
}
