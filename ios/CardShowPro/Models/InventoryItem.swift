import Foundation

struct CardSummary: Codable {
    let cardId: String
    let name: String?
    let setName: String?
    let imageUrlSm: String?
    let marketPrice: Double?

    enum CodingKeys: String, CodingKey {
        case cardId = "card_id"
        case name
        case setName = "set_name"
        case imageUrlSm = "image_url_sm"
        case marketPrice = "market_price"
    }
}

enum CardStatus: String, CaseIterable, Codable {
    case holding, bought, sold, traded, wishlist

    var displayName: String {
        switch self {
        case .holding: return "Holding"
        case .bought: return "Bought"
        case .sold: return "Sold"
        case .traded: return "Traded"
        case .wishlist: return "Wishlist"
        }
    }

    var color: String {
        switch self {
        case .holding: return "blue"
        case .bought: return "green"
        case .sold: return "red"
        case .traded: return "orange"
        case .wishlist: return "purple"
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

struct InventoryItem: Codable, Identifiable {
    let id: String
    let cardId: String
    let card: CardSummary?
    let status: String
    let condition: String
    let quantity: Int
    let purchasePrice: Double?
    let salePrice: Double?
    let marketPriceAtScan: Double?
    let unrealizedGain: Double?
    let notes: String?
    let sourceLocation: String?
    let acquiredAt: String
    let soldAt: String?
    let createdAt: String
    let clientId: String?

    enum CodingKeys: String, CodingKey {
        case id, card, status, condition, quantity, notes
        case cardId = "card_id"
        case purchasePrice = "purchase_price"
        case salePrice = "sale_price"
        case marketPriceAtScan = "market_price_at_scan"
        case unrealizedGain = "unrealized_gain"
        case sourceLocation = "source_location"
        case acquiredAt = "acquired_at"
        case soldAt = "sold_at"
        case createdAt = "created_at"
        case clientId = "client_id"
    }
}

struct InventoryListResponse: Codable {
    let items: [InventoryItem]
    let total: Int
    let page: Int
    let pages: Int
}

struct CreateInventoryRequest: Codable {
    let cardId: String
    let status: String
    let condition: String
    let quantity: Int
    let purchasePrice: Double?
    let salePrice: Double?
    let marketPriceAtScan: Double?
    let notes: String?
    let sourceLocation: String?
    let paymentMethod: String?
    let clientId: String

    enum CodingKeys: String, CodingKey {
        case status, condition, quantity, notes
        case cardId = "card_id"
        case purchasePrice = "purchase_price"
        case salePrice = "sale_price"
        case marketPriceAtScan = "market_price_at_scan"
        case sourceLocation = "source_location"
        case paymentMethod = "payment_method"
        case clientId = "client_id"
    }
}
