import Foundation
import os

/// Local-only analytics. Logs event names to the unified log; never document content.
/// Swap in a network implementation behind the same protocol when needed.
final class LocalAnalyticsService: AnalyticsTracking, @unchecked Sendable {
    private let logger = Logger(subsystem: "com.rakshit1998.lever", category: "analytics")
    private let lock = NSLock()
    private var _enabled = true
    private var _recent: [(AnalyticsEvent, Date)] = []

    var isEnabled: Bool {
        get { lock.withLock { _enabled } }
        set { lock.withLock { _enabled = newValue } }
    }

    var recent: [(AnalyticsEvent, Date)] { lock.withLock { _recent } }

    static let forbiddenKeys: Set<String> = ["rawText", "merchant", "amount", "orderNumber", "serial", "email", "name", "text"]

    func track(_ event: AnalyticsEvent, properties: [String: String]) {
        guard isEnabled else { return }
        let safe = properties.filter { !Self.forbiddenKeys.contains($0.key) }
        lock.withLock {
            _recent.append((event, .now))
            if _recent.count > 200 { _recent.removeFirst(_recent.count - 200) }
        }
        logger.info("\(event.rawValue, privacy: .public) \(safe.description, privacy: .public)")
    }
}
