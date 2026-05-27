import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class InventoryViewModel {
    var items: [LocalInventoryItem] = []
    var isLoading = false
    var errorMessage: String?
    var searchText = ""
    var statusFilter: String? = "bought"
    var totalCount: Int = 0

    private let service = InventoryService.shared

    var filteredItems: [LocalInventoryItem] {
        guard !searchText.isEmpty else { return items }
        return items.filter {
            $0.cardName?.localizedCaseInsensitiveContains(searchText) == true ||
            $0.notes?.localizedCaseInsensitiveContains(searchText) == true ||
            $0.cardId.localizedCaseInsensitiveContains(searchText)
        }
    }

    func load() async {
        isLoading = true
        items = service.fetchAll(status: statusFilter)
        totalCount = items.count
        isLoading = false
    }

    func markSold(item: LocalInventoryItem, price: Double) async {
        service.markSold(item: item, price: price)
        await load()
    }

    func delete(item: LocalInventoryItem) async {
        service.delete(item: item)
        items.removeAll { $0.id == item.id }
        totalCount = items.count
    }
}
