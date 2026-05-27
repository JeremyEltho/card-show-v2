import Foundation
import SwiftData

/// Local-only inventory. All data lives in SwiftData on the device.
/// Vendors need this to work at conventions with no Wi-Fi.
@MainActor
final class InventoryService {
    static let shared = InventoryService()

    private var modelContext: ModelContext?

    private init() {}

    /// Wire up the SwiftData container from the app's @main entry point.
    func attach(container: ModelContainer) {
        self.modelContext = container.mainContext
    }

    // MARK: - CRUD

    @discardableResult
    func add(card: CardMatch, purchasePrice: Double?, status: String,
             condition: String, sourceLocation: String,
             capturedImagePath: String? = nil,
             tradeId: String? = nil,
             notes: String? = nil) -> LocalInventoryItem? {
        guard let ctx = modelContext else { return nil }
        let item = LocalInventoryItem(
            cardId: card.cardId.isEmpty ? card.name.lowercased() : card.cardId,
            cardName: card.name,
            cardImageUrl: card.imageUrlSm,
            status: status,
            condition: condition,
            quantity: 1,
            purchasePrice: purchasePrice ?? card.marketPrice,
            salePrice: status == "sold" ? (purchasePrice ?? card.marketPrice) : nil,
            marketPrice: card.marketPrice,
            setName: card.setName,
            notes: notes,
            sourceLocation: sourceLocation.isEmpty ? nil : sourceLocation,
            capturedImagePath: capturedImagePath,
            tradeId: tradeId,
            acquiredAt: .now
        )
        ctx.insert(item)
        try? ctx.save()
        return item
    }

    func markSold(item: LocalInventoryItem, price: Double) {
        guard let ctx = modelContext else { return }
        item.status = "sold"
        item.salePrice = price
        try? ctx.save()
    }

    /// Apply arbitrary field edits to an inventory item. Pass only the fields you
    /// want to change; the rest stay untouched.
    func update(
        item: LocalInventoryItem,
        status: String? = nil,
        condition: String? = nil,
        purchasePrice: Double? = nil,
        salePrice: Double? = nil,
        notes: String? = nil,
        sourceLocation: String? = nil,
        paymentMethod: String? = nil,
        counterparty: String? = nil
    ) {
        guard let ctx = modelContext else { return }
        if let status { item.status = status }
        if let condition { item.condition = condition }
        if let purchasePrice { item.purchasePrice = purchasePrice }
        if let salePrice { item.salePrice = salePrice }
        if let notes { item.notes = notes }
        if let sourceLocation { item.sourceLocation = sourceLocation }
        if let paymentMethod { item.paymentMethod = paymentMethod }
        if let counterparty { item.counterparty = counterparty }
        try? ctx.save()
    }

    func delete(item: LocalInventoryItem) {
        guard let ctx = modelContext else { return }
        CardImageStore.delete(item.capturedImagePath)
        ctx.delete(item)
        try? ctx.save()
    }

    /// Bulk-delete every inventory item in a single save. Used by the
    /// "Delete all inventory" action in Settings. Cheaper than looping
    /// `delete(item:)` because it doesn't pay the save() round-trip per row.
    func clearAll() {
        guard let ctx = modelContext else { return }
        let all = fetchAll()
        for item in all {
            CardImageStore.delete(item.capturedImagePath)
            ctx.delete(item)
        }
        try? ctx.save()
    }

    func fetchAll(status: String? = nil) -> [LocalInventoryItem] {
        guard let ctx = modelContext else { return [] }
        var descriptor = FetchDescriptor<LocalInventoryItem>(
            sortBy: [SortDescriptor(\.acquiredAt, order: .reverse)]
        )
        if let s = status {
            descriptor.predicate = #Predicate { $0.status == s }
        }
        return (try? ctx.fetch(descriptor)) ?? []
    }

    // MARK: - Analytics

    struct TodaySummary {
        let buys: Double
        let sells: Double
        let net: Double
        let cardsIn: Int
        let cardsOut: Int
        let allTimeNet: Double
        let stockCount: Int
    }

    func summary() -> TodaySummary {
        let all = fetchAll()
        let startOfDay = Calendar.current.startOfDay(for: .now)
        let today = all.filter { $0.acquiredAt >= startOfDay }

        let cardsIn = today.filter { $0.status == "bought" || $0.status == "holding" }.count
        let cardsOut = today.filter { $0.status == "sold" }.count
        let buys = today
            .filter { $0.status == "bought" || $0.status == "holding" }
            .compactMap { $0.purchasePrice }
            .reduce(0, +)
        let sells = today
            .filter { $0.status == "sold" }
            .compactMap { $0.salePrice }
            .reduce(0, +)

        let allTimeRevenue = all.filter { $0.status == "sold" }.compactMap { $0.salePrice }.reduce(0, +)
        let allTimeCost = all.compactMap { $0.purchasePrice }.reduce(0, +)
        let stockCount = all.filter { $0.status == "bought" || $0.status == "holding" }.count

        return TodaySummary(
            buys: buys, sells: sells, net: sells - buys,
            cardsIn: cardsIn, cardsOut: cardsOut,
            allTimeNet: allTimeRevenue - allTimeCost,
            stockCount: stockCount
        )
    }
}
