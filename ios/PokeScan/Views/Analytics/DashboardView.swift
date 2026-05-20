import SwiftUI

struct DashboardView: View {
    @State private var vm = DashboardViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading && vm.summary == nil {
                    ProgressView("Loading...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let summary = vm.summary {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            // Show summary (today)
                            ShowSummaryCard(summary: summary.showSummary)

                            // Portfolio value + P&L
                            HStack(spacing: 12) {
                                MetricCard(
                                    title: "Portfolio",
                                    value: String(format: "$%.2f", summary.portfolioValue),
                                    subtitle: "\(summary.cardsHolding) cards holding",
                                    color: .blue
                                )
                                MetricCard(
                                    title: "Net Profit",
                                    value: String(format: "%+.2f", summary.netProfit),
                                    subtitle: "Realized",
                                    color: summary.netProfit >= 0 ? .green : .red
                                )
                            }

                            HStack(spacing: 12) {
                                MetricCard(
                                    title: "Invested",
                                    value: String(format: "$%.2f", summary.totalInvested),
                                    subtitle: "Total cost basis",
                                    color: .secondary
                                )
                                MetricCard(
                                    title: "Unrealized",
                                    value: String(format: "%+.2f", summary.unrealizedGain),
                                    subtitle: "On hand",
                                    color: summary.unrealizedGain >= 0 ? .green : .red
                                )
                            }

                            // Top gainer
                            if let top = summary.topGainer, let gainPct = top.gainPct {
                                VStack(alignment: .leading, spacing: 8) {
                                    Label("Top Gainer", systemImage: "arrow.up.right.circle")
                                        .font(.headline)
                                    HStack {
                                        Text(top.name ?? top.cardId)
                                        Spacer()
                                        Text(String(format: "+%.1f%%", gainPct))
                                            .fontWeight(.semibold)
                                            .foregroundStyle(.green)
                                    }
                                }
                                .padding()
                                .background(.regularMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }

                            // Stats row
                            HStack(spacing: 12) {
                                StatCard(title: "Total Cards", value: "\(summary.totalCards)")
                                StatCard(title: "Sold", value: "\(summary.cardsSold)")
                                StatCard(title: "Revenue", value: String(format: "$%.0f", summary.totalRevenue))
                            }
                        }
                        .padding()
                    }
                } else {
                    ContentUnavailableView("No Data", systemImage: "chart.bar",
                        description: Text("Start scanning cards to see analytics"))
                }
            }
            .navigationTitle("Analytics")
            .refreshable { await vm.load() }
        }
        .task { await vm.load() }
    }
}

struct ShowSummaryCard: View {
    let summary: ShowSummary
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Today's Show", systemImage: "star.fill")
                    .font(.headline)
                    .foregroundStyle(.yellow)
                Spacer()
                Text("\(summary.cardsLogged) cards")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 24) {
                VStack {
                    Text("Spent").font(.caption).foregroundStyle(.secondary)
                    Text(String(format: "$%.2f", summary.spent)).fontWeight(.bold).foregroundStyle(.red)
                }
                VStack {
                    Text("Earned").font(.caption).foregroundStyle(.secondary)
                    Text(String(format: "$%.2f", summary.earned)).fontWeight(.bold).foregroundStyle(.green)
                }
                VStack {
                    Text("Net").font(.caption).foregroundStyle(.secondary)
                    Text(String(format: "%+.2f", summary.net))
                        .fontWeight(.bold)
                        .foregroundStyle(summary.net >= 0 ? .green : .red)
                }
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct MetricCard: View {
    let title: String; let value: String; let subtitle: String; let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3).fontWeight(.bold).foregroundStyle(color).minimumScaleFactor(0.6).lineLimit(1)
            Text(subtitle).font(.caption2).foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct StatCard: View {
    let title: String; let value: String
    var body: some View {
        VStack(spacing: 4) {
            Text(value).font(.headline).fontWeight(.bold)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
