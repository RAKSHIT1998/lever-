import Foundation

/// Curated knowledge about merchants: category, aliases and *typical* return windows with a stated source.
/// Windows are marked medium confidence and always labelled "verify" — policies change and vary by category.
struct MerchantDirectory: ReturnPolicyProviding {
    struct Entry: Sendable {
        let name: String
        let aliases: [String]
        let category: MerchantCategory
        let domain: String?
        let typicalReturnDays: Int?
        let policyNote: String?
    }

    static let entries: [Entry] = [
        Entry(name: "Amazon", aliases: ["amazon.in", "amazon.com", "amzn"], category: .retail, domain: "amazon.in", typicalReturnDays: 10, policyNote: "Amazon.in lists 7–10 day return/replacement windows for most categories; some items are non-returnable."),
        Entry(name: "Flipkart", aliases: ["flipkart.com"], category: .retail, domain: "flipkart.com", typicalReturnDays: 7, policyNote: "Flipkart's typical window is 7 days for most categories; varies by product."),
        Entry(name: "Apple", aliases: ["apple store", "apple.com", "apple inc", "apple india"], category: .electronics, domain: "apple.com", typicalReturnDays: 14, policyNote: "Apple's standard return policy is 14 calendar days from receipt in most regions."),
        Entry(name: "Croma", aliases: ["croma.com", "infiniti retail"], category: .electronics, domain: "croma.com", typicalReturnDays: 7, policyNote: "Croma lists a 7-day return window for many categories."),
        Entry(name: "Reliance Digital", aliases: ["reliancedigital"], category: .electronics, domain: "reliancedigital.in", typicalReturnDays: 7, policyNote: "Typical 7-day window; verify for your category."),
        Entry(name: "Myntra", aliases: ["myntra.com"], category: .fashion, domain: "myntra.com", typicalReturnDays: 14, policyNote: "Myntra commonly lists 7–14 day returns depending on product."),
        Entry(name: "Ajio", aliases: ["ajio.com"], category: .fashion, domain: "ajio.com", typicalReturnDays: 15, policyNote: nil),
        Entry(name: "Nykaa", aliases: ["nykaa.com"], category: .health, domain: "nykaa.com", typicalReturnDays: nil, policyNote: nil),
        Entry(name: "Best Buy", aliases: ["bestbuy.com", "bestbuy"], category: .electronics, domain: "bestbuy.com", typicalReturnDays: 15, policyNote: "Best Buy's standard return window is 15 days for most customers."),
        Entry(name: "Walmart", aliases: ["walmart.com"], category: .retail, domain: "walmart.com", typicalReturnDays: 90, policyNote: "Walmart lists 90 days for most items; electronics are often 30 days."),
        Entry(name: "Target", aliases: ["target.com"], category: .retail, domain: "target.com", typicalReturnDays: 90, policyNote: nil),
        Entry(name: "Costco", aliases: ["costco.com"], category: .retail, domain: "costco.com", typicalReturnDays: 90, policyNote: "Electronics are typically 90 days at Costco."),
        Entry(name: "IKEA", aliases: ["ikea.com", "ikea.in"], category: .home, domain: "ikea.com", typicalReturnDays: 365, policyNote: "IKEA lists 365 days for unused items in many markets."),
        Entry(name: "Decathlon", aliases: ["decathlon.in"], category: .retail, domain: "decathlon.in", typicalReturnDays: 90, policyNote: nil),
        Entry(name: "Samsung", aliases: ["samsung.com", "samsung india"], category: .electronics, domain: "samsung.com", typicalReturnDays: nil, policyNote: nil),
        Entry(name: "Dell", aliases: ["dell.com"], category: .electronics, domain: "dell.com", typicalReturnDays: nil, policyNote: nil),
        Entry(name: "OnePlus", aliases: ["oneplus.in"], category: .electronics, domain: "oneplus.in", typicalReturnDays: nil, policyNote: nil),
        Entry(name: "Netflix", aliases: ["netflix.com"], category: .streaming, domain: "netflix.com", typicalReturnDays: nil, policyNote: nil),
        Entry(name: "Spotify", aliases: ["spotify.com"], category: .streaming, domain: "spotify.com", typicalReturnDays: nil, policyNote: nil),
        Entry(name: "Prime Video", aliases: ["primevideo", "amazon prime"], category: .streaming, domain: "primevideo.com", typicalReturnDays: nil, policyNote: nil),
        Entry(name: "JioHotstar", aliases: ["hotstar", "disney+ hotstar", "jiocinema"], category: .streaming, domain: "hotstar.com", typicalReturnDays: nil, policyNote: nil),
        Entry(name: "YouTube Premium", aliases: ["youtube premium", "youtube music"], category: .streaming, domain: "youtube.com", typicalReturnDays: nil, policyNote: nil),
        Entry(name: "Apple One", aliases: ["icloud+", "icloud storage", "apple music", "apple tv+", "apple arcade"], category: .software, domain: "apple.com", typicalReturnDays: nil, policyNote: nil),
        Entry(name: "Adobe", aliases: ["adobe.com", "creative cloud"], category: .software, domain: "adobe.com", typicalReturnDays: nil, policyNote: nil),
        Entry(name: "Microsoft", aliases: ["microsoft 365", "office 365", "microsoft.com", "xbox"], category: .software, domain: "microsoft.com", typicalReturnDays: nil, policyNote: nil),
        Entry(name: "Google", aliases: ["google one", "google workspace", "google.com", "google play"], category: .software, domain: "google.com", typicalReturnDays: nil, policyNote: nil),
        Entry(name: "OpenAI", aliases: ["chatgpt", "openai.com"], category: .software, domain: "openai.com", typicalReturnDays: nil, policyNote: nil),
        Entry(name: "Notion", aliases: ["notion.so"], category: .software, domain: "notion.so", typicalReturnDays: nil, policyNote: nil),
        Entry(name: "Dropbox", aliases: ["dropbox.com"], category: .software, domain: "dropbox.com", typicalReturnDays: nil, policyNote: nil),
        Entry(name: "Canva", aliases: ["canva.com"], category: .software, domain: "canva.com", typicalReturnDays: nil, policyNote: nil),
        Entry(name: "Airtel", aliases: ["bharti airtel", "airtel.in", "airtel xstream"], category: .telecom, domain: "airtel.in", typicalReturnDays: nil, policyNote: nil),
        Entry(name: "Jio", aliases: ["reliance jio", "jiofiber", "jio.com"], category: .telecom, domain: "jio.com", typicalReturnDays: nil, policyNote: nil),
        Entry(name: "Vi", aliases: ["vodafone idea", "vodafone", "myvi.in"], category: .telecom, domain: "myvi.in", typicalReturnDays: nil, policyNote: nil),
        Entry(name: "ACT Fibernet", aliases: ["actcorp", "act fibernet"], category: .telecom, domain: "actcorp.in", typicalReturnDays: nil, policyNote: nil),
        Entry(name: "Tata Play", aliases: ["tata sky", "tataplay"], category: .telecom, domain: "tataplay.com", typicalReturnDays: nil, policyNote: nil),
        Entry(name: "BSES", aliases: ["bses rajdhani", "bses yamuna"], category: .utilities, domain: nil, typicalReturnDays: nil, policyNote: nil),
        Entry(name: "Tata Power", aliases: ["tatapower"], category: .utilities, domain: nil, typicalReturnDays: nil, policyNote: nil),
        Entry(name: "MakeMyTrip", aliases: ["makemytrip.com", "mmt"], category: .travel, domain: "makemytrip.com", typicalReturnDays: nil, policyNote: nil),
        Entry(name: "Booking.com", aliases: ["booking.com"], category: .travel, domain: "booking.com", typicalReturnDays: nil, policyNote: nil),
        Entry(name: "Airbnb", aliases: ["airbnb.com", "airbnb.co.in"], category: .travel, domain: "airbnb.com", typicalReturnDays: nil, policyNote: nil),
        Entry(name: "Agoda", aliases: ["agoda.com"], category: .travel, domain: "agoda.com", typicalReturnDays: nil, policyNote: nil),
        Entry(name: "Expedia", aliases: ["expedia.com"], category: .travel, domain: "expedia.com", typicalReturnDays: nil, policyNote: nil),
        Entry(name: "Goibibo", aliases: ["goibibo.com"], category: .travel, domain: "goibibo.com", typicalReturnDays: nil, policyNote: nil),
        Entry(name: "Cleartrip", aliases: ["cleartrip.com"], category: .travel, domain: "cleartrip.com", typicalReturnDays: nil, policyNote: nil),
        Entry(name: "IndiGo", aliases: ["goindigo", "indigo airlines"], category: .travel, domain: "goindigo.in", typicalReturnDays: nil, policyNote: nil),
        Entry(name: "Air India", aliases: ["airindia.com"], category: .travel, domain: "airindia.com", typicalReturnDays: nil, policyNote: nil),
        Entry(name: "IRCTC", aliases: ["irctc.co.in"], category: .travel, domain: "irctc.co.in", typicalReturnDays: nil, policyNote: nil),
        Entry(name: "Uber", aliases: ["uber.com"], category: .travel, domain: "uber.com", typicalReturnDays: nil, policyNote: nil),
        Entry(name: "Ola", aliases: ["olacabs"], category: .travel, domain: "olacabs.com", typicalReturnDays: nil, policyNote: nil),
        Entry(name: "Swiggy", aliases: ["swiggy.com", "instamart"], category: .groceries, domain: "swiggy.com", typicalReturnDays: nil, policyNote: nil),
        Entry(name: "Zomato", aliases: ["zomato.com"], category: .groceries, domain: "zomato.com", typicalReturnDays: nil, policyNote: nil),
        Entry(name: "Blinkit", aliases: ["blinkit.com", "grofers"], category: .groceries, domain: "blinkit.com", typicalReturnDays: nil, policyNote: nil),
        Entry(name: "Zepto", aliases: ["zeptonow"], category: .groceries, domain: "zeptonow.com", typicalReturnDays: nil, policyNote: nil),
        Entry(name: "BigBasket", aliases: ["bigbasket.com"], category: .groceries, domain: "bigbasket.com", typicalReturnDays: nil, policyNote: nil),
        Entry(name: "HDFC ERGO", aliases: ["hdfcergo"], category: .insurance, domain: "hdfcergo.com", typicalReturnDays: nil, policyNote: nil),
        Entry(name: "ICICI Lombard", aliases: ["icicilombard"], category: .insurance, domain: "icicilombard.com", typicalReturnDays: nil, policyNote: nil),
        Entry(name: "LIC", aliases: ["life insurance corporation", "licindia"], category: .insurance, domain: "licindia.in", typicalReturnDays: nil, policyNote: nil),
        Entry(name: "Bajaj Allianz", aliases: ["bajajallianz"], category: .insurance, domain: "bajajallianz.com", typicalReturnDays: nil, policyNote: nil),
        Entry(name: "Star Health", aliases: ["starhealth"], category: .insurance, domain: "starhealth.in", typicalReturnDays: nil, policyNote: nil),
        Entry(name: "Nike", aliases: ["nike.com"], category: .fashion, domain: "nike.com", typicalReturnDays: 30, policyNote: "Nike lists a 30-day return window in many regions."),
        Entry(name: "Zara", aliases: ["zara.com"], category: .fashion, domain: "zara.com", typicalReturnDays: 30, policyNote: nil),
        Entry(name: "H&M", aliases: ["hm.com", "h & m"], category: .fashion, domain: "hm.com", typicalReturnDays: 30, policyNote: nil),
        Entry(name: "Uniqlo", aliases: ["uniqlo.com"], category: .fashion, domain: "uniqlo.com", typicalReturnDays: 30, policyNote: nil),
        Entry(name: "Lenskart", aliases: ["lenskart.com"], category: .health, domain: "lenskart.com", typicalReturnDays: 14, policyNote: nil),
        Entry(name: "Urban Company", aliases: ["urbanclap"], category: .home, domain: "urbancompany.com", typicalReturnDays: nil, policyNote: nil),
    ]

    /// Finds the best-matching merchant in text. Earliest match position wins ties.
    func match(in text: String) -> Entry? {
        let lower = text.lowercased()
        var best: (Entry, Int)?
        for entry in Self.entries {
            let candidates = [entry.name.lowercased()] + entry.aliases.map { $0.lowercased() }
            for candidate in candidates {
                guard let range = lower.range(of: candidate) else { continue }
                // Avoid matching short names inside other words ("Vi" in "Visa").
                if candidate.count <= 3 {
                    let before = range.lowerBound == lower.startIndex ? " " : lower[lower.index(before: range.lowerBound)]
                    let after = range.upperBound == lower.endIndex ? " " : lower[range.upperBound]
                    if before.isLetter || after.isLetter { continue }
                }
                let position = lower.distance(from: lower.startIndex, to: range.lowerBound)
                if let current = best, position >= current.1 { continue }
                best = (entry, position)
            }
        }
        return best?.0
    }

    func entry(named name: String) -> Entry? {
        let lower = name.lowercased()
        return Self.entries.first { $0.name.lowercased() == lower || $0.aliases.contains(lower) }
    }

    // MARK: ReturnPolicyProviding

    func policy(forMerchant merchant: String, category: MerchantCategory) -> ReturnPolicy? {
        guard let entry = entry(named: merchant) ?? match(in: merchant), let days = entry.typicalReturnDays else { return nil }
        return ReturnPolicy(
            merchant: entry.name,
            days: days,
            source: "Typical \(entry.name) policy — verify",
            confidence: .medium,
            note: entry.policyNote
        )
    }
}
