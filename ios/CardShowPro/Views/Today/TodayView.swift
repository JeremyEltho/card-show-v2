import SwiftUI

struct TodayView: View {
    @State private var vm = DashboardViewModel()
    @State private var showSettings = false
    @Environment(AppState.self) private var appState

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.bg.ignoresSafeArea()

                if vm.isLoading && vm.summary == nil {
                    ProgressView()
                        .tint(Theme.Colors.amber)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let summary = vm.summary {
                    content(summary)
                } else {
                    emptyState
                }
            }
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape.fill")
                            .foregroundStyle(Theme.Colors.amber)
                    }
                }
            }
            .refreshable { await vm.load() }
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .presentationDetents([.large])
            }
        }
        .task { await vm.load() }
    }

    private func content(_ summary: InventoryService.TodaySummary) -> some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.md) {
                if !appState.activeShowName.isEmpty {
                    HStack(spacing: 6) {
                        Circle().fill(Theme.Colors.green).frame(width: 6, height: 6)
                        Text("LIVE · \(appState.activeShowName.uppercased())")
                            .font(Theme.Typography.label).tracking(1)
                            .foregroundStyle(Theme.Colors.green)
                        Spacer()
                    }
                    .padding(.horizontal, Theme.Spacing.xs)
                }

                HStack(spacing: Theme.Spacing.sm) {
                    StatTile(
                        label: "Buys today",
                        value: String(format: "$%.0f", summary.buys),
                        accent: Theme.Colors.blue,
                        subtitle: "\(summary.cardsIn) cards in"
                    )
                    StatTile(
                        label: "Sells today",
                        value: String(format: "$%.0f", summary.sells),
                        accent: Theme.Colors.green,
                        subtitle: "\(summary.cardsOut) cards out"
                    )
                }

                let net = summary.net
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("NET TODAY")
                        .font(Theme.Typography.label).tracking(1)
                        .foregroundStyle(Theme.Colors.textTertiary)
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                        Text(netDisplay(net))
                            .font(Theme.Typography.displayLarge)
                            .foregroundStyle(net >= 0 ? Theme.Colors.green : Theme.Colors.red)
                            .contentTransition(.numericText(value: net))
                        if abs(net) > 0 {
                            Image(systemName: net >= 0 ? "arrow.up.right" : "arrow.down.right")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(net >= 0 ? Theme.Colors.green : Theme.Colors.red)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .surfaceCard(padding: Theme.Spacing.lg)

                HStack(spacing: Theme.Spacing.sm) {
                    smallStat("All-time", String(format: "$%.0f", summary.allTimeNet),
                              tint: summary.allTimeNet >= 0 ? Theme.Colors.green : Theme.Colors.red)
                    smallStat("Stock", "\(summary.stockCount)", tint: Theme.Colors.amber)
                }
            }
            .padding(Theme.Spacing.md)
        }
    }

    private func smallStat(_ label: String, _ value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(Theme.Typography.label).tracking(0.5)
                .foregroundStyle(Theme.Colors.textTertiary)
            Text(value).font(Theme.Typography.priceMd).foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCard()
    }

    private func netDisplay(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : "-"
        return "\(sign)$\(String(format: "%.2f", abs(value)))"
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "chart.bar")
                .font(.system(size: 48, weight: .thin))
                .foregroundStyle(Theme.Colors.textTertiary)
            Text("Nothing logged yet today")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text("Scan cards to start tracking your show")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
