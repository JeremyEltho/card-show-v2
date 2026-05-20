import SwiftUI
import SwiftData

@main
struct PokeScanApp: App {
    @State private var authVM = AuthViewModel()
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            Group {
                if authVM.isAuthenticated {
                    RootView()
                } else {
                    LoginView()
                }
            }
            .environment(authVM)
            .environment(appState)
        }
        .modelContainer(for: [LocalInventoryItem.self, OfflineOperation.self])
    }
}
