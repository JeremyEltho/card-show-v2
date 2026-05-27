import Foundation

/// Calls pokemontcg.io directly from the device — no backend required.
///
/// Endpoints used:
///   GET https://api.pokemontcg.io/v2/cards?q=name:"Charizard"&pageSize=10
///
/// Pricing comes embedded in `tcgplayer.prices` on each card response,
/// so we don't need a separate JustTCG call.
actor PokemonTCGService {
    static let shared = PokemonTCGService()

    private let session: URLSession
    private let decoder: JSONDecoder
    private let baseURL = "https://api.pokemontcg.io/v2"

    /// Bounded in-memory cache (card name → result) so we don't hammer the
    /// API for cards the vendor has already scanned in this session. NSCache
    /// auto-purges under memory pressure; the count limit keeps the working
    /// set reasonable on long sessions.
    private let cache: NSCache<NSString, CachedMatch> = {
        let c = NSCache<NSString, CachedMatch>()
        c.countLimit = 200
        return c
    }()

    /// NSCache requires class-typed values, so we wrap the CardMatch struct.
    private final class CachedMatch {
        let match: CardMatch
        init(_ match: CardMatch) { self.match = match }
    }

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8
        config.waitsForConnectivity = false
        session = URLSession(configuration: config)
        decoder = JSONDecoder()
    }

    /// Look up a card by name. Returns the best match with metadata + market price.
    /// Returns nil if the API is unreachable or no card found.
    func lookup(name: String) async -> CardMatch? {
        let key = name.lowercased() as NSString
        if let cached = cache.object(forKey: key) { return cached.match }

        // Build query: name search with prefix wildcard
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
        let urlStr = "\(baseURL)/cards?q=name:\"\(encoded)\"&pageSize=5"
        guard let url = URL(string: urlStr) else { return nil }

        do {
            var req = URLRequest(url: url)
            // pokemontcg.io accepts an optional API key for higher rate limits
            if let key = Bundle.main.object(forInfoDictionaryKey: "POKEMONTCG_API_KEY") as? String,
               !key.isEmpty, key != "$(POKEMONTCG_API_KEY)" {
                req.setValue(key, forHTTPHeaderField: "X-Api-Key")
            }
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            let parsed = try decoder.decode(APIResponse.self, from: data)
            guard let firstCard = parsed.data.first else { return nil }

            let match = CardMatch(
                cardId: firstCard.id,
                name: firstCard.name,
                setName: firstCard.set?.name,
                number: firstCard.number,
                imageUrlSm: firstCard.images?.small,
                confidence: 1.0,
                marketPrice: extractMarketPrice(firstCard.tcgplayer?.prices),
                pipeline: "pokemontcg_api"
            )
            cache.setObject(CachedMatch(match), forKey: key)
            return match
        } catch {
            return nil
        }
    }

    /// Full-text search for cards (used by manual assist).
    func search(query: String, limit: Int = 10) async -> [CardSearchResult] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let urlStr = "\(baseURL)/cards?q=name:\"\(encoded)*\"&pageSize=\(limit)"
        guard let url = URL(string: urlStr) else { return [] }
        do {
            let (data, _) = try await session.data(from: url)
            let parsed = try decoder.decode(APIResponse.self, from: data)
            return parsed.data.map {
                CardSearchResult(id: $0.id, name: $0.name,
                                 setName: $0.set?.name, number: $0.number,
                                 imageUrlSm: $0.images?.small)
            }
        } catch {
            return []
        }
    }

    private func extractMarketPrice(_ prices: TCGPlayerPrices?) -> Double? {
        guard let prices else { return nil }
        // Prefer holofoil → reverseHolofoil → normal market prices
        return prices.holofoil?.market
            ?? prices.reverseHolofoil?.market
            ?? prices.normal?.market
            ?? prices.unlimited?.market
            ?? prices.firstEditionNormal?.market
    }

    // MARK: - API response shapes

    private struct APIResponse: Decodable {
        let data: [APICard]
    }

    private struct APICard: Decodable {
        let id: String
        let name: String
        let number: String?
        let images: APIImages?
        let set: APISet?
        let tcgplayer: TCGPlayerData?
    }

    private struct APIImages: Decodable {
        let small: String?
        let large: String?
    }

    private struct APISet: Decodable {
        let id: String?
        let name: String?
        let series: String?
    }

    private struct TCGPlayerData: Decodable {
        let prices: TCGPlayerPrices?
    }

    private struct TCGPlayerPrices: Decodable {
        let holofoil: PriceBracket?
        let reverseHolofoil: PriceBracket?
        let normal: PriceBracket?
        let unlimited: PriceBracket?
        let firstEditionNormal: PriceBracket?
    }

    private struct PriceBracket: Decodable {
        let low: Double?
        let mid: Double?
        let high: Double?
        let market: Double?
    }
}
