import Foundation
import SwiftData

enum ModelContainerFactory {
    static let schema = Schema([
        Purchase.self, PurchaseItem.self, Merchant.self, StoredDocument.self, AIAnalysis.self,
        Subscription.self, Warranty.self, ReturnWindow.self, Opportunity.self, Evidence.self,
        ActionPlan.self, Negotiation.self, SavingsEvent.self, PriceObservation.self,
        NotificationRule.self, UserProfile.self, AppSettings.self,
    ])

    static var storeURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("LEVER", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
        return dir.appendingPathComponent("LEVER.store")
    }

    static func make(inMemory: Bool = false) throws -> ModelContainer {
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        } else {
            configuration = ModelConfiguration(schema: schema, url: storeURL)
        }
        let container = try ModelContainer(for: schema, configurations: [configuration])
        if !inMemory {
            applyFileProtection(to: storeURL)
        }
        return container
    }

    /// Belt and braces: ensure the SQLite files are protected even if the directory attribute didn't propagate.
    static func applyFileProtection(to url: URL) {
        let candidates = [url.path, url.path + "-wal", url.path + "-shm"]
        for path in candidates where FileManager.default.fileExists(atPath: path) {
            try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: path)
        }
    }

    /// Removes the on-disk store completely. Used by "Delete everything".
    static func destroyStore() {
        let path = storeURL.path
        for candidate in [path, path + "-wal", path + "-shm"] {
            try? FileManager.default.removeItem(atPath: candidate)
        }
    }
}
