import Foundation

struct Card: Codable, Identifiable {
    let id: String
    let name: String
    let setId: String?
    let setName: String?
    let series: String?
    let number: String?
    let rarity: String?
    let supertype: String?
    let subtypes: [String]
    let hp: Int?
    let types: [String]
    let imageUrlSm: String?
    let imageUrlLg: String?

    var id_: String { id }

    enum CodingKeys: String, CodingKey {
        case id = "card_id"
        case name
        case setId = "set_id"
        case setName = "set_name"
        case series, number, rarity, supertype, subtypes, hp, types
        case imageUrlSm = "image_url_sm"
        case imageUrlLg = "image_url_lg"
    }
}

struct CardPrice: Codable {
    let cardId: String
    let marketPrice: Double?
    let lowPrice: Double?
    let midPrice: Double?
    let highPrice: Double?
    let foilMarket: Double?
    let source: String?

    enum CodingKeys: String, CodingKey {
        case cardId = "card_id"
        case marketPrice = "market_price"
        case lowPrice = "low_price"
        case midPrice = "mid_price"
        case highPrice = "high_price"
        case foilMarket = "foil_market"
        case source
    }
}

struct CardMatch {
    let cardId: String
    let name: String
    let setName: String?
    let number: String?
    let imageUrlSm: String?
    var confidence: Float
    var marketPrice: Double?
    var pipeline: String
}

struct CardSearchResult: Codable, Identifiable {
    let id: String
    let name: String
    let setName: String?
    let number: String?
    let imageUrlSm: String?

    enum CodingKeys: String, CodingKey {
        case id = "card_id"
        case name
        case setName = "set_name"
        case number
        case imageUrlSm = "image_url_sm"
    }
}
