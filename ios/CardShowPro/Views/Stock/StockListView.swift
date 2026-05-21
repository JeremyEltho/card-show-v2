import SwiftUI

struct StockListView: View {
    @State private var vm = InventoryViewModel()
    @State private var sellingItem: LocalInventoryItem? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.bg.ignoresSafeArea()

                if vm.isLoading && vm.items.isEmpty {
                    ProgressView()
                        .tint(Theme.Colors.amber)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if vm.filteredItems.isEmpty {
                    emptyState
                } else {
                    stockList
                }
            }
            .navigationTitle("Stock")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("In Stock") { vm.statusFilter = "bought"; Task { await vm.load() } }
                        Button("Sold") { vm.statusFilter = "sold"; Task { await vm.load() } }
                        Button("All") { vm.statusFilter = nil; Task { await vm.load() } }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .foregroundStyle(Theme.Colors.amber)
                    }
                }
            }
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
        }
        .task { await vm.load() }
    }

    private var stockList: some View {
        ScrollView {
            LazyVStack(spacing: Theme.Spacing.sm) {
                HStack {
                    Text("\(vm.filteredItems.count) cards")
                        .font(Theme.Typography.captionMono)
                        .foregroundStyle(Theme.Colors.textTertiary)
                    Spacer()
                    Text(stockValueLabel)
                        .font(Theme.Typography.priceSm)
                        .foregroundStyle(Theme.Colors.amber)
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, Theme.Spacing.sm)

                ForEach(vm.filteredItems) { item in
                    NavigationLink {
                        CardDetailView(item: item, vm: vm)
                    } label: {
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
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.bottom, Theme.Spacing.lg)
        }
    }

    private var stockValueLabel: String {
        let total = vm.filteredItems
            .compactMap { extractMarketPrice(from: $0) ?? $0.purchasePrice }
            .reduce(0, +)
        return String(format: "$%.2f total", total)
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "tray")
                .font(.system(size: 48, weight: .thin))
                .foregroundStyle(Theme.Colors.textTertiary)
            Text("Nothing in stock")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text("Scan a card to log it")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Stock row

struct StockRow: View {
    let item: LocalInventoryItem
    let onSell: () -> Void

    private var marketPrice: Double? { extractMarketPrice(from: item) }
    private var setName: String? { extractSetName(from: item) }

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            cardImage

            VStack(alignment: .leading, spacing: 4) {
                Text(item.cardName ?? item.cardId)
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                if let set = setName {
                    Text(set)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    StatusPill(status: item.status)
                    if let purchase = item.purchasePrice {
                        Text(String(format: "paid $%.2f", purchase))
                            .font(Theme.Typography.captionMono)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                if let market = marketPrice {
                    Text(String(format: "$%.0f", market))
                        .font(Theme.Typography.priceLg)
                        .foregroundStyle(Theme.Colors.amber)
                }
                if item.status == "bought" {
                    Button(action: onSell) {
                        Text("SELL")
                            .font(Theme.Typography.label)
                            .tracking(1)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Theme.Colors.greenSoft))
                            .foregroundStyle(Theme.Colors.green)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(Theme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .fill(Theme.Colors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .stroke(Theme.Colors.border, lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private var cardImage: some View {
        if let url = item.cardImageUrl.flatMap(URL.init) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img): img.resizable().aspectRatio(contentMode: .fill)
                default: Theme.Colors.surfaceHi
                }
            }
            .frame(width: 48, height: 66)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        } else {
            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                .fill(Theme.Colors.surfaceHi)
                .frame(width: 48, height: 66)
                .overlay(
                    Image(systemName: "rectangle.portrait")
                        .font(.system(size: 18))
                        .foregroundStyle(Theme.Colors.textTertiary)
                )
        }
    }
}

// MARK: - Helpers to read embedded notes metadata

func extractMarketPrice(from item: LocalInventoryItem) -> Double? {
    guard let notes = item.notes else { return nil }
    for token in notes.split(separator: ";") {
        let parts = token.split(separator: "=", maxSplits: 1)
        if parts.count == 2, parts[0] == "market" {
            return Double(parts[1])
        }
    }
    return nil
}

func extractSetName(from item: LocalInventoryItem) -> String? {
    guard let notes = item.notes else { return nil }
    for token in notes.split(separator: ";") {
        let parts = token.split(separator: "=", maxSplits: 1)
        if parts.count == 2, parts[0] == "set" {
            return String(parts[1])
        }
    }
    return nil
}

// MARK: - Sell sheet

struct SellSheet: View {
    let item: LocalInventoryItem
    let onConfirm: (Double) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var price: String = ""
    @FocusState private var priceFocused: Bool

    private var canConfirm: Bool { Double(price) ?? 0 > 0 }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.bg.ignoresSafeArea()

                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text((item.cardName ?? item.cardId).uppercased())
                            .font(Theme.Typography.label)
                            .foregroundStyle(Theme.Colors.textTertiary)
                        if let set = extractSetName(from: item) {
                            Text(set)
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.textTertiary)
                        }
                    }
                    .padding(.top, Theme.Spacing.lg)

                    HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                        Text("$")
                            .font(Theme.Typography.displayLarge)
                            .foregroundStyle(Theme.Colors.textSecondary)
                        TextField("0.00", text: $price)
                            .keyboardType(.decimalPad)
                            .font(Theme.Typography.displayLarge)
                            .foregroundStyle(Theme.Colors.green)
                            .focused($priceFocused)
                    }
                    .padding(.vertical, Theme.Spacing.md)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.lg)
                            .fill(Theme.Colors.surface)
                    )

                    if let market = extractMarketPrice(from: item), let paid = item.purchasePrice {
                        HStack {
                            Label(String(format: "market $%.2f", market), systemImage: "chart.line.uptrend.xyaxis")
                                .font(Theme.Typography.priceSm)
                                .foregroundStyle(Theme.Colors.amber)
                            Spacer()
                            Label(String(format: "paid $%.2f", paid), systemImage: "arrow.down")
                                .font(Theme.Typography.priceSm)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                    }

                    Spacer()

                    Button {
                        if let p = Double(price) { onConfirm(p) }
                    } label: {
                        Text("MARK SOLD")
                            .font(Theme.Typography.title)
                            .tracking(1)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(canConfirm ? Theme.Colors.green : Theme.Colors.surfaceHi)
                            .foregroundStyle(canConfirm ? .black : Theme.Colors.textDisabled)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
                    }
                    .disabled(!canConfirm)
                }
                .padding(Theme.Spacing.lg)
            }
            .navigationTitle("Sell Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
        }
        .onAppear {
            if let market = extractMarketPrice(from: item) {
                price = String(format: "%.2f", market)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                priceFocused = true
            }
        }
    }
}
