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
            let cleaned = HTMLText.strip(text)
            recognized = RecognizedText(lines: cleaned.components(separatedBy: .newlines), averageConfidence: 1.0)
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


/// Shared emails and web pages often arrive as HTML. Turn them into readable lines without a browser engine.
enum HTMLText {
    static func strip(_ input: String) -> String {
        guard input.contains("<") && (input.range(of: #"<\s*(html|body|div|p|br|table|tr|td|span|a|img|meta|style|script)\b"#, options: [.regularExpression, .caseInsensitive]) != nil) else { return input }
        var text = input
        text = text.replacingOccurrences(of: #"(?is)<(script|style|head)[^>]*>.*?</\1>"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?i)<br\s*/?>|</(p|div|tr|li|h[1-6]|table|section)>"#, with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?i)</t[dh]>"#, with: "  ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        let entities: [String: String] = ["&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&rsquo;": "'", "&ndash;": "–", "&mdash;": "—", "&#8377;": "₹", "&#x20B9;": "₹", "&euro;": "€", "&pound;": "£", "&copy;": "©"]
        for (entity, value) in entities { text = text.replacingOccurrences(of: entity, with: value) }
        text = text.replacingOccurrences(of: #"&#(\d+);"#, with: " ", options: .regularExpression)
        return text
            .components(separatedBy: .newlines)
            .map { $0.squashedWhitespace }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}
