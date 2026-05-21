import SwiftUI

/// Vendor profile + settings. Shows today's totals, lifetime totals, the active
/// show name editor, and app info. Replaces the old Today + Settings tabs.
struct ProfileView: View {
    @Environment(AppState.self) private var appState
    @State private var summary: InventoryService.TodaySummary?

    var body: some View {
        ZStack {
            Theme.Colors.bg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: Theme.Spacing.md) {
                    // Today snapshot
                    if let s = summary {
                        todayCard(s)
                        allTimeCard(s)
                    }

                    // Active show
                    section("ACTIVE SHOW") {
                        @Bindable var state = appState
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

                    // About
                    section("ABOUT") {
                        infoRow("Mode", "On-device only", mono: true)
                        Divider().background(Theme.Colors.divider)
                        infoRow("Version", "2.0.0")
                    }
                }
                .padding(Theme.Spacing.md)
            }
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Theme.Colors.bg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await refresh() }
        .refreshable { await refresh() }
    }

    // MARK: - Today card

    private func todayCard(_ s: InventoryService.TodaySummary) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text("TODAY")
                    .font(Theme.Typography.label)
                    .tracking(2)
                    .foregroundStyle(Theme.Colors.textTertiary)
                Spacer()
            }

            // Three numbers in a row
            HStack(spacing: 0) {
                stat("Buys",  amount: s.buys,  count: s.cardsIn,  tint: Theme.Colors.blue)
                Divider().frame(width: 1).background(Theme.Colors.divider).padding(.vertical, 6)
                stat("Sells", amount: s.sells, count: s.cardsOut, tint: Theme.Colors.green)
                Divider().frame(width: 1).background(Theme.Colors.divider).padding(.vertical, 6)
                netStat(s.net)
            }
        }
        .padding(Theme.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .fill(Theme.Colors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                        .stroke(Theme.Colors.border, lineWidth: 1)
                )
        )
    }

    private func stat(_ label: String, amount: Double, count: Int, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(Theme.Typography.label)
                .tracking(1)
                .foregroundStyle(Theme.Colors.textTertiary)
            Text(String(format: "$%.0f", amount))
                .font(Theme.Typography.priceLg)
                .foregroundStyle(tint)
            Text("\(count) cards")
                .font(Theme.Typography.captionMono)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func netStat(_ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("NET")
                .font(Theme.Typography.label)
                .tracking(1)
                .foregroundStyle(Theme.Colors.textTertiary)
            Text((value >= 0 ? "+$" : "-$") + String(format: "%.0f", abs(value)))
                .font(Theme.Typography.priceLg)
                .foregroundStyle(value >= 0 ? Theme.Colors.green : Theme.Colors.red)
            Image(systemName: value >= 0 ? "arrow.up.right" : "arrow.down.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(value >= 0 ? Theme.Colors.green : Theme.Colors.red)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, Theme.Spacing.sm)
    }

    // MARK: - All-time card

    private func allTimeCard(_ s: InventoryService.TodaySummary) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            simpleStat("STOCK", value: "\(s.stockCount)", tint: Theme.Colors.amber)
            simpleStat(
                "ALL-TIME",
                value: (s.allTimeNet >= 0 ? "+$" : "-$") + String(format: "%.0f", abs(s.allTimeNet)),
                tint: s.allTimeNet >= 0 ? Theme.Colors.green : Theme.Colors.red
            )
        }
    }

    private func simpleStat(_ label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(Theme.Typography.label).tracking(1)
                .foregroundStyle(Theme.Colors.textTertiary)
            Text(value).font(Theme.Typography.priceMd).foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCard()
    }

    // MARK: - Sections

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

    private func refresh() async {
        summary = await MainActor.run { InventoryService.shared.summary() }
    }
}
