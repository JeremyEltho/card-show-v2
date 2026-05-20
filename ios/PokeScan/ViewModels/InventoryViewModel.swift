import Foundation
import Observation

@Observable
final class InventoryViewModel {
    var items: [InventoryItem] = []
    var isLoading = false
    var isLoadingMore = false
    var errorMessage: String?
    var searchText = ""
    var statusFilter: String? = nil
    var currentPage = 1
    var hasMore = true
    var totalCount = 0

    private let service = InventoryService.shared

    var filteredItems: [InventoryItem] {
        guard !searchText.isEmpty else { return items }
        return items.filter {
            $0.card?.name?.localizedCaseInsensitiveContains(searchText) == true ||
            $0.notes?.localizedCaseInsensitiveContains(searchText) == true
        }
    }

    func load() async {
        isLoading = true
        currentPage = 1
        errorMessage = nil
        do {
            let resp = try await service.fetchItems(status: statusFilter, page: 1)
            items = resp.items
            totalCount = resp.total
            hasMore = resp.page < resp.pages
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func loadNextPage() async {
        guard hasMore, !isLoadingMore else { return }
        isLoadingMore = true
        let next = currentPage + 1
        do {
            let resp = try await service.fetchItems(status: statusFilter, page: next)
            items.append(contentsOf: resp.items)
            currentPage = next
            hasMore = next < resp.pages
        } catch { }
        isLoadingMore = false
    }

    func markSold(item: InventoryItem, price: Double) async {
        do {
            let updated = try await service.updateItem(id: item.id, status: "sold", salePrice: price)
            if let idx = items.firstIndex(where: { $0.id == item.id }) {
                items[idx] = updated
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(item: InventoryItem) async {
        do {
            try await service.deleteItem(id: item.id)
            items.removeAll { $0.id == item.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
