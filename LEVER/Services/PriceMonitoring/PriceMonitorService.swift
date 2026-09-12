import Foundation

/// MVP price monitoring: the user records prices they see; automated, permitted sources plug in behind this protocol.
struct ManualPriceMonitor: PriceMonitoring {
    func supportsAutomaticTracking(for url: URL) -> Bool { false }

    func fetchCurrentPrice(for url: URL) async throws -> Decimal? {
        // TODO: implementation required — integrate approved price APIs. No scraping, no bypassing protections.
        nil
    }
}
