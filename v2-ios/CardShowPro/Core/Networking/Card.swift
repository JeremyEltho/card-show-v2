import Foundation
import UIKit

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
    var cardId: String
    var name: String
    var setName: String?
    var number: String?
    var imageUrlSm: String?
    var confidence: Float
    var marketPrice: Double?
    var pipeline: String
    /// Live camera capture of the card at the moment of match. Set by
    /// CardScannerService. nil if rendering failed or this is a manual-search
    /// match (where there's no live frame).
    var capturedImage: UIImage? = nil
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

// MARK: - Inventory status / condition enums

enum CardStatus: String, CaseIterable, Codable {
    case holding, bought, sold, traded

    var displayName: String {
        switch self {
        case .holding: return "Holding"
        case .bought: return "Bought"
        case .sold: return "Sold"
        case .traded: return "Traded"
        }
    }
}

enum CardCondition: String, CaseIterable, Codable {
    case mint
    case near_mint
    case lightly_played
    case moderately_played
    case heavily_played
    case damaged

    var displayName: String {
        switch self {
        case .mint: return "Mint"
        case .near_mint: return "Near Mint"
        case .lightly_played: return "Lightly Played"
        case .moderately_played: return "Moderately Played"
        case .heavily_played: return "Heavily Played"
        case .damaged: return "Damaged"
        }
    }
}
