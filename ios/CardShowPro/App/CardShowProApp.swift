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

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .preferredColorScheme(.dark)
        }
        .modelContainer(container)
    }
}
