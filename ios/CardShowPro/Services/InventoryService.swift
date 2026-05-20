import Foundation

actor InventoryService {
    static let shared = InventoryService()
    private let network = NetworkService.shared

    func fetchItems(status: String? = nil, page: Int = 1) async throws -> InventoryListResponse {
        var path = "/inventory?page=\(page)&limit=25&order=desc"
        if let s = status { path += "&status=\(s)" }
        return try await network.request(path)
    }

    func addItem(_ req: CreateInventoryRequest) async throws -> InventoryItem {
        try await network.post("/inventory", body: req)
    }

    func updateItem(id: String, status: String? = nil, salePrice: Double? = nil,
                    condition: String? = nil, notes: String? = nil) async throws -> InventoryItem {
        struct Patch: Encodable {
            let status: String?; let sale_price: Double?
            let condition: String?; let notes: String?
        }
        return try await network.patch("/inventory/\(id)",
            body: Patch(status: status, sale_price: salePrice, condition: condition, notes: notes))
    }

    func deleteItem(id: String) async throws {
        try await network.delete("/inventory/\(id)")
    }

    func fetchSummary() async throws -> AnalyticsSummary {
        try await network.request("/analytics/summary")
    }
}
