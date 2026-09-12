import Foundation

/// Fully on-device: Vision OCR + PDFKit + rule-based understanding. This is the default and always available.
struct LocalIntelligenceProvider: IntelligenceProvider {
    let name = "LEVER on-device"
    let processesOnDevice = true

    private let recognizer: TextRecognizing
    private let parser = DocumentParser()
    private let engine = OpportunityEngine.standard
    private let planner = ActionPlanGenerator()

    init(recognizer: TextRecognizing = OCRService()) {
        self.recognizer = recognizer
    }

    func extractDocument(from input: CaptureInput, currencyCode: String) async throws -> PurchaseDocument {
        let recognized: RecognizedText
        var sourceURL: URL?
        switch input {
        case .image(let data):
            recognized = try await recognizer.recognizeText(in: data)
        case .pdf(let data):
            recognized = try await recognizer.extractText(fromPDF: data)
        case .text(let text):
            recognized = RecognizedText(lines: text.components(separatedBy: .newlines), averageConfidence: 1.0)
        case .url(let url):
            // MVP: we don't fetch pages. The URL is stored for price tracking; the user adds details.
            sourceURL = url
            recognized = RecognizedText(lines: [url.absoluteString], averageConfidence: 1.0)
        }
        guard !recognized.isEmpty else { throw IntelligenceError.unreadable }
        var document = parser.parse(recognized, currencyCode: currencyCode, sourceURL: sourceURL)
        document.providerName = name
        document.processedOnDevice = true
        return document
    }

    func detectOpportunities(in context: OpportunityContext) async throws -> [OpportunityDraft] {
        engine.detect(context)
    }

    func generateActionPlan(for opportunity: OpportunitySnapshot) async throws -> ActionPlanDraft {
        planner.plan(for: opportunity)
    }
}

/// Placeholder for a cloud model. Disabled by default; documents are never uploaded unless the user turns this on
/// in Privacy Center. Falls back to the local provider until an endpoint is configured.
struct RemoteIntelligenceProvider: IntelligenceProvider {
    let name = "LEVER cloud"
    let processesOnDevice = false
    let fallback: LocalIntelligenceProvider
    let endpoint: URL?

    init(fallback: LocalIntelligenceProvider = LocalIntelligenceProvider(), endpoint: URL? = nil) {
        self.fallback = fallback
        self.endpoint = endpoint
    }

    var isConfigured: Bool { endpoint != nil }

    func extractDocument(from input: CaptureInput, currencyCode: String) async throws -> PurchaseDocument {
        // TODO: implementation required — send to configured endpoint with user consent.
        var doc = try await fallback.extractDocument(from: input, currencyCode: currencyCode)
        doc.providerName = fallback.name
        return doc
    }

    func detectOpportunities(in context: OpportunityContext) async throws -> [OpportunityDraft] {
        try await fallback.detectOpportunities(in: context)
    }

    func generateActionPlan(for opportunity: OpportunitySnapshot) async throws -> ActionPlanDraft {
        try await fallback.generateActionPlan(for: opportunity)
    }
}
