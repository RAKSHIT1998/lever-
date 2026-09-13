import Foundation
import CoreSpotlight
import UniformTypeIdentifiers

/// Makes purchases findable from iOS Search ("MacBook", "Amazon", "warranty") with a deep link into LEVER.
/// Only titles, merchants, amounts and dates are indexed — never document text or images.
struct SpotlightIndexer: Sendable {
    static let domain = "com.rakshit1998.lever.purchases"

    static func identifier(for purchaseID: UUID) -> String { "purchase:\(purchaseID.uuidString)" }

    static func purchaseID(from identifier: String) -> UUID? {
        guard identifier.hasPrefix("purchase:") else { return nil }
        return UUID(uuidString: String(identifier.dropFirst("purchase:".count)))
    }

    @MainActor
    func index(_ purchases: [Purchase]) {
        guard CSSearchableIndex.isIndexingAvailable() else { return }
        let items = purchases.map { p -> CSSearchableItem in
            let attributes = CSSearchableItemAttributeSet(contentType: .content)
            attributes.title = p.title
            attributes.contentDescription = [p.merchantName, Money.format(p.amount, code: p.currencyCode), p.purchaseDate?.leverShort].compactMap { $0 }.joined(separator: " · ")
            var keywords = [p.merchantName, p.documentType.displayName, p.merchantCategory.displayName] + p.tags
            if !p.warranties.isEmpty { keywords.append("warranty") }
            if p.subscription != nil { keywords.append("subscription") }
            attributes.keywords = keywords
            attributes.contentCreationDate = p.purchaseDate
            let item = CSSearchableItem(uniqueIdentifier: Self.identifier(for: p.id), domainIdentifier: Self.domain, attributeSet: attributes)
            return item
        }
        CSSearchableIndex.default().indexSearchableItems(items) { _ in }
    }

    func remove(_ purchaseID: UUID) {
        CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: [Self.identifier(for: purchaseID)]) { _ in }
    }

    func removeAll() {
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [Self.domain]) { _ in }
    }
}
