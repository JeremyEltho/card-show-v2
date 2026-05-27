import SwiftUI

/// Sectioned settings screen. Reachable from the gear icon on HomeView.
/// Absorbs what used to live on ProfileView (vendor identity, active show)
/// plus new scan defaults that persist across launches.
struct SettingsView: View {
    @State private var settings = AppSettings.shared
    @State private var showResetConfirm = false
    @State private var showClearDataConfirm = false
    @Environment(\.dismiss) private var dismiss

    private let conditions = ["mint", "near_mint", "lightly_played",
                              "moderately_played", "heavily_played", "damaged"]

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.bg.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: Theme.Spacing.md) {
                        vendorSection
                        activeShowSection
                        scanDefaultsSection
                        dataSection
                        aboutSection
                    }
                    .padding(Theme.Spacing.md)
                    .padding(.bottom, Theme.Spacing.xl)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Theme.Colors.bg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.Colors.amber)
                        .fontWeight(.semibold)
                }
            }
            .confirmationDialog("Reset vendor identity?",
                                isPresented: $showResetConfirm,
                                titleVisibility: .visible) {
                Button("Reset", role: .destructive) { settings.resetVendorIdentity() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Clears vendor name, active show, and recent shows. Doesn't touch your inventory.")
            }
            .confirmationDialog("Clear all inventory?",
                                isPresented: $showClearDataConfirm,
                                titleVisibility: .visible) {
                Button("Clear All", role: .destructive) {
                    clearAllInventory()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Deletes every logged card and its receipt photo. This can't be undone.")
            }
        }
    }

    // MARK: - Vendor

    private var vendorSection: some View {
        section("VENDOR") {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "person.crop.square.fill")
                    .foregroundStyle(Theme.Colors.magenta)
                TextField("Your name or shop", text: $settings.vendorName)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.words)
            }
            .font(Theme.Typography.body)
            .padding(.vertical, 4)

            footnote("Shown at the bottom of every saved receipt.")
        }
    }

    // MARK: - Active show

    private var activeShowSection: some View {
        section("ACTIVE SHOW") {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "mappin.circle.fill")
                    .foregroundStyle(Theme.Colors.amber)
                TextField("e.g. GameStop Nationals", text: $settings.activeShowName)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.words)
                if !settings.activeShowName.isEmpty {
                    Button {
                        settings.activeShowName = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .font(Theme.Typography.body)
            .padding(.vertical, 4)

            if !settings.recentShows.isEmpty {
                Divider().background(Theme.Colors.divider)
                    .padding(.vertical, 6)
                VStack(alignment: .leading, spacing: 6) {
                    Text("RECENT")
                        .font(Theme.Typography.label)
                        .tracking(1)
                        .foregroundStyle(Theme.Colors.textTertiary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(settings.recentShows, id: \.self) { name in
                                Button {
                                    settings.activeShowName = name
                                } label: {
                                    Text(name.uppercased())
                                        .font(Theme.Typography.label)
                                        .tracking(1)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(
                                            Capsule().fill(Theme.Colors.amberSoft)
                                                .overlay(Capsule().stroke(Theme.Colors.amber.opacity(0.5), lineWidth: 1))
                                        )
                                        .foregroundStyle(Theme.Colors.amber)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Scan defaults

    private var scanDefaultsSection: some View {
        section("SCAN DEFAULTS") {
            pickerRow(
                label: "LOG MODE",
                tint: settings.defaultLogMode.tint,
                selection: Binding(
                    get: { settings.defaultLogMode },
                    set: { settings.defaultLogMode = $0 }
                ),
                options: LogMode.allCases,
                display: { $0.title }
            )
            Divider().background(Theme.Colors.divider)

            pickerRow(
                label: "RECEIPT MODE",
                tint: settings.defaultReceiptMode.tint,
                selection: Binding(
                    get: { settings.defaultReceiptMode },
                    set: { settings.defaultReceiptMode = $0 }
                ),
                options: ReceiptMode.allCases,
                display: { $0.title }
            )
            Divider().background(Theme.Colors.divider)

            pickerRow(
                label: "CONDITION",
                tint: Theme.Colors.amber,
                selection: $settings.defaultCondition,
                options: conditions,
                display: { $0.replacingOccurrences(of: "_", with: " ").capitalized }
            )

            Divider().background(Theme.Colors.divider)

            pickerRow(
                label: "DAILY TARGET",
                tint: Theme.Colors.green,
                selection: $settings.dailyTarget,
                options: [100.0, 200.0, 500.0, 1000.0, 2500.0, 5000.0],
                display: { String(format: "$%.0f", $0) }
            )

            footnote("Pre-selected when you open the scanner. Daily target drives the home-screen progress bar.")
        }
    }

    // MARK: - Data

    private var dataSection: some View {
        section("DATA") {
            Button {
                showResetConfirm = true
            } label: {
                actionRow(icon: "arrow.uturn.backward",
                          label: "Reset vendor identity",
                          tint: Theme.Colors.textPrimary)
            }
            .buttonStyle(.plain)

            Divider().background(Theme.Colors.divider)

            Button {
                showClearDataConfirm = true
            } label: {
                actionRow(icon: "trash.fill",
                          label: "Delete all inventory",
                          tint: Theme.Colors.red)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        section("ABOUT") {
            infoRow("Mode", "On-device only", mono: true)
            Divider().background(Theme.Colors.divider)
            infoRow("Version", "2.0.0")
        }
    }

    // MARK: - Building blocks

    @ViewBuilder
    private func section<Content: View>(_ title: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title)
                .font(Theme.Typography.label)
                .tracking(1)
                .foregroundStyle(Theme.Colors.textTertiary)
                .padding(.horizontal, Theme.Spacing.sm)
            VStack(spacing: 0) {
                content()
            }
            .padding(Theme.Spacing.md)
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

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Colors.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 6)
    }

    private func infoRow(_ label: String, _ value: String, mono: Bool = false) -> some View {
        HStack {
            Text(label).font(Theme.Typography.body).foregroundStyle(Theme.Colors.textSecondary)
            Spacer()
            Text(value)
                .font(mono ? Theme.Typography.captionMono : Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textPrimary)
        }
        .padding(.vertical, 6)
    }

    private func actionRow(icon: String, label: String, tint: Color) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .heavy))
            Text(label)
                .font(Theme.Typography.body)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.Colors.textTertiary)
        }
        .padding(.vertical, 6)
        .foregroundStyle(tint)
    }

    @ViewBuilder
    private func pickerRow<T: Hashable>(label: String,
                                        tint: Color,
                                        selection: Binding<T>,
                                        options: [T],
                                        display: @escaping (T) -> String) -> some View {
        HStack {
            Text(label)
                .font(Theme.Typography.label)
                .tracking(1.5)
                .foregroundStyle(Theme.Colors.textTertiary)
            Spacer()
            Menu {
                Picker(selection: selection) {
                    ForEach(options, id: \.self) { opt in
                        Text(display(opt)).tag(opt)
                    }
                } label: { EmptyView() }
            } label: {
                HStack(spacing: 4) {
                    Text(display(selection.wrappedValue))
                        .font(Theme.Typography.body)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .heavy))
                }
                .foregroundStyle(tint)
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Actions

    private func clearAllInventory() {
        InventoryService.shared.clearAll()
    }
}
