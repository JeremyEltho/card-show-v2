import Foundation
import Observation

@Observable
final class DashboardViewModel {
    var summary: AnalyticsSummary?
    var isLoading = false
    var errorMessage: String?

    private let service = InventoryService.shared

    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            summary = try await service.fetchSummary()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
