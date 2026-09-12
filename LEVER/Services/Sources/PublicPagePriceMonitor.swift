import Foundation

/// Reads the current price from a product page the *user* gave us. One page, one request, standard metadata
/// (Open Graph / schema.org / JSON-LD) — no crawling, no bypassing protections, and an honest User-Agent.
struct PublicPagePriceMonitor: PriceMonitoring {
    private static let patterns: [Pattern] = [
        Pattern(#"property=["']product:price:amount["']\s+content=["']([\d.,]+)["']"#),
        Pattern(#"content=["']([\d.,]+)["']\s+property=["']product:price:amount["']"#),
        Pattern(#"itemprop=["']price["'][^>]*content=["']([\d.,]+)["']"#),
        Pattern(#"["']price["']\s*:\s*["']?([\d]+(?:[.,]\d+)*)["']?"#),
        Pattern(#"["']lowPrice["']\s*:\s*["']?([\d]+(?:[.,]\d+)*)["']?"#),
        Pattern(#"priceAmount["']\s*:\s*["']?([\d]+(?:[.,]\d+)*)"#),
        Pattern(#"class=["'][^"']*a-price-whole[^"']*["'][^>]*>([\d,]+)"#),
    ]

    func supportsAutomaticTracking(for url: URL) -> Bool {
        ["http", "https"].contains(url.scheme?.lowercased() ?? "")
    }

    func fetchCurrentPrice(for url: URL) async throws -> Decimal? {
        guard supportsAutomaticTracking(for: url) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("LEVER/1.0 (iOS; price check requested by the user)", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
        guard let html = String(data: data.prefix(1_500_000), encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return nil }
        return Self.extractPrice(from: html)
    }

    /// Exposed for tests. Returns the most plausible price on the page, or nil — never a guess.
    static func extractPrice(from html: String) -> Decimal? {
        var found: [Decimal] = []
        for pattern in patterns {
            for groups in pattern.allMatches(in: html) {
                guard let raw = groups.count > 1 ? groups[1] : nil else { continue }
                let normalised = raw.filter { $0.isNumber || $0 == "." || $0 == "," }
                // "1.299,00" (EU) vs "1,299.00" — decide by the last separator.
                let value: Decimal?
                if let lastComma = normalised.lastIndex(of: ","), let lastDot = normalised.lastIndex(of: "."), lastComma > lastDot {
                    value = AmountParser.parseDecimal(normalised.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: "."))
                } else {
                    value = AmountParser.parseDecimal(normalised)
                }
                if let value, value > 0, value < 50_000_000 { found.append(value) }
            }
            if !found.isEmpty { break }   // Earlier patterns are more reliable; stop at the first that yields anything.
        }
        guard !found.isEmpty else { return nil }
        // Structured metadata usually repeats the same figure; take the most common value.
        var counts: [Decimal: Int] = [:]
        found.forEach { counts[$0, default: 0] += 1 }
        return counts.max { a, b in a.value < b.value || (a.value == b.value && a.key > b.key) }?.key
    }
}
