import SwiftUI

struct SettingsView: View {
    @Environment(AuthViewModel.self) private var authVM
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState
        NavigationStack {
            Form {
                Section("Active Show") {
                    TextField("Show name (e.g. GameStop Nationals)", text: $state.activeShowName)
                }

                Section("Account") {
                    if let user = authVM.currentUser {
                        LabeledContent("Email", value: user.email)
                        LabeledContent("Name", value: user.displayName)
                    }
                    Button("Sign Out", role: .destructive) {
                        Task { await authVM.logout() }
                    }
                }

                Section("Sync") {
                    LabeledContent("Pending operations", value: "\(appState.syncPending)")
                    LabeledContent("Network", value: appState.networkReachable ? "Online" : "Offline")
                }

                Section("About") {
                    LabeledContent("Version", value: "2.0.0")
                    LabeledContent("Backend", value: NetworkService.baseURL)
                }
            }
            .navigationTitle("Settings")
        }
    }
}
