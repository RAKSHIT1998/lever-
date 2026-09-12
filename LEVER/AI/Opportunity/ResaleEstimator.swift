import Foundation

/// A depreciation-curve estimate of what a device is worth on the second-hand market — clearly labelled as a
/// model, never a quote. Curves are conservative industry rules of thumb; a marketplace API can replace them later.
struct ResaleEstimate: Equatable, Sendable {
    var valueNow: Decimal
    var valueInSixMonths: Decimal
    var deviceClass: ResaleEstimator.DeviceClass
    var ageMonths: Int
    var confidence: Confidence
    var method: String

    var projectedSixMonthLoss: Decimal { max(0, valueNow - valueInSixMonths) }
    var retainedFraction: Decimal { valueNow }
}

enum ResaleEstimator {
    enum DeviceClass: String, CaseIterable, Sendable {
        case phone, laptop, tablet, wearable, camera, console, audio, television, appliance, other

        /// Fraction of value retained after year 1, then the yearly multiplier thereafter.
        var curve: (firstYear: Double, thereafter: Double) {
            switch self {
            case .phone: (0.62, 0.78)
            case .laptop: (0.68, 0.80)
            case .tablet: (0.65, 0.80)
            case .wearable: (0.55, 0.72)
            case .camera: (0.78, 0.86)
            case .console: (0.72, 0.85)
            case .audio: (0.60, 0.78)
            case .television: (0.55, 0.75)
            case .appliance: (0.65, 0.82)
            case .other: (0.60, 0.75)
            }
        }

        var displayName: String {
            switch self {
            case .phone: "Phone"
            case .laptop: "Laptop"
            case .tablet: "Tablet"
            case .wearable: "Wearable"
            case .camera: "Camera"
            case .console: "Games console"
            case .audio: "Audio"
            case .television: "TV"
            case .appliance: "Appliance"
            case .other: "Electronics"
            }
        }
    }

    static let keywords: [(DeviceClass, [String])] = [
        (.phone, ["iphone", "galaxy s", "galaxy z", "pixel", "oneplus", "smartphone", "phone", "redmi", "realme", "vivo", "oppo", "nothing phone"]),
        (.laptop, ["macbook", "laptop", "thinkpad", "xps", "surface laptop", "chromebook", "zenbook", "vivobook", "ideapad", "notebook"]),
        (.tablet, ["ipad", "tablet", "galaxy tab", "surface pro", "kindle"]),
        (.wearable, ["apple watch", "watch series", "galaxy watch", "fitbit", "garmin", "smartwatch", "airpods", "buds", "band"]),
        (.camera, ["camera", "eos", "alpha a7", "lumix", "gopro", "dslr", "mirrorless", "lens"]),
        (.console, ["playstation", "ps5", "xbox", "nintendo", "switch", "steam deck"]),
        (.audio, ["headphones", "speaker", "soundbar", "earbuds", "wh-1000", "bose", "sonos", "jbl", "marshall"]),
        (.television, ["tv", "television", "oled", "qled", "bravia"]),
        (.appliance, ["refrigerator", "fridge", "washing machine", "dishwasher", "microwave", "air conditioner", "ac ", "purifier", "vacuum", "dyson", "oven"]),
    ]

    static func deviceClass(for title: String, category: MerchantCategory) -> DeviceClass? {
        let lower = " " + title.lowercased() + " "
        for (klass, words) in keywords where words.contains(where: { lower.contains($0) }) { return klass }
        return category == .electronics ? .other : nil
    }

    static func estimate(price: Decimal, purchaseDate: Date, title: String, category: MerchantCategory, now: Date = .now) -> ResaleEstimate? {
        guard price > 0, let klass = deviceClass(for: title, category: category) else { return nil }
        let months = max(0, Calendar.current.dateComponents([.month], from: purchaseDate, to: now).month ?? 0)
        let now = retained(months: months, curve: klass.curve)
        let later = retained(months: months + 6, curve: klass.curve)
        let base = NSDecimalNumber(decimal: price).doubleValue
        let confidence: Confidence = klass == .other ? .low : (months <= 36 ? .medium : .low)
        return ResaleEstimate(
            valueNow: Decimal(Int((base * now / 100).rounded()) * 100),
            valueInSixMonths: Decimal(Int((base * later / 100).rounded()) * 100),
            deviceClass: klass,
            ageMonths: months,
            confidence: confidence,
            method: "Depreciation model for \(klass.displayName.lowercased())s — an estimate, not a marketplace quote"
        )
    }

    /// Smooth exponential decay: first-year retention, then a yearly multiplier, interpolated by month.
    static func retained(months: Int, curve: (firstYear: Double, thereafter: Double)) -> Double {
        let m = Double(months)
        if m <= 12 { return pow(curve.firstYear, m / 12) }
        return curve.firstYear * pow(curve.thereafter, (m - 12) / 12)
    }
}

/// Surfaces resale value when a device is past its return window and about to shed meaningful value.
struct ResaleValueRule: OpportunityRule {
    let name = "Resale value"
    let minimumPrice: Decimal = 15_000
    let minimumAgeMonths = 10

    func evaluate(_ context: OpportunityContext) -> [OpportunityDraft] {
        let p = context.purchase
        guard p.subscription == nil, p.documentType != .booking, p.documentType != .insurance, p.documentType != .bill, p.amount >= minimumPrice, let date = p.purchaseDate else { return [] }
        guard let estimate = ResaleEstimator.estimate(price: p.amount, purchaseDate: date, title: p.title, category: p.category, now: context.now), estimate.ageMonths >= minimumAgeMonths else { return [] }
        let loss = estimate.projectedSixMonthLoss
        guard loss >= 2_000, estimate.valueNow > 0, loss / estimate.valueNow >= Decimal(sign: .plus, exponent: -2, significand: 8) else { return [] }
        let hasCoverage = p.warranties.contains { ($0.endDate ?? .distantPast) > context.now }
        return [OpportunityDraft(
            type: .resale,
            title: "Your \(p.title) is worth about \(Money.format(estimate.valueNow, code: p.currencyCode, compact: true)) today",
            detail: "Bought for \(Money.format(p.amount, code: p.currencyCode)) \(estimate.ageMonths) months ago. If you're planning to upgrade, the model suggests it loses about \(Money.format(loss, code: p.currencyCode)) more over the next six months\(hasCoverage ? " — and selling while coverage is still active gets a better price" : "").",
            estimatedSavings: loss,
            currencyCode: p.currencyCode,
            confidence: .low,
            urgency: .low,
            deadline: p.warranties.compactMap(\.endDate).filter { $0 > context.now }.min(),
            merchantName: p.merchantName,
            recommendedAction: "Only if you intend to replace it: check two marketplace listings for your exact model and condition, then decide whether to sell before the next drop.",
            evidence: [
                .init(kind: .fact, statement: "Paid \(Money.format(p.amount, code: p.currencyCode)) on \(date.leverShort).", source: "Your document"),
                .init(kind: .inference, statement: "Estimated value now \(Money.format(estimate.valueNow, code: p.currencyCode)), in 6 months \(Money.format(estimate.valueInSixMonths, code: p.currencyCode)).", source: estimate.method),
                .init(kind: .possibility, statement: "Real offers depend on condition, storage and demand. Nothing here is a quote.", source: "LEVER"),
            ],
            dedupeKey: "resale:\(p.id.uuidString)"
        )]
    }
}
