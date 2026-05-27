import SwiftUI

/// Full activity feed — every buy, sell, and trade. Replaces the old Stock tab.
/// Includes inline filter pills so the vendor can narrow down what they're looking at.
struct TransactionsView: View {
    /// Optional search text supplied by the caller (e.g. HomeView's search
    /// bar). Applied once on appear.
    var initialSearch: String = ""

    @State private var vm = InventoryViewModel()
    @State private var sellingItem: LocalInventoryItem? = nil

    var body: some View {
        ZStack {
            Theme.Colors.bg.ignoresSafeArea()

            if vm.isLoading && vm.items.isEmpty {
                ProgressView()
                    .tint(Theme.Colors.amber)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                content
            }
        }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Theme.Colors.bg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .searchable(text: $vm.searchText, prompt: "Search by card name")
        .refreshable { await vm.load() }
        .sheet(item: $sellingItem) { item in
            SellSheet(item: item) { price in
                Task {
                    await vm.markSold(item: item, price: price)
                    sellingItem = nil
                }
            }
        }
        .task {
            // Default to "all" rather than just bought
            if vm.statusFilter == "bought" { vm.statusFilter = nil }
            // Apply caller-supplied search (e.g. HomeView's search bar).
            if !initialSearch.isEmpty && vm.searchText.isEmpty {
                vm.searchText = initialSearch
            }
            await vm.load()
        }
    }

    // MARK: - Content

    private var content: some View {
        ScrollView {
            LazyVStack(spacing: Theme.Spacing.sm) {
                filterPills
                if vm.filteredItems.isEmpty {
                    emptyState
                } else {
                    ForEach(vm.filteredItems) { item in
                        NavigationLink(destination: CardDetailView(item: item, vm: vm)) {
                            StockRow(item: item, onSell: { sellingItem = item })
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("Delete", role: .destructive) {
                                Task { await vm.delete(item: item) }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
        }
    }

    private var filterPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                filterPill("All", value: nil)
                filterPill("In stock", value: "bought", tint: Theme.Colors.blue)
                filterPill("Sold", value: "sold", tint: Theme.Colors.green)
                filterPill("Traded", value: "traded", tint: Theme.Colors.amber)
            }
            .padding(.vertical, 6)
        }
    }

    private func filterPill(_ label: String, value: String?, tint: Color = Theme.Colors.amber) -> some View {
        let isActive = vm.statusFilter == value
        return Button {
            vm.statusFilter = value
            Task { await vm.load() }
        } label: {
            Text(label.uppercased())
                .font(Theme.Typography.label)
                .tracking(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(isActive ? tint.opacity(0.2) : Theme.Colors.surface))
                .overlay(
                    Capsule().stroke(isActive ? tint : Theme.Colors.border, lineWidth: 1)
                )
                .foregroundStyle(isActive ? tint : Theme.Colors.textSecondary)
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "tray")
                .font(.system(size: 48, weight: .thin))
                .foregroundStyle(Theme.Colors.textTertiary)
            Text("No activity yet")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text("Go back and tap LOG to start scanning")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 80)
        .frame(maxWidth: .infinity)
    }
}
