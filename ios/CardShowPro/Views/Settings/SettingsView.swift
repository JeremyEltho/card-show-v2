import SwiftUI

struct SettingsView: View {
    @Environment(AuthViewModel.self) private var authVM
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

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
                            Divider().background(Theme.Colors.divider)
                            row("Backend", NetworkService.baseURL, monospace: true, truncate: true)
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
}
