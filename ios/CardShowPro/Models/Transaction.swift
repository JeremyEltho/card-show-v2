import Foundation

struct Transaction: Codable, Identifiable {
    let id: String
    let userId: String
    let inventoryItemId: String?
    let type: String
    let price: Double
    let quantity: Int
    let paymentMethod: String?
    let location: String?
    let notes: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, type, price, quantity, location, notes
        case userId = "user_id"
        case inventoryItemId = "inventory_item_id"
        case paymentMethod = "payment_method"
        case createdAt = "created_at"
    }
}
