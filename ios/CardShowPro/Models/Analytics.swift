import Foundation

struct ShowSummary: Codable {
    let cardsLogged: Int
    let spent: Double
    let earned: Double
    let net: Double

    enum CodingKeys: String, CodingKey {
        case cardsLogged = "cards_logged"
        case spent, earned, net
    }
}

struct TopCard: Codable {
    let cardId: String
    let name: String?
    let gainPct: Double?

    enum CodingKeys: String, CodingKey {
        case cardId = "card_id"
        case name
        case gainPct = "gain_pct"
    }
}

struct AnalyticsSummary: Codable {
    let totalCards: Int
    let totalInvested: Double
    let totalRevenue: Double
    let netProfit: Double
    let unrealizedGain: Double
    let portfolioValue: Double
    let cardsHolding: Int
    let cardsSold: Int
    let topGainer: TopCard?
    let showSummary: ShowSummary

    enum CodingKeys: String, CodingKey {
        case totalCards = "total_cards"
        case totalInvested = "total_invested"
        case totalRevenue = "total_revenue"
        case netProfit = "net_profit"
        case unrealizedGain = "unrealized_gain"
        case portfolioValue = "portfolio_value"
        case cardsHolding = "cards_holding"
        case cardsSold = "cards_sold"
        case topGainer = "top_gainer"
        case showSummary = "show_summary"
    }
}
