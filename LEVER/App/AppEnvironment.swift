import Foundation
import SwiftData
import Observation
import UserNotifications
import UIKit

/// Composition root. Everything the features need is injected from here — no global singletons in feature code.
@MainActor
@Observable
final class AppEnvironment {
    let container: ModelContainer
    let repository: PurchaseRepository
    let intelligence: IntelligenceProvider
    let notifications: NotificationScheduling
    let store: StoreService
    let biometrics: BiometricAuthenticating
    let analytics: LocalAnalyticsService
    let priceMonitor: PriceMonitoring
    let inbox: InboxImporter
    let files: DocumentFileStore
    let router = AppRouter()
    let screenshots = ScreenshotWatcher()
    let wallet = WalletTransactionSource()
    let calendar = CalendarExporter()
    let notificationDelegate = NotificationDelegate()
    let gmail = GmailImportSource()

    /// New screenshots noticed since the last check (only when the watcher is enabled).
    var pendingScreenshotCount = 0
    /// Mirrors `settings.cloudAIEnabled` into the Sendable provider without touching SwiftData off the main actor.
    var cloudFlag: CloudFlag?
    /// A payment the user launched from Scan & Pay, awaiting confirmation on return.
    var pendingPayment: PendingPayment?

    var paymentRegion: PaymentRegion {
        settings.paymentRegionRaw.flatMap(PaymentRegion.init(rawValue:)) ?? PaymentRegion.detect()
    }
    let merchantIdentity = MerchantIdentityService()

    /// Set by the biometric gate; sensitive screens check this.
    var isUnlocked = true
    var pendingInboxCount = 0
    var launchedForUITests = false

    init(container: ModelContainer, intelligence: IntelligenceProvider, notifications: NotificationScheduling, store: StoreService, biometrics: BiometricAuthenticating, priceMonitor: PriceMonitoring, files: DocumentFileStore) {
        self.container = container
        self.intelligence = intelligence
        self.notifications = notifications
        self.store = store
        self.biometrics = biometrics
        self.priceMonitor = priceMonitor
        self.files = files
        self.analytics = LocalAnalyticsService()
        self.inbox = InboxImporter()
        self.repository = PurchaseRepository(
            context: container.mainContext,
            intelligence: intelligence,
            policies: MerchantDirectory(),
            notifications: notifications,
            files: files,
            analytics: analytics
        )
        analytics.isEnabled = repository.settings().analyticsEnabled
        notificationDelegate.onOpenPurchase = { [weak self] id in
            self?.router.selectedTab = .vault
            self?.router.pendingPurchaseID = id
        }
        notificationDelegate.onOpenOpportunity = { [weak self] id in
            self?.router.selectedTab = .home
            self?.router.pendingOpportunityID = id
        }
        UNUserNotificationCenter.current().delegate = notificationDelegate
    }

    /// Production wiring.
    static func live() -> AppEnvironment {
        let arguments = ProcessInfo.processInfo.arguments
        let uiTesting = arguments.contains("-ui-testing")
        let container: ModelContainer
        do {
            container = try ModelContainerFactory.make(inMemory: uiTesting)
        } catch {
            // A corrupt store must never brick the app: fall back to memory and let the user re-import.
            container = (try? ModelContainerFactory.make(inMemory: true)) ?? { fatalError("SwiftData unavailable: \(error)") }()
        }
        let cloudFlag = CloudFlag()
        let env = AppEnvironment(
            container: container,
            intelligence: HybridIntelligenceProvider(isCloudEnabled: { cloudFlag.isEnabled }),
            notifications: NotificationService(),
            store: StoreService(),
            biometrics: uiTesting ? AlwaysAllowBiometrics() : BiometricAuthService(),
            priceMonitor: PublicPagePriceMonitor(),
            files: DocumentFileStore()
        )
        env.launchedForUITests = uiTesting
        if GeminiIntelligenceProvider.buildDefaultKey != nil, env.settings.cloudAIDecisionMade == false {
            // A personal build with a baked-in key: on by default, clearly shown and switchable in Privacy Center.
            env.settings.cloudAIEnabled = true
            env.settings.cloudAIDecisionMade = true
        }
        cloudFlag.isEnabled = env.settings.cloudAIEnabled && !uiTesting
        env.cloudFlag = cloudFlag
        if uiTesting {
            // XCUITest waits for animations to settle before every query; none of ours carry meaning in tests.
            UIView.setAnimationsEnabled(false)
            env.store.debugOverridePro = arguments.contains("-pro") ? true : nil
            let settings = env.repository.settings()
            settings.hasCompletedOnboarding = !arguments.contains("-onboarding")
            if arguments.contains("-sample-data") {
                SampleDataSeeder.seedIfNeeded(env.repository, force: true)
            }
            if let index = arguments.firstIndex(of: "-tab"), index + 1 < arguments.count, let tab = AppTab(rawValue: arguments[index + 1]) {
                env.router.selectedTab = tab
            }
        }
        return env
    }

    /// In-memory environment for previews and tests.
    static func preview(seeded: Bool = true) -> AppEnvironment {
        guard let container = try? ModelContainerFactory.make(inMemory: true) else {
            preconditionFailure("In-memory SwiftData container could not be created for previews/tests.")
        }
        let env = AppEnvironment(
            container: container,
            intelligence: LocalIntelligenceProvider(),
            notifications: NoopNotifications(),
            store: StoreService(),
            biometrics: AlwaysAllowBiometrics(),
            priceMonitor: ManualPriceMonitor(),
            files: DocumentFileStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("LEVERPreview", isDirectory: true))
        )
        env.repository.settings().hasCompletedOnboarding = true
        if seeded { SampleDataSeeder.seedIfNeeded(env.repository, force: true) }
        return env
    }

    var settings: AppSettings { repository.settings() }
    var currencyCode: String { repository.profile().currencyCode }

    func refreshInboxCount() {
        pendingInboxCount = inbox.pending().count
        refreshScreenshotCount()
    }

    func refreshScreenshotCount() {
        guard settings.screenshotWatchEnabled, !launchedForUITests else { pendingScreenshotCount = 0; return }
        pendingScreenshotCount = screenshots.newScreenshots(since: settings.lastScreenshotCheck).count
    }

}

/// Thread-safe on/off switch shared with the intelligence provider.
final class CloudFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isEnabled: Bool {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
}

enum BackgroundRefresh {
    static let taskIdentifier = "com.rakshit1998.lever.refresh"
}

/// Notification scheduler that records instead of scheduling — previews and tests.
final class NoopNotifications: NotificationScheduling, @unchecked Sendable {
    private let lock = NSLock()
    private var scheduled: [String: Date] = [:]
    var granted = true

    func requestAuthorization() async -> Bool { granted }
    func authorizationGranted() async -> Bool { granted }
    func schedule(identifier: String, title: String, body: String, at date: Date, userInfo: [String: String]) async { lock.withLock { scheduled[identifier] = date } }
    func cancel(identifiers: [String]) async { lock.withLock { identifiers.forEach { scheduled.removeValue(forKey: $0) } } }
    func cancelAll() async { lock.withLock { scheduled.removeAll() } }
    func pendingIdentifiers() async -> [String] { lock.withLock { Array(scheduled.keys) } }
    var count: Int { lock.withLock { scheduled.count } }
}
