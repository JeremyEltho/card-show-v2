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
                        Image(systemName: "person.crop.circle")
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

    // MARK: - Content

    private func content(_ summary: AnalyticsSummary) -> some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.md) {
                // Show name header
                if !appState.activeShowName.isEmpty {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Theme.Colors.green)
                            .frame(width: 6, height: 6)
                        Text("LIVE · \(appState.activeShowName.uppercased())")
                            .font(Theme.Typography.label)
                            .tracking(1)
                            .foregroundStyle(Theme.Colors.green)
                        Spacer()
                    }
                    .padding(.horizontal, Theme.Spacing.xs)
                }

                // Three big numbers — buys, sells, net
                HStack(spacing: Theme.Spacing.sm) {
                    StatTile(
                        label: "Buys today",
                        value: String(format: "$%.0f", summary.showSummary.spent),
                        accent: Theme.Colors.blue,
                        subtitle: "\(buyCount(summary)) cards in"
                    )
                    StatTile(
                        label: "Sells today",
                        value: String(format: "$%.0f", summary.showSummary.earned),
                        accent: Theme.Colors.green,
                        subtitle: "\(sellCount(summary)) cards out"
                    )
                }

                // Net P&L — big single number
                let net = summary.showSummary.net
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("NET TODAY")
                        .font(Theme.Typography.label)
                        .tracking(1)
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

                // All-time stats — tighter, secondary
                HStack(spacing: Theme.Spacing.sm) {
                    smallStat("All-time", String(format: "$%.0f", summary.netProfit),
                              tint: summary.netProfit >= 0 ? Theme.Colors.green : Theme.Colors.red)
                    smallStat("Sold", "\(summary.cardsSold)", tint: Theme.Colors.textSecondary)
                    smallStat("Stock", "\(summary.cardsHolding)", tint: Theme.Colors.textSecondary)
                }
            }
            .padding(Theme.Spacing.md)
        }
    }

    private func smallStat(_ label: String, _ value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(Theme.Typography.label)
                .tracking(0.5)
                .foregroundStyle(Theme.Colors.textTertiary)
            Text(value)
                .font(Theme.Typography.priceMd)
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCard()
    }

    private func netDisplay(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : "-"
        return "\(sign)$\(String(format: "%.2f", abs(value)))"
    }

    private func buyCount(_ summary: AnalyticsSummary) -> Int {
        // For now, use total today's cards minus sells
        max(summary.showSummary.cardsLogged - sellCount(summary), 0)
    }

    private func sellCount(_ summary: AnalyticsSummary) -> Int {
        // Heuristic: if earned > 0, there was at least one sell
        summary.showSummary.earned > 0 ? max(1, summary.showSummary.cardsLogged / 2) : 0
    }

    // MARK: - Empty state

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
