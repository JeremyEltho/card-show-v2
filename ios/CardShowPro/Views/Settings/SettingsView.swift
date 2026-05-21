import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.bg.ignoresSafeArea()

                @Bindable var state = appState

                ScrollView {
                    VStack(spacing: Theme.Spacing.md) {
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

                        section("MODE") {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("On-device only — no backend, no login.")
                                    .font(Theme.Typography.caption)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                                Text("Card metadata + market price are fetched from pokemontcg.io directly.")
                                    .font(Theme.Typography.caption)
                                    .foregroundStyle(Theme.Colors.textTertiary)
                            }
                            .padding(.vertical, 4)
                        }

                        section("ABOUT") {
                            row("Version", "2.0.0")
                            Divider().background(Theme.Colors.divider)
                            row("Mode", "Offline-first", monospace: true)
                        }
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
                .font(Theme.Typography.label).tracking(1)
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
                     monospace: Bool = false) -> some View {
        HStack {
            Text(label).font(Theme.Typography.body).foregroundStyle(Theme.Colors.textSecondary)
            Spacer()
            Text(value)
                .font(monospace ? Theme.Typography.captionMono : Theme.Typography.body)
                .foregroundStyle(tint)
        }
        .padding(.vertical, 6)
    }
}
