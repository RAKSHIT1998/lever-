import Foundation

/// Constants and storage locations shared between the main app, the Share Extension and the widgets.
enum AppGroup {
    static let identifier = "group.com.rakshit1998.lever"
    static let urlScheme = "lever"

    /// The shared container. Falls back to the process's own Application Support directory when the
    /// app group is unavailable (e.g. when running without entitlements), so nothing ever crashes.
    static var containerURL: URL {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) {
            return url
        }
        let fallback = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return fallback.appendingPathComponent("LEVERGroupFallback", isDirectory: true)
    }

    static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }

    /// Directory where the Share Extension drops incoming items for the app to pick up.
    static var inboxURL: URL {
        let url = containerURL.appendingPathComponent("Inbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
