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
    var marketPrice: Double?            // snapshotted at scan time
    var setName: String?                 // snapshotted at scan time
    var notes: String?                   // free-form vendor notes (user-editable)
    var sourceLocation: String?
    var paymentMethod: String?
    var counterparty: String?           // who I bought from / sold to
    /// Relative filename of the camera-captured photo under Documents/card_images/.
    /// Set at scan time. Used by the receipt exporter as the primary image
    /// source — falls back to cardImageUrl only when this is missing.
    var capturedImagePath: String?
    /// Shared UUID linking the two sides of a single trade transaction.
    /// Both LocalInventoryItem rows from one trade carry the same value.
    /// nil for buys, sells, and any pre-trade-feature entries.
    var tradeId: String?
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
        marketPrice: Double? = nil,
        setName: String? = nil,
        notes: String? = nil,
        sourceLocation: String? = nil,
        paymentMethod: String? = nil,
        counterparty: String? = nil,
        capturedImagePath: String? = nil,
        tradeId: String? = nil,
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
        self.marketPrice = marketPrice
        self.setName = setName
        self.notes = notes
        self.sourceLocation = sourceLocation
        self.paymentMethod = paymentMethod
        self.counterparty = counterparty
        self.capturedImagePath = capturedImagePath
        self.tradeId = tradeId
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
