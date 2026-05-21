import SwiftUI

struct SettingsView: View {
    @Environment(AuthViewModel.self) private var authVM
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var editingURL = false
    @State private var draftURL = ""
    @State private var connectionStatus: ConnectionStatus = .unknown

    enum ConnectionStatus { case unknown, testing, ok, failed }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.bg.ignoresSafeArea()

                @Bindable var state = appState

                ScrollView {
                    VStack(spacing: Theme.Spacing.md) {
                        // Account
                        section("ACCOUNT") {
                            if let user = authVM.currentUser {
                                row("Name", user.displayName)
                                Divider().background(Theme.Colors.divider)
                                row("Email", user.email)
                            }
                        }

                        // Active show
                        section("ACTIVE SHOW") {
                            HStack(spacing: Theme.Spacing.sm) {
                                Image(systemName: "mappin.circle.fill")
                                    .foregroundStyle(Theme.Colors.amber)
                                TextField("e.g. GameStop Nationals", text: $state.activeShowName)
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                    .autocorrectionDisabled()
                            }
                            .font(Theme.Typography.body)
                            .padding(.vertical, 4)
                        }

                        // Connection — editable backend URL
                        section("CONNECTION") {
                            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                                HStack {
                                    Text("BACKEND URL")
                                        .font(Theme.Typography.label)
                                        .tracking(0.5)
                                        .foregroundStyle(Theme.Colors.textTertiary)
                                    Spacer()
                                    if connectionStatus == .ok {
                                        connectionBadge("CONNECTED", color: Theme.Colors.green)
                                    } else if connectionStatus == .failed {
                                        connectionBadge("UNREACHABLE", color: Theme.Colors.red)
                                    }
                                }
                                if editingURL {
                                    TextField("http://192.168.1.42:8000/api/v1", text: $draftURL)
                                        .font(Theme.Typography.captionMono)
                                        .foregroundStyle(Theme.Colors.textPrimary)
                                        .keyboardType(.URL)
                                        .autocorrectionDisabled()
                                        .autocapitalization(.none)
                                        .padding(8)
                                        .background(Theme.Colors.surfaceHi)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                    HStack(spacing: Theme.Spacing.sm) {
                                        Button("Cancel") {
                                            editingURL = false
                                            draftURL = NetworkService.baseURL
                                        }
                                        .foregroundStyle(Theme.Colors.textSecondary)
                                        Spacer()
                                        Button("Save") {
                                            NetworkService.setBaseURL(draftURL)
                                            editingURL = false
                                            connectionStatus = .unknown
                                            Task { await testConnection() }
                                        }
                                        .foregroundStyle(Theme.Colors.amber)
                                        .fontWeight(.semibold)
                                    }
                                    .font(Theme.Typography.body)
                                } else {
                                    Text(NetworkService.baseURL)
                                        .font(Theme.Typography.captionMono)
                                        .foregroundStyle(Theme.Colors.textPrimary)
                                        .lineLimit(2)
                                        .truncationMode(.middle)
                                }
                                HStack(spacing: Theme.Spacing.sm) {
                                    if !editingURL {
                                        Button {
                                            draftURL = NetworkService.baseURL
                                            editingURL = true
                                        } label: {
                                            Label("Edit", systemImage: "pencil")
                                                .font(Theme.Typography.caption)
                                                .foregroundStyle(Theme.Colors.amber)
                                        }
                                    }
                                    Spacer()
                                    Button {
                                        Task { await testConnection() }
                                    } label: {
                                        if connectionStatus == .testing {
                                            ProgressView().scaleEffect(0.6).tint(Theme.Colors.amber)
                                        } else {
                                            Label("Test", systemImage: "arrow.triangle.2.circlepath")
                                                .font(Theme.Typography.caption)
                                                .foregroundStyle(Theme.Colors.amber)
                                        }
                                    }
                                    .disabled(connectionStatus == .testing)
                                }
                            }
                            .padding(.vertical, 4)
                        }

                        // Sync status
                        section("SYNC") {
                            row("Network", state.networkReachable ? "Online" : "Offline",
                                 tint: state.networkReachable ? Theme.Colors.green : Theme.Colors.red)
                            Divider().background(Theme.Colors.divider)
                            row("Pending operations", "\(state.syncPending)",
                                tint: state.syncPending > 0 ? Theme.Colors.amber : Theme.Colors.textPrimary)
                        }

                        // About
                        section("ABOUT") {
                            row("Version", "2.0.0")
                        }

                        // Sign out
                        Button {
                            Task {
                                await authVM.logout()
                                dismiss()
                            }
                        } label: {
                            Text("SIGN OUT")
                                .font(Theme.Typography.label)
                                .tracking(2)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(Theme.Colors.redSoft)
                                .foregroundStyle(Theme.Colors.red)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                        }
                        .padding(.top, Theme.Spacing.sm)
                    }
                    .padding(Theme.Spacing.md)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.Colors.amber)
                }
            }
        }
        .task { await testConnection() }
    }

    private func connectionBadge(_ label: String, color: Color) -> some View {
        Text(label)
            .font(Theme.Typography.label)
            .tracking(0.5)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.18)))
            .foregroundStyle(color)
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title)
                .font(Theme.Typography.label)
                .tracking(1)
                .foregroundStyle(Theme.Colors.textTertiary)
                .padding(.horizontal, Theme.Spacing.sm)
            VStack(spacing: 0) {
                content()
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.sm)
            }
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .fill(Theme.Colors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.md)
                            .stroke(Theme.Colors.border, lineWidth: 1)
                    )
            )
        }
    }

    private func row(_ label: String, _ value: String, tint: Color = Theme.Colors.textPrimary,
                     monospace: Bool = false, truncate: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
            Spacer()
            Text(value)
                .font(monospace ? Theme.Typography.captionMono : Theme.Typography.body)
                .foregroundStyle(tint)
                .lineLimit(truncate ? 1 : nil)
                .truncationMode(.middle)
        }
        .padding(.vertical, 6)
    }

    private func testConnection() async {
        connectionStatus = .testing
        let urlStr = NetworkService.baseURL.replacingOccurrences(of: "/api/v1", with: "/health")
        guard let url = URL(string: urlStr) else {
            connectionStatus = .failed
            return
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 3
        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                connectionStatus = .ok
            } else {
                connectionStatus = .failed
            }
        } catch {
            connectionStatus = .failed
        }
    }
}
