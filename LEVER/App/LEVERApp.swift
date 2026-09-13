import SwiftUI
import SwiftData
import BackgroundTasks
import CoreSpotlight

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
                .onContinueUserActivity(CSSearchableItemActionType) { activity in
                    guard let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
                          let id = SpotlightIndexer.purchaseID(from: identifier) else { return }
                    environment.router.selectedTab = .vault
                    environment.router.pendingPurchaseID = id
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background {
                        LEVERApp.scheduleBackgroundRefresh()
                    }
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
        .backgroundTask(.appRefresh(BackgroundRefresh.taskIdentifier)) {
            await environment.repository.performBackgroundRefresh(priceMonitor: environment.priceMonitor)
            LEVERApp.scheduleBackgroundRefresh()
        }
    }

    /// Asks iOS for a refresh roughly once a day. iOS decides the actual time based on usage.
    nonisolated static func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: BackgroundRefresh.taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 12 * 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}

extension AppEnvironment {
    /// Deep links: lever://capture, lever://inbox, lever://savings, lever://opportunity/<uuid>, lever://purchase/<uuid>
    func handle(url: URL) {
        if url.isFileURL, url.pathExtension.lowercased() == "leverpurchase" {
            Task {
                if let purchase = try? await repository.importTransfer(fileURL: url) {
                    router.selectedTab = .vault
                    router.pendingPurchaseID = purchase.id
                    Haptics.scanSucceeded()
                }
            }
            return
        }
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
