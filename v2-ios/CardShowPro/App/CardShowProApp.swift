import SwiftUI
import SwiftData

@main
struct CardShowProApp: App {
    @State private var appState = AppState()

    /// SwiftData container — all inventory lives locally on the device.
    /// No backend required. No login required. Works offline.
    private let container: ModelContainer = {
        let schema = Schema([LocalInventoryItem.self, OfflineOperation.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        let c = try! ModelContainer(for: schema, configurations: [config])
        Task { @MainActor in InventoryService.shared.attach(container: c) }
        return c
    }()

    init() {
        // Preload the 5,437-name canonical dictionary off the main thread so the
        // first scan doesn't stall the camera while it parses JSON + builds the map.
        FuzzyMatcher.preload()
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(appState)
                .preferredColorScheme(.dark)
        }
        .modelContainer(container)
    }
}
