import Foundation
import Observation
import UIKit

enum AppTab: String, CaseIterable, Hashable {
    case home, capture, vault, savings
}

/// Cross-tab navigation intents (deep links, widgets, App Intents).
@MainActor
@Observable
final class AppRouter {
    var selectedTab: AppTab = .home
    var pendingOpportunityID: UUID?
    var pendingPurchaseID: UUID?
    var showPaywall = false
    var showSettings = false
    /// A screenshot chosen from the watcher, waiting for the Capture tab to pick it up.
    var pendingScreenshot: UIImage?
}
