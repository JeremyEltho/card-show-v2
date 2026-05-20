import Foundation
import SwiftData

@Model
final class LocalInventoryItem {
    @Attribute(.unique) var id: UUID
    var cardId: String
    var cardName: String?
    var cardImageUrl: String?
    var status: String
    var condition: String
    var quantity: Int
    var purchasePrice: Double?
    var salePrice: Double?
    var notes: String?
    var sourceLocation: String?
    var acquiredAt: Date
    var syncedToServer: Bool
    var serverItemId: String?
    var clientId: String

    init(
        cardId: String,
        cardName: String? = nil,
        cardImageUrl: String? = nil,
        status: String = "holding",
        condition: String = "near_mint",
        quantity: Int = 1,
        purchasePrice: Double? = nil,
        salePrice: Double? = nil,
        notes: String? = nil,
        sourceLocation: String? = nil,
        acquiredAt: Date = .now,
        syncedToServer: Bool = false,
        serverItemId: String? = nil
    ) {
        let newId = UUID()
        self.id = newId
        self.clientId = newId.uuidString
        self.cardId = cardId
        self.cardName = cardName
        self.cardImageUrl = cardImageUrl
        self.status = status
        self.condition = condition
        self.quantity = quantity
        self.purchasePrice = purchasePrice
        self.salePrice = salePrice
        self.notes = notes
        self.sourceLocation = sourceLocation
        self.acquiredAt = acquiredAt
        self.syncedToServer = syncedToServer
        self.serverItemId = serverItemId
    }
}

@Model
final class OfflineOperation {
    @Attribute(.unique) var clientId: UUID
    var type: String
    var payloadJson: Data
    var retryCount: Int
    var createdAt: Date

    init(type: String, payloadJson: Data) {
        self.clientId = UUID()
        self.type = type
        self.payloadJson = payloadJson
        self.retryCount = 0
        self.createdAt = .now
    }
}
