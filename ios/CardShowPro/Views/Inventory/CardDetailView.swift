import SwiftUI

struct CardDetailView: View {
    let item: InventoryItem
    let vm: InventoryViewModel

    @State private var showSellSheet = false

    var body: some View {
        ZStack {
            Theme.Colors.bg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    // Hero image
                    if let url = item.card?.imageUrlSm.flatMap(URL.init) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let img): img.resizable().aspectRatio(contentMode: .fit)
                            default: Theme.Colors.surface
                            }
                        }
                        .frame(maxWidth: 220)
                        .frame(maxHeight: 308)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                        .shadow(color: .black.opacity(0.5), radius: 24, y: 12)
                        .padding(.top, Theme.Spacing.md)
                    }

                    // Name + set
                    VStack(spacing: Theme.Spacing.xs) {
                        Text(item.card?.name ?? item.cardId)
                            .font(Theme.Typography.headline)
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .multilineTextAlignment(.center)
                        if let set = item.card?.setName {
                            Text(set)
                                .font(Theme.Typography.body)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        StatusPill(status: item.status)
                            .padding(.top, 4)
                    }

                    // Price tiles
                    HStack(spacing: Theme.Spacing.sm) {
                        if let market = item.card?.marketPrice {
                            priceTile("MARKET", String(format: "$%.2f", market), tint: Theme.Colors.amber)
                        }
                        if let purchase = item.purchasePrice {
                            priceTile("PAID", String(format: "$%.2f", purchase), tint: Theme.Colors.blue)
                        }
                        if let sale = item.salePrice {
                            priceTile("SOLD", String(format: "$%.2f", sale), tint: Theme.Colors.green)
                        }
                    }

                    // Details
                    VStack(spacing: 0) {
                        detailRow("Condition", item.condition.replacingOccurrences(of: "_", with: " ").capitalized)
                        Divider().background(Theme.Colors.divider)
                        detailRow("Quantity", "\(item.quantity)")
                        if let loc = item.sourceLocation {
                            Divider().background(Theme.Colors.divider)
                            detailRow("Source", loc)
                        }
                        if let notes = item.notes {
                            Divider().background(Theme.Colors.divider)
                            detailRow("Notes", notes)
                        }
                    }
                    .surfaceCard()

                    // Sell button
                    if item.status == "bought" {
                        Button { showSellSheet = true } label: {
                            HStack {
                                Image(systemName: "dollarsign.circle.fill")
                                Text("MARK AS SOLD")
                                    .font(Theme.Typography.title)
                                    .tracking(1.5)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Theme.Colors.green)
                            .foregroundStyle(.black)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
                        }
                    }
                }
                .padding(Theme.Spacing.md)
            }
        }
        .navigationTitle(item.card?.name ?? "Card")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showSellSheet) {
            SellSheet(item: item) { price in
                Task {
                    await vm.markSold(item: item, price: price)
                    showSellSheet = false
                }
            }
        }
    }

    private func priceTile(_ label: String, _ value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(Theme.Typography.label)
                .tracking(1)
                .foregroundStyle(Theme.Colors.textTertiary)
            Text(value)
                .font(Theme.Typography.priceMd)
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCard()
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label.uppercased())
                .font(Theme.Typography.label)
                .tracking(1)
                .foregroundStyle(Theme.Colors.textTertiary)
            Spacer()
            Text(value)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textPrimary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 8)
    }
}
