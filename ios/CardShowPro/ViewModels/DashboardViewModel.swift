import Foundation
import Observation

@MainActor
@Observable
final class DashboardViewModel {
    var summary: InventoryService.TodaySummary?
    var isLoading = false

    private let service = InventoryService.shared

    func load() async {
        isLoading = true
        summary = service.summary()
        isLoading = false
    }
}
