import SwiftUI

struct InventoryListView: View {
    @State private var vm = InventoryViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading && vm.items.isEmpty {
                    ProgressView("Loading inventory...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if vm.filteredItems.isEmpty && !vm.isLoading {
                    ContentUnavailableView(
                        "No Cards",
                        systemImage: "tray",
                        description: Text("Scanned cards will appear here")
                    )
                } else {
                    List {
                        ForEach(vm.filteredItems) { item in
                            NavigationLink(destination: CardDetailView(item: item, vm: vm)) {
                                InventoryRowView(item: item)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button("Delete", role: .destructive) {
                                    Task { await vm.delete(item: item) }
                                }
                            }
                        }
                        if vm.hasMore {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .task { await vm.loadNextPage() }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Inventory (\(vm.totalCount))")
            .searchable(text: $vm.searchText, prompt: "Search cards")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("All") { vm.statusFilter = nil; Task { await vm.load() } }
                        Button("Holding") { vm.statusFilter = "holding"; Task { await vm.load() } }
                        Button("Bought") { vm.statusFilter = "bought"; Task { await vm.load() } }
                        Button("Sold") { vm.statusFilter = "sold"; Task { await vm.load() } }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .refreshable { await vm.load() }
        }
        .task { await vm.load() }
    }
}

struct InventoryRowView: View {
    let item: InventoryItem

    var body: some View {
        HStack(spacing: 12) {
            if let url = item.card?.imageUrlSm.flatMap(URL.init) {
                AsyncImage(url: url) { img in img.resizable().aspectRatio(contentMode: .fit) }
                    placeholder: { RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.2)) }
                    .frame(width: 44, height: 62)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: 44, height: 62)
                    .overlay(Image(systemName: "photo").foregroundStyle(.secondary).font(.caption))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.card?.name ?? item.cardId)
                    .font(.headline)
                    .lineLimit(1)
                Text(item.card?.setName ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    StatusBadge(status: item.status)
                    if let price = item.purchasePrice {
                        Text(String(format: "$%.2f", price))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                if let gain = item.unrealizedGain {
                    Text(String(format: "%+.2f", gain))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(gain >= 0 ? .green : .red)
                }
                if let market = item.card?.marketPrice {
                    Text(String(format: "$%.0f", market))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct StatusBadge: View {
    let status: String
    private var color: Color {
        switch status {
        case "bought", "holding": return .blue
        case "sold": return .red
        case "traded": return .orange
        case "wishlist": return .purple
        default: return .secondary
        }
    }
    var body: some View {
        Text(status.capitalized)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}
