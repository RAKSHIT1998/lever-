import Foundation
import SwiftData

/// One coverage on a purchase. A product may carry several (manufacturer + extended + card protection).
@Model
final class Warranty {
    @Attribute(.unique) var id: UUID
    var provider: String
    var typeRaw: String
    var startDate: Date?
    var endDate: Date?
    var coverageSummary: String?
    var policyNumber: String?
    var source: String
    var confidenceRaw: String
    var purchase: Purchase?

    @Relationship(deleteRule: .nullify, inverse: \StoredDocument.warranty)
    var documents: [StoredDocument] = []

    init(
        id: UUID = UUID(),
        provider: String,
        type: WarrantyType,
        startDate: Date?,
        endDate: Date?,
        coverageSummary: String? = nil,
        policyNumber: String? = nil,
        source: String,
        confidence: Confidence
    ) {
        self.id = id
        self.provider = provider
        self.typeRaw = type.rawValue
        self.startDate = startDate
        self.endDate = endDate
        self.coverageSummary = coverageSummary
        self.policyNumber = policyNumber
        self.source = source
        self.confidenceRaw = confidence.rawValue
    }

    var type: WarrantyType { WarrantyType(rawValue: typeRaw) ?? .manufacturer }
    var confidence: Confidence { Confidence(rawValue: confidenceRaw) ?? .low }

    func daysRemaining(from now: Date = .now) -> Int? {
        guard let endDate else { return nil }
        return DateMath.days(from: now, to: endDate)
    }

    var isActive: Bool {
        guard let endDate else { return false }
        return endDate >= .now
    }
}

@Model
final class ReturnWindow {
    var deadline: Date?
    var daysAllowed: Int?
    var policySource: String
    var policyDate: Date?
    var confidenceRaw: String
    var purchase: Purchase?

    init(deadline: Date?, daysAllowed: Int?, policySource: String, policyDate: Date? = nil, confidence: Confidence) {
        self.deadline = deadline
        self.daysAllowed = daysAllowed
        self.policySource = policySource
        self.policyDate = policyDate
        self.confidenceRaw = confidence.rawValue
    }

    var confidence: Confidence { Confidence(rawValue: confidenceRaw) ?? .low }

    func daysRemaining(from now: Date = .now) -> Int? {
        guard let deadline else { return nil }
        return DateMath.days(from: now, to: deadline)
    }

    var isOpen: Bool {
        guard let deadline else { return false }
        return deadline >= Calendar.current.startOfDay(for: .now)
    }
}
