import Foundation

/// Free, keyless brand lookups: Clearbit Autocomplete resolves a merchant *name* to a domain; the logo is the
/// site's own icon via Google's favicon service (with DuckDuckGo as fallback). Only the merchant name is sent —
/// never amounts or documents. Off switch lives in Privacy Center.
struct MerchantIdentityService: Sendable {
    struct Identity: Codable, Equatable, Sendable {
        var name: String
        var domain: String
        var logoURL: URL? { MerchantIdentityService.logoURL(domain: domain) }
        var websiteURL: URL? { URL(string: "https://\(domain)") }
    }

    private static let cacheKey = "lever.merchantIdentity"

    static func logoURL(domain: String) -> URL? {
        URL(string: "https://t3.gstatic.com/faviconV2?client=SOCIAL&type=FAVICON&fallback_opts=TYPE,SIZE,URL&url=https://\(domain)&size=128")
    }

    static func fallbackLogoURL(domain: String) -> URL? { URL(string: "https://icons.duckduckgo.com/ip3/\(domain).ico") }

    /// Already-resolved identity, no network. Used for support links.
    func cachedIdentity(for merchantName: String) -> Identity? {
        let hit = Self.loadCache()[merchantName.lowercased().trimmingCharacters(in: .whitespaces)]
        return (hit?.domain.isEmpty ?? true) ? nil : hit
    }

    /// Cached lookup. Returns nil for unknown names rather than a wrong brand.
    func identity(for merchantName: String) async -> Identity? {
        let key = merchantName.lowercased().trimmingCharacters(in: .whitespaces)
        guard key.count >= 3 else { return nil }
        var cache = Self.loadCache()
        if let hit = cache[key] { return hit.domain.isEmpty ? nil : hit }
        var components = URLComponents(string: "https://autocomplete.clearbit.com/v1/companies/suggest")!
        components.queryItems = [URLQueryItem(name: "query", value: merchantName)]
        struct Suggestion: Decodable { let name: String; let domain: String }
        guard let url = components.url, let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let suggestions = try? JSONDecoder().decode([Suggestion].self, from: data) else { return nil }
        // Accept only a confident match: the first suggestion whose name shares the merchant's first word.
        let firstWord = key.split(separator: " ").first.map(String.init) ?? key
        let match = suggestions.first { $0.name.lowercased().contains(firstWord) || firstWord.contains($0.name.lowercased()) }
        let identity = match.map { Identity(name: $0.name, domain: $0.domain) } ?? Identity(name: merchantName, domain: "")
        cache[key] = identity
        Self.saveCache(cache)
        return identity.domain.isEmpty ? nil : identity
    }

    private static func loadCache() -> [String: Identity] {
        guard let data = AppGroup.sharedDefaults.data(forKey: cacheKey) else { return [:] }
        return (try? JSONDecoder.lever.decode([String: Identity].self, from: data)) ?? [:]
    }

    private static func saveCache(_ cache: [String: Identity]) {
        if let data = try? JSONEncoder.lever.encode(cache) { AppGroup.sharedDefaults.set(data, forKey: cacheKey) }
    }
}
