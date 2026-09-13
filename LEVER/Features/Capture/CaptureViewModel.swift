import Foundation
import Observation
import UIKit

/// Drives the capture pipeline: input → OCR → understanding → review → save → opportunities.
@MainActor
@Observable
final class CaptureViewModel {
    enum Phase: Equatable {
        case idle
        case processing(step: Int)
        case review
        case saving
        case result
        case statement([StatementTransaction], String)
        case failed(String)
    }

    static let steps = ["Reading document…", "Understanding purchase…", "Checking deadlines…", "Looking for opportunities…", "Preparing your LEVER…"]

    private let env: AppEnvironment
    var phase: Phase = .idle
    var document: PurchaseDocument?
    var files: [CaptureFile] = []
    var savedPurchase: Purchase?
    var foundOpportunities: [Opportunity] = []
    var rawInputDescription = ""
    var pendingInbox: InboxItem?
    /// What produced the current document — lets the review screen ask the cloud to re-read the same input.
    private(set) var lastInput: CaptureInput?
    /// Screenshots waiting their turn (batch capture).
    var queue: [UIImage] = []

    init(env: AppEnvironment) {
        self.env = env
    }

    var isBusy: Bool {
        if case .processing = phase { return true }
        return phase == .saving
    }

    var canCapture: Bool {
        EntitlementResolver.canCapture(isPro: env.store.isPro, capturesUsed: env.settings.capturesUsed)
    }

    var remainingFree: Int {
        EntitlementResolver.remainingFreeCaptures(capturesUsed: env.settings.capturesUsed)
    }

    // MARK: - Entry points

    /// Batch: process the first now, keep the rest for after the user finishes this one.
    func enqueue(images: [UIImage]) async {
        guard let first = images.first else { return }
        queue = Array(images.dropFirst())
        await process(images: [first])
    }

    /// Pops the next queued screenshot, if any. Returns false when the batch is done.
    @discardableResult
    func processNextInQueue() async -> Bool {
        guard !queue.isEmpty else { return false }
        let next = queue.removeFirst()
        reset(keepQueue: true)
        await process(images: [next])
        return true
    }

    func process(images: [UIImage]) async {
        let datas = images.compactMap { $0.leverNormalisedJPEG() }
        guard !datas.isEmpty else { return fail("Couldn't read that image.") }
        files = datas.map(CaptureFile.image)
        rawInputDescription = datas.count > 1 ? "\(datas.count) pages" : "Photo"
        if datas.count == 1, let data = datas.first {
            // Single photo: the provider handles OCR — and, with cloud on, can read the image itself if OCR fails.
            lastInput = .image(data)
            await run { try await self.env.intelligence.extractDocument(from: .image(data), currencyCode: self.env.currencyCode) }
            return
        }
        // OCR all pages and merge; understanding runs on the merged text.
        await run {
            var merged: [String] = []
            var confidences: [Double] = []
            let ocr = OCRService()
            for data in datas {
                let text = try await ocr.recognizeText(in: data)
                merged.append(contentsOf: text.lines)
                confidences.append(text.averageConfidence)
            }
            guard !merged.isEmpty else { throw IntelligenceError.unreadable }
            let joined = merged.joined(separator: "\n")
            self.lastInput = .text(joined)
            var doc = try await self.env.intelligence.extractDocument(from: .text(joined), currencyCode: self.env.currencyCode)
            // Carry OCR confidence into the document's field confidences.
            let avg = confidences.reduce(0, +) / Double(max(confidences.count, 1))
            if avg < 0.9 {
                doc.fieldConfidences = doc.fieldConfidences.mapValues { $0 * max(0.5, avg) }
                doc.overallConfidence = Confidence(score: NSDecimalNumber(decimal: Decimal(doc.overallConfidence.weight * avg)).doubleValue)
            }
            return doc
        }
    }

    func process(pdf data: Data) async {
        files = [.pdf(data)]
        rawInputDescription = "PDF"
        lastInput = .pdf(data)
        await run { try await self.env.intelligence.extractDocument(from: .pdf(data), currencyCode: self.env.currencyCode) }
    }

    func process(text: String) async {
        files = []
        rawInputDescription = "Text"
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 3 else { return fail("Paste a receipt, email or confirmation text first.") }
        lastInput = .text(trimmed)
        if let url = URL(string: trimmed), let scheme = url.scheme, ["http", "https"].contains(scheme), !trimmed.contains(" ") {
            await run { try await self.env.intelligence.extractDocument(from: .url(url), currencyCode: self.env.currencyCode) }
        } else {
            await run { try await self.env.intelligence.extractDocument(from: .text(trimmed), currencyCode: self.env.currencyCode) }
        }
    }

    func process(fileURL: URL) async {
        let accessed = fileURL.startAccessingSecurityScopedResource()
        defer { if accessed { fileURL.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: fileURL) else { return fail("Couldn't open that file.") }
        switch fileURL.pathExtension.lowercased() {
        case "pdf": await process(pdf: data)
        case "jpg", "jpeg", "png", "heic", "heif", "tiff", "webp":
            guard let image = UIImage(data: data) else { return fail("Couldn't read that image.") }
            await process(images: [image])
        case "txt", "eml", "md", "csv", "tsv":
            await process(text: String(decoding: data, as: UTF8.self))
        default:
            fail("LEVER can't read .\(fileURL.pathExtension) files yet. Try a photo, screenshot, PDF or text.")
        }
    }

    func process(inbox item: InboxItem) async {
        pendingInbox = item
        if item.kind == .transfer {
            guard let url = item.fileURL else { return fail("That shared purchase couldn't be read.") }
            do {
                let purchase = try await env.repository.importTransfer(fileURL: url)
                env.inbox.consume(item)
                pendingInbox = nil
                env.refreshInboxCount()
                savedPurchase = purchase
                foundOpportunities = OpportunityRanker.rank(purchase.openOpportunities) { $0.priorityScore }
                phase = .result
                Haptics.scanSucceeded()
            } catch {
                fail(error.localizedDescription)
            }
            return
        }
        guard let (input, file) = env.inbox.captureInput(for: item) else {
            env.inbox.consume(item)
            env.refreshInboxCount()
            return fail("That shared item couldn't be read.")
        }
        files = file.map { [$0] } ?? []
        rawInputDescription = "Shared \(input.kindDescription)"
        switch input {
        case .image(let data):
            if let image = UIImage(data: data) { await process(images: [image]) } else { fail("Couldn't read that image.") }
        case .pdf(let data): await process(pdf: data)
        case .text(let text): await process(text: text)
        case .url(let url): await process(text: url.absoluteString)
        }
    }

    // MARK: - Pipeline

    private func run(_ extraction: @escaping () async throws -> PurchaseDocument) async {
        env.analytics.track(.captureStarted)
        phase = .processing(step: 0)
        do {
            try await stepDelay()
            phase = .processing(step: 1)
            var doc = try await extraction()
            if doc.rawText.squashedWhitespace.count < 8 { throw IntelligenceError.unreadable }
            // Statements aren't purchases: hand them to the recurring-charge flow instead.
            let importer = StatementImporter()
            if doc.documentType == .financial || importer.looksLikeStatement(doc.rawText) {
                let transactions = importer.parse(doc.rawText, defaultCurrency: self.env.currencyCode)
                if transactions.count >= 3 {
                    phase = .statement(transactions, doc.rawText)
                    Haptics.scanSucceeded()
                    return
                }
            }
            phase = .processing(step: 2)
            try await stepDelay()
            if !doc.hasUsableCore {
                // Nothing recognisable — offer manual entry rather than inventing values.
                doc.overallConfidence = .low
            }
            document = doc
            phase = .review
            Haptics.scanSucceeded()
        } catch {
            fail((error as? IntelligenceError)?.errorDescription ?? IntelligenceError.unreadable.errorDescription ?? "Something went wrong.")
        }
    }

    private func stepDelay() async throws {
        try await Task.sleep(for: .milliseconds(350))
    }

    private func fail(_ message: String) {
        phase = .failed(message)
        Haptics.failed()
    }

    // MARK: - Review & save

    func startManualEntry() {
        var doc = PurchaseDocument(rawText: document?.rawText ?? "", currencyCode: env.currencyCode)
        doc.documentType = .receipt
        doc.providerName = "Entered manually"
        document = doc
        phase = .review
    }

    func saveDocumentOnly() async {
        var doc = document ?? PurchaseDocument(rawText: "", currencyCode: env.currencyCode)
        doc.documentType = .unknown
        doc.productTitle = doc.productTitle ?? "Saved document"
        document = doc
        await confirmAndSave()
    }

    func confirmAndSave() async {
        guard let doc = document else { return }
        phase = .saving
        do {
            phase = .processing(step: 3)
            let purchase = try await env.repository.save(document: doc, files: files)
            phase = .processing(step: 4)
            try await stepDelay()
            savedPurchase = purchase
            foundOpportunities = OpportunityRanker.rank(purchase.openOpportunities) { $0.priorityScore }
            env.settings.capturesUsed += 1
            try? env.container.mainContext.save()
            if let pendingInbox {
                env.inbox.consume(pendingInbox)
                self.pendingInbox = nil
                env.refreshInboxCount()
            }
            phase = .result
            if !foundOpportunities.isEmpty { Haptics.importantDeadline() }
        } catch {
            fail("Couldn't save this purchase. \(error.localizedDescription)")
        }
    }

    /// Whether the review screen should offer a cloud re-read.
    var canRereadWithAI: Bool { env.settings.cloudAIEnabled && GeminiIntelligenceProvider.storedKey != nil && document != nil }

    /// Explicit "Re-read with AI": returns how many fields changed.
    func rereadWithAI() async -> Int {
        guard let current = document else { return 0 }
        let improved = await HybridIntelligenceProvider.improve(current, input: lastInput)
        let before = current
        document = improved
        var changed = 0
        if improved.merchant != before.merchant { changed += 1 }
        if improved.amount != before.amount { changed += 1 }
        if improved.purchaseDate != before.purchaseDate { changed += 1 }
        if improved.productTitle != before.productTitle { changed += 1 }
        if improved.renewalDate != before.renewalDate { changed += 1 }
        if improved.returnDeadline != before.returnDeadline { changed += 1 }
        if improved.warranties != before.warranties { changed += 1 }
        if improved.orderNumber != before.orderNumber { changed += 1 }
        return changed
    }

    func reset(keepQueue: Bool = false) {
        phase = .idle
        document = nil
        files = []
        savedPurchase = nil
        foundOpportunities = []
        pendingInbox = nil
        lastInput = nil
        if !keepQueue { queue = [] }
    }
}

extension UIImage {
    /// Downscales very large captures and strips orientation so OCR and storage are predictable.
    func leverNormalisedJPEG(maxDimension: CGFloat = 2400, quality: CGFloat = 0.85) -> Data? {
        let longest = max(size.width, size.height)
        let scale = longest > maxDimension ? maxDimension / longest : 1
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        let normalised = renderer.image { _ in draw(in: CGRect(origin: .zero, size: target)) }
        return normalised.jpegData(compressionQuality: quality)
    }
}
