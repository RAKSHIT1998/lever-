import Foundation
import UniformTypeIdentifiers
import CoreTransferable

extension UTType {
    /// One purchase with its documents, warranties and subscription — the unit of family sharing.
    static let leverPurchase = UTType(exportedAs: "com.rakshit1998.lever.purchase", conformingTo: .json)
}

/// Portable, versioned snapshot of a purchase. Sent by AirDrop/Messages/Files; imported into another LEVER.
struct PurchaseTransfer: Codable, Equatable {
    static let currentVersion = 1

    struct Document: Codable, Equatable {
        var kind: String
        var fileName: String?
        var rawText: String?
        /// Base64 of the original image/PDF. Images are downscaled; PDFs capped by `maxDocumentBytes`.
        var payload: Data?
    }
    struct Warranty: Codable, Equatable {
        var provider: String; var type: String; var start: Date?; var end: Date?; var coverage: String?; var source: String; var confidence: String
    }
    struct Subscription: Codable, Equatable {
        var price: Decimal; var currency: String; var cycle: String; var next: Date?; var previous: Decimal?; var status: String; var source: String
    }
    struct ReturnWindow: Codable, Equatable { var deadline: Date?; var days: Int?; var source: String; var confidence: String }

    var version: Int = PurchaseTransfer.currentVersion
    var id: UUID
    var householdID: UUID?
    var sharedBy: String?
    var title: String
    var merchantName: String
    var merchantCategory: String
    var documentType: String
    var amount: Decimal
    var currencyCode: String
    var purchaseDate: Date?
    var serviceDate: Date?
    var orderNumber: String?
    var serialNumber: String?
    var policyNumber: String?
    var paymentMethod: String?
    var productURL: String?
    var notes: String?
    var tags: [String]
    var items: [String]
    var documents: [Document]
    var warranties: [Warranty]
    var subscription: Subscription?
    var returnWindow: ReturnWindow?
    var exportedAt: Date

    static let maxDocumentBytes = 6_000_000
}

enum PurchaseTransferCodec {
    @MainActor
    static func export(_ p: Purchase, sharedBy: String?, householdID: UUID?, files: DocumentFileStore) -> PurchaseTransfer {
        PurchaseTransfer(
            id: p.id, householdID: householdID ?? p.householdID, sharedBy: sharedBy,
            title: p.title, merchantName: p.merchantName, merchantCategory: p.merchantCategoryRaw, documentType: p.documentTypeRaw,
            amount: p.amount, currencyCode: p.currencyCode, purchaseDate: p.purchaseDate, serviceDate: p.serviceDate,
            orderNumber: p.orderNumber, serialNumber: p.serialNumber, policyNumber: p.policyNumber, paymentMethod: p.paymentMethod,
            productURL: p.productURL, notes: p.notes, tags: p.tags, items: p.items.map(\.name),
            documents: p.documents.map { d in
                var payload: Data?
                if let name = d.fileName, let data = files.read(name), data.count <= PurchaseTransfer.maxDocumentBytes { payload = data }
                return .init(kind: d.kindRaw, fileName: d.fileName, rawText: d.rawText, payload: payload)
            },
            warranties: p.warranties.map { .init(provider: $0.provider, type: $0.typeRaw, start: $0.startDate, end: $0.endDate, coverage: $0.coverageSummary, source: $0.source, confidence: $0.confidenceRaw) },
            subscription: p.subscription.map { .init(price: $0.price, currency: $0.currencyCode, cycle: $0.billingCycleRaw, next: $0.nextBillingDate, previous: $0.previousPrice, status: $0.statusRaw, source: $0.source) },
            returnWindow: p.returnWindow.map { .init(deadline: $0.deadline, days: $0.daysAllowed, source: $0.policySource, confidence: $0.confidenceRaw) },
            exportedAt: .now
        )
    }

    static func encode(_ transfer: PurchaseTransfer) throws -> Data { try JSONEncoder.lever.encode(transfer) }

    static func decode(_ data: Data) throws -> PurchaseTransfer {
        let transfer = try JSONDecoder.lever.decode(PurchaseTransfer.self, from: data)
        guard transfer.version <= PurchaseTransfer.currentVersion else { throw TransferError.newerVersion }
        return transfer
    }

    enum TransferError: LocalizedError {
        case newerVersion
        var errorDescription: String? { "This was shared from a newer LEVER. Update the app to import it." }
    }

    static func fileName(for transfer: PurchaseTransfer) -> String {
        let safe = transfer.title.replacingOccurrences(of: #"[^A-Za-z0-9 _-]"#, with: "", options: .regularExpression).prefix(40)
        return "\(safe.isEmpty ? "Purchase" : String(safe)).leverpurchase"
    }
}

/// ShareLink payload: writes the bundle to a temporary file so AirDrop/Messages/Files all accept it.
struct SharedPurchaseFile: Transferable {
    let transfer: PurchaseTransfer

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .leverPurchase) { file in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(PurchaseTransferCodec.fileName(for: file.transfer))
            try PurchaseTransferCodec.encode(file.transfer).write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
        .suggestedFileName { PurchaseTransferCodec.fileName(for: $0.transfer) }
    }
}
