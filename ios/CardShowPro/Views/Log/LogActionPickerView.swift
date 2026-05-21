import SwiftUI

/// Pushed after tapping LOG on the home view. User picks Buy / Sell / Trade,
/// which then opens the Scanner in that mode.
struct LogActionPickerView: View {
    var body: some View {
        ZStack {
            Theme.Colors.bg.ignoresSafeArea()

            VStack(spacing: Theme.Spacing.lg) {
                VStack(spacing: Theme.Spacing.xs) {
                    Text("WHAT ARE YOU LOGGING?")
                        .font(Theme.Typography.label)
                        .tracking(2)
                        .foregroundStyle(Theme.Colors.textTertiary)
                    Text("Pick an action, then scan the card.")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .padding(.top, Theme.Spacing.xl)

                VStack(spacing: Theme.Spacing.md) {
                    ForEach(LogMode.allCases) { mode in
                        NavigationLink(destination: ScannerView(logMode: mode)) {
                            ModeButton(mode: mode)
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)

                Spacer()
            }
        }
        .navigationTitle("Log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.Colors.bg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

private struct ModeButton: View {
    let mode: LogMode

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: mode.icon)
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(mode.tint)
                .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 4) {
                Text(mode.title)
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(mode.subtitle)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.Colors.textTertiary)
        }
        .padding(Theme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .fill(Theme.Colors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                        .stroke(mode.tint.opacity(0.4), lineWidth: 1.5)
                )
        )
    }
}
