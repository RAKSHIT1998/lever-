import Foundation

/// Cloud extraction with Google's Gemini API (free tier, user's own key). Strictly opt-in: only the recognised
/// *text* is sent — never images or PDFs — and only when the on-device parser is unsure.
struct GeminiIntelligenceProvider: IntelligenceProvider {
    let name = "Gemini"
    let processesOnDevice = false
    let apiKey: String
    let model: String

    static let keychain = KeychainStore(service: "com.rakshit1998.lever.cloud")
    static let defaultModel = "gemini-flash-latest"

    /// Build-time defaults from Config/Secrets.xcconfig (gitignored) — lets a personal build ship with a key baked in.
    static var buildDefaultKey: String? {
        let v = Bundle.main.object(forInfoDictionaryKey: "LEVERGeminiDefaultKey") as? String
        return (v?.isEmpty ?? true) ? nil : v
    }

    static var buildDefaultModel: String? {
        let v = Bundle.main.object(forInfoDictionaryKey: "LEVERGeminiDefaultModel") as? String
        return (v?.isEmpty ?? true) ? nil : v
    }

    static var storedKey: String? {
        get { keychain.get("geminiKey").flatMap { String(data: $0, encoding: .utf8) } ?? buildDefaultKey }
        set { if let newValue, !newValue.isEmpty { keychain.set(Data(newValue.utf8), for: "geminiKey") } else { keychain.remove("geminiKey") } }
    }

    static var storedModel: String {
        get { keychain.get("geminiModel").flatMap { String(data: $0, encoding: .utf8) } ?? buildDefaultModel ?? defaultModel }
        set { keychain.set(Data(newValue.utf8), for: "geminiModel") }
    }

    /// The shape we ask Gemini to fill. Every field optional; the prompt forbids guessing.
    struct Extraction: Decodable {
        struct Item: Decodable { let name: String?; let price: Double? }
        let merchant: String?
        let product_title: String?
        let document_type: String?
        let amount: Double?
        let currency: String?
        let purchase_date: String?
        let renewal_date: String?
        let return_deadline: String?
        let billing_cycle: String?
        let previous_price: Double?
        let warranty_months: Int?
        let order_number: String?
        let serial_number: String?
        let payment_method: String?
        let items: [Item]?
    }

    static let responseSchema: [String: Any] = [
        "type": "OBJECT",
        "properties": [
            "merchant": ["type": "STRING", "nullable": true],
            "product_title": ["type": "STRING", "nullable": true],
            "document_type": ["type": "STRING", "nullable": true, "enum": DocumentType.allCases.map(\.rawValue)],
            "amount": ["type": "NUMBER", "nullable": true],
            "currency": ["type": "STRING", "nullable": true],
            "purchase_date": ["type": "STRING", "nullable": true],
            "renewal_date": ["type": "STRING", "nullable": true],
            "return_deadline": ["type": "STRING", "nullable": true],
            "billing_cycle": ["type": "STRING", "nullable": true, "enum": ["weekly", "monthly", "quarterly", "yearly"]],
            "previous_price": ["type": "NUMBER", "nullable": true],
            "warranty_months": ["type": "INTEGER", "nullable": true],
            "order_number": ["type": "STRING", "nullable": true],
            "serial_number": ["type": "STRING", "nullable": true],
            "payment_method": ["type": "STRING", "nullable": true],
            "items": ["type": "ARRAY", "items": ["type": "OBJECT", "properties": ["name": ["type": "STRING"], "price": ["type": "NUMBER", "nullable": true]]]],
        ],
    ]

    static let prompt = """
    You extract purchase facts from receipts, invoices, order emails, subscription notices, bookings and bills.
    Rules: use ONLY values explicitly present in the text. If something is not stated, return null. Never infer or guess dates, prices or policies. Dates as YYYY-MM-DD. Amount = the final total paid or due. currency = ISO 4217 code. billing_cycle only if the text says the charge repeats. warranty_months only if a warranty duration is stated. Keep product_title short (the main item).
    TEXT:
    """

    func extractDocument(from input: CaptureInput, currencyCode: String) async throws -> PurchaseDocument {
        guard case .text(let text) = input else { throw IntelligenceError.unsupportedInput }
        let extraction = try await extract(text: text)
        var doc = PurchaseDocument(rawText: text, currencyCode: extraction.currency ?? currencyCode)
        Self.apply(extraction, to: &doc, confidence: 0.75)
        doc.providerName = name
        doc.processedOnDevice = false
        return doc
    }

    func detectOpportunities(in context: OpportunityContext) async throws -> [OpportunityDraft] {
        OpportunityEngine.standard.detect(context)   // Rules stay deterministic and local.
    }

    func generateActionPlan(for opportunity: OpportunitySnapshot) async throws -> ActionPlanDraft {
        ActionPlanGenerator(generatedBy: "LEVER on-device").plan(for: opportunity)
    }

    // MARK: - API

    func extract(text: String) async throws -> Extraction {
        guard !apiKey.isEmpty else { throw IntelligenceError.remoteUnavailable }
        var request = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        let body: [String: Any] = [
            "contents": [["parts": [["text": Self.prompt + "\n" + String(text.prefix(12_000))]]]],
            "generationConfig": ["temperature": 0, "response_mime_type": "application/json", "response_schema": Self.responseSchema],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw IntelligenceError.remoteUnavailable }
        guard (200..<300).contains(http.statusCode) else {
            throw GeminiError.http(http.statusCode, Self.errorMessage(from: data))
        }
        struct Envelope: Decodable {
            struct Candidate: Decodable { struct Content: Decodable { struct Part: Decodable { let text: String? }; let parts: [Part]? }; let content: Content? }
            let candidates: [Candidate]?
        }
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        guard let json = envelope.candidates?.first?.content?.parts?.first?.text, let jsonData = json.data(using: .utf8) else {
            throw GeminiError.emptyResponse
        }
        return try JSONDecoder().decode(Extraction.self, from: jsonData)
    }

    enum GeminiError: LocalizedError {
        case http(Int, String?), emptyResponse
        var errorDescription: String? {
            switch self {
            case .http(let code, let message): "Gemini returned \(code)\(message.map { ": \($0)" } ?? "")"
            case .emptyResponse: "Gemini returned no extraction."
            }
        }
    }

    private static func errorMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let error = object["error"] as? [String: Any] else { return nil }
        return error["message"] as? String
    }

    // MARK: - Merge

    /// Writes cloud fields into a document, only where the document has nothing (or low confidence) already.
    static func apply(_ e: Extraction, to doc: inout PurchaseDocument, confidence: Double) {
        func weak(_ field: String) -> Bool { (doc.fieldConfidences[field] ?? 0) < 0.8 }
        func date(_ s: String?) -> Date? {
            guard let s, !s.isEmpty else { return nil }
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = .current
            if let iso = f.date(from: s) { return Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: iso) }
            // Models don't always obey the format instruction ("9 September 2026"); reuse the strict local date parser.
            return DateParser.explicitDates(in: s).first
        }
        if let m = e.merchant, !m.isEmpty, doc.merchant == nil || weak("merchant") {
            doc.merchant = MerchantDirectory().entry(named: m)?.name ?? m
            if let entry = MerchantDirectory().entry(named: m) { doc.merchantCategory = entry.category }
            doc.fieldConfidences["merchant"] = confidence
        }
        if let a = e.amount, a > 0, doc.amount == nil || weak("amount") { doc.amount = Decimal(a); doc.fieldConfidences["amount"] = confidence }
        if let t = e.product_title, !t.isEmpty, doc.productTitle == nil || weak("productTitle") { doc.productTitle = t; doc.fieldConfidences["productTitle"] = confidence }
        if let raw = e.document_type, let type = DocumentType(rawValue: raw), doc.documentType == .unknown || weak("documentType") { doc.documentType = type; doc.fieldConfidences["documentType"] = confidence }
        if let d = date(e.purchase_date), doc.purchaseDate == nil || weak("purchaseDate") { doc.purchaseDate = d; doc.fieldConfidences["purchaseDate"] = confidence }
        if let d = date(e.renewal_date), doc.renewalDate == nil || weak("renewalDate") { doc.renewalDate = d; doc.fieldConfidences["renewalDate"] = confidence }
        if let d = date(e.return_deadline), doc.returnDeadline == nil || weak("returnDeadline") { doc.returnDeadline = d; doc.fieldConfidences["returnDeadline"] = confidence }
        if let cycle = e.billing_cycle.flatMap(BillingCycle.init(rawValue:)), doc.subscription == nil {
            doc.subscription = .init(billingCycle: cycle, nextBillingDate: doc.renewalDate, previousPrice: e.previous_price.map { Decimal($0) })
            doc.fieldConfidences["subscription"] = confidence
        } else if let prev = e.previous_price, var sub = doc.subscription, sub.previousPrice == nil {
            sub.previousPrice = Decimal(prev); doc.subscription = sub
        }
        if let months = e.warranty_months, months > 0, doc.warranties.isEmpty {
            let end = doc.purchaseDate.flatMap { DateMath.adding(months: months, to: $0) }
            doc.warranties = [.init(provider: doc.merchant ?? "Manufacturer", type: .manufacturer, months: months, endDate: end, source: "Stated in document (read by Gemini)", confidence: .medium)]
            doc.fieldConfidences["warranty"] = confidence
        }
        if let v = e.order_number, !v.isEmpty, doc.orderNumber == nil { doc.orderNumber = v; doc.fieldConfidences["orderNumber"] = confidence }
        if let v = e.serial_number, !v.isEmpty, doc.serialNumber == nil { doc.serialNumber = v; doc.fieldConfidences["serialNumber"] = confidence }
        if let v = e.payment_method, !v.isEmpty, doc.paymentMethod == nil { doc.paymentMethod = v; doc.fieldConfidences["paymentMethod"] = confidence }
        if doc.items.isEmpty, let items = e.items {
            doc.items = items.compactMap { item in item.name.map { .init(name: $0, quantity: 1, unitPrice: item.price.map { Decimal($0) }) } }
        }
        let core: [Double] = [doc.fieldConfidences["merchant"] ?? 0, doc.fieldConfidences["amount"] ?? 0, doc.fieldConfidences["purchaseDate"] ?? 0.4]
        doc.overallConfidence = Confidence(score: core.reduce(0, +) / Double(core.count))
    }
}

/// On-device first; Gemini fills the gaps only when enabled, keyed, and the local read is uncertain.
struct HybridIntelligenceProvider: IntelligenceProvider {
    let local = LocalIntelligenceProvider()
    let isCloudEnabled: @Sendable () -> Bool

    var name: String { "LEVER on-device" + (isCloudEnabled() && GeminiIntelligenceProvider.storedKey != nil ? " + Gemini" : "") }
    var processesOnDevice: Bool { !(isCloudEnabled() && GeminiIntelligenceProvider.storedKey != nil) }

    func extractDocument(from input: CaptureInput, currencyCode: String) async throws -> PurchaseDocument {
        var doc = try await local.extractDocument(from: input, currencyCode: currencyCode)
        guard isCloudEnabled(), let key = GeminiIntelligenceProvider.storedKey, Self.needsHelp(doc) else { return doc }
        let cloud = GeminiIntelligenceProvider(apiKey: key, model: GeminiIntelligenceProvider.storedModel)
        if let extraction = try? await cloud.extract(text: doc.rawText) {
            GeminiIntelligenceProvider.apply(extraction, to: &doc, confidence: 0.75)
            doc.providerName = "On-device + Gemini"
            doc.processedOnDevice = false
        }
        return doc
    }

    static func needsHelp(_ doc: PurchaseDocument) -> Bool {
        doc.merchant == nil || doc.amount == nil || doc.purchaseDate == nil || doc.overallConfidence != .high
    }

    func detectOpportunities(in context: OpportunityContext) async throws -> [OpportunityDraft] { try await local.detectOpportunities(in: context) }
    func generateActionPlan(for opportunity: OpportunitySnapshot) async throws -> ActionPlanDraft { try await local.generateActionPlan(for: opportunity) }
}
