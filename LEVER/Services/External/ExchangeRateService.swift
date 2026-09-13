import Foundation

/// Free, keyless ECB reference rates from frankfurter.dev. Cached for a day in the app group so widgets can use them.
/// Used only to *approximate* other-currency opportunities in your home currency — always shown with "≈".
actor ExchangeRateService {
    static let shared = ExchangeRateService()

    private struct Cache: Codable { var base: String; var rates: [String: Decimal]; var fetchedAt: Date }
    private let key = "lever.exchangeRates"
    private var memory: Cache?

    func rate(from: String, to: String) async -> Decimal? {
        if from == to { return 1 }
        if let cache = await cached(base: to), let r = cache.rates[from], r > 0 { return 1 / r }
        return nil
    }

    /// Converts an amount into `to`, or nil when no rate is available. Never guesses.
    func convert(_ amount: Decimal, from: String, to: String) async -> Decimal? {
        guard let rate = await rate(from: from, to: to) else { return nil }
        return (amount * rate).rounded(scale: 0)
    }

    private func cached(base: String) async -> Cache? {
        if let memory, memory.base == base, Date().timeIntervalSince(memory.fetchedAt) < 86_400 { return memory }
        if let data = AppGroup.sharedDefaults.data(forKey: key), let disk = try? JSONDecoder.lever.decode(Cache.self, from: data),
           disk.base == base, Date().timeIntervalSince(disk.fetchedAt) < 86_400 {
            memory = disk
            return disk
        }
        return await fetch(base: base)
    }

    private func fetch(base: String) async -> Cache? {
        guard let url = URL(string: "https://api.frankfurter.dev/v1/latest?from=\(base)") else { return nil }
        struct Response: Decodable { let base: String; let rates: [String: Double] }
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(Response.self, from: data) else { return nil }
        // Response rates are "1 base = x other"; store as other→base divisor.
        let cache = Cache(base: base, rates: decoded.rates.mapValues { Decimal($0) }, fetchedAt: .now)
        memory = cache
        if let encoded = try? JSONEncoder.lever.encode(cache) { AppGroup.sharedDefaults.set(encoded, forKey: key) }
        return cache
    }
}
