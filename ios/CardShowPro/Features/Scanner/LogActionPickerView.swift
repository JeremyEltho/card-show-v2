import SwiftUI

/// Pushed after tapping LOG on the home view. User picks Buy / Sell / Trade,
/// chooses receipt mode (with receipt vs fast/no receipt), then opens the
/// scanner. Receipt mode is sticky for the navigation push.
struct LogActionPickerView: View {
    @State private var settings = AppSettings.shared
    @State private var receiptMode: ReceiptMode = AppSettings.shared.defaultReceiptMode

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
                        NavigationLink(
                            destination: ScannerView(logMode: mode, receiptMode: receiptMode)
                        ) {
                            ModeButton(mode: mode)
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)

                Spacer()

                receiptModePicker
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.bottom, Theme.Spacing.lg)
            }
        }
        .navigationTitle("Log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.Colors.bg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    // MARK: - Receipt mode picker

    private var receiptModePicker: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("SCAN MODE")
                .font(Theme.Typography.label)
                .tracking(2)
                .foregroundStyle(Theme.Colors.textTertiary)

            HStack(spacing: Theme.Spacing.sm) {
                ForEach(ReceiptMode.allCases) { mode in
                    Button {
                        receiptMode = mode
                    } label: {
                        ReceiptModeChip(mode: mode, selected: receiptMode == mode)
                    }
                    .buttonStyle(.plain)
                }
            }

            Text(receiptMode.subtitle)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .padding(.top, 2)
        }
    }
}

private struct ReceiptModeChip: View {
    let mode: ReceiptMode
    let selected: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: mode.icon)
                .font(.system(size: 13, weight: .heavy))
            Text(mode.title)
                .font(Theme.Typography.label)
                .tracking(1.5)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .fill(selected ? mode.tint : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .stroke(selected ? mode.tint : Theme.Colors.border,
                                style: StrokeStyle(lineWidth: 1.5,
                                                   dash: selected ? [] : [4, 3]))
                )
        )
        .foregroundStyle(selected ? .black : Theme.Colors.textSecondary)
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
