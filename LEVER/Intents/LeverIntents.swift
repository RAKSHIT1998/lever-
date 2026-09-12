import AppIntents
import Foundation

/// App Intents read only the non-sensitive shared snapshot, so they work instantly and without unlocking the vault.

struct ScanWithLeverIntent: AppIntent {
    static let title: LocalizedStringResource = "Scan with LEVER"
    static let description = IntentDescription("Open LEVER ready to scan a receipt, bill or screenshot.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentRouter.pendingURL = URL(string: "lever://capture")
        return .result()
    }
}

struct ShowSavingsIntent: AppIntent {
    static let title: LocalizedStringResource = "Show money I can save"
    static let description = IntentDescription("Tells you how much LEVER thinks you can still save or recover.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let s = WidgetSnapshot.load()
        let amount = s.potentialSavings.currencyString(code: s.currencyCode, fractionDigits: 0)
        let text = s.openOpportunities == 0
            ? "LEVER hasn't found any money leaks right now."
            : "LEVER found \(amount) in potential savings across \(s.openOpportunities) opportunit\(s.openOpportunities == 1 ? "y" : "ies")."
        return .result(dialog: IntentDialog(stringLiteral: text))
    }
}

struct ShowExpiringWarrantiesIntent: AppIntent {
    static let title: LocalizedStringResource = "Show expiring warranties"
    static let description = IntentDescription("Lists warranties ending in the next 60 days.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let s = WidgetSnapshot.load()
        guard !s.expiringWarranties.isEmpty else { return .result(dialog: "No warranties are expiring in the next 60 days.") }
        let lines = s.expiringWarranties.prefix(5).map { "\($0.title) ends \($0.date.formatted(date: .abbreviated, time: .omitted))" }
        return .result(dialog: IntentDialog(stringLiteral: lines.joined(separator: ". ")))
    }
}

struct ShowUpcomingRenewalsIntent: AppIntent {
    static let title: LocalizedStringResource = "Show upcoming renewals"
    static let description = IntentDescription("Lists subscriptions renewing in the next 30 days.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let s = WidgetSnapshot.load()
        guard !s.upcomingRenewals.isEmpty else { return .result(dialog: "No renewals in the next 30 days.") }
        let lines = s.upcomingRenewals.prefix(5).map { "\($0.title) renews \($0.date.formatted(date: .abbreviated, time: .omitted))\($0.amount.map { " at \($0.currencyString(code: s.currencyCode))" } ?? "")" }
        return .result(dialog: IntentDialog(stringLiteral: lines.joined(separator: ". ")))
    }
}

struct ShowMonthSavingsIntent: AppIntent {
    static let title: LocalizedStringResource = "Show money saved this month"
    static let description = IntentDescription("Your confirmed savings this month.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let s = WidgetSnapshot.load()
        return .result(dialog: IntentDialog(stringLiteral: "You've confirmed \(s.savedThisMonth.currencyString(code: s.currencyCode, fractionDigits: 0)) saved with LEVER this month. \(s.lifetimeSaved.currencyString(code: s.currencyCode, fractionDigits: 0)) all time."))
    }
}

struct LeverShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: ScanWithLeverIntent(), phrases: ["Scan with \(.applicationName)", "Scan a receipt in \(.applicationName)"], shortTitle: "Scan", systemImageName: "viewfinder")
        AppShortcut(intent: ShowSavingsIntent(), phrases: ["Show money I can save in \(.applicationName)", "What did \(.applicationName) find"], shortTitle: "Potential savings", systemImageName: "sparkles")
        AppShortcut(intent: ShowExpiringWarrantiesIntent(), phrases: ["Show expiring warranties in \(.applicationName)"], shortTitle: "Warranties", systemImageName: "shield.checkered")
        AppShortcut(intent: ShowUpcomingRenewalsIntent(), phrases: ["Show upcoming renewals in \(.applicationName)"], shortTitle: "Renewals", systemImageName: "arrow.triangle.2.circlepath")
        AppShortcut(intent: ShowMonthSavingsIntent(), phrases: ["Show money saved this month in \(.applicationName)"], shortTitle: "Saved this month", systemImageName: "chart.line.uptrend.xyaxis")
    }
}

/// Lets an intent that opens the app hand off a deep link once the scene is active.
@MainActor
enum IntentRouter {
    static var pendingURL: URL?
}
