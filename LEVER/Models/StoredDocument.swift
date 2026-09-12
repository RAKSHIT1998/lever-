import Foundation
import SwiftData

/// A captured artefact (image, PDF or pasted text). Binary payloads live on disk under Data Protection;
/// the model only stores the relative path plus extracted text.
@Model
final class StoredDocument {
    @Attribute(.unique) var id: UUID
    var kindRaw: String
    var fileName: String?
    var rawText: String?
    var pageCount: Int
    var createdAt: Date
    var purchase: Purchase?
    var warranty: Warranty?

    enum Kind: String, Codable {
        case image, pdf, text
    }

    init(id: UUID = UUID(), kind: Kind, fileName: String? = nil, rawText: String? = nil, pageCount: Int = 1) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.fileName = fileName
        self.rawText = rawText
        self.pageCount = pageCount
        self.createdAt = .now
    }

    var kind: Kind { Kind(rawValue: kindRaw) ?? .text }
}

@Model
final class AIAnalysis {
    var providerName: String
    var documentTypeRaw: String
    var confidenceRaw: String
    var fieldConfidences: [String: Double]
    var processedOnDevice: Bool
    var createdAt: Date
    var purchase: Purchase?

    init(providerName: String, documentType: DocumentType, confidence: Confidence, fieldConfidences: [String: Double], processedOnDevice: Bool) {
        self.providerName = providerName
        self.documentTypeRaw = documentType.rawValue
        self.confidenceRaw = confidence.rawValue
        self.fieldConfidences = fieldConfidences
        self.processedOnDevice = processedOnDevice
        self.createdAt = .now
    }

    var confidence: Confidence { Confidence(rawValue: confidenceRaw) ?? .low }
}
