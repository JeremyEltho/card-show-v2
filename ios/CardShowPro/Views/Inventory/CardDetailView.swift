import SwiftUI

struct CardDetailView: View {
    let item: InventoryItem
    let vm: InventoryViewModel

    @State private var showSellSheet = false
    @State private var salePrice = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Card image
                if let url = item.card?.imageUrlSm.flatMap(URL.init) {
                    AsyncImage(url: url) { img in img.resizable().aspectRatio(contentMode: .fit) }
                        placeholder: { Color.secondary.opacity(0.1) }
                        .frame(maxWidth: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(radius: 8)
                }

                // Card name + set
                VStack(spacing: 4) {
                    Text(item.card?.name ?? item.cardId)
                        .font(.title2.bold())
                    if let set = item.card?.setName {
                        Text(set).font(.subheadline).foregroundStyle(.secondary)
                    }
                }

                // Price + gain row
                HStack(spacing: 32) {
                    VStack {
                        Text("Market").font(.caption).foregroundStyle(.secondary)
                        Text(item.card?.marketPrice.map { String(format: "$%.2f", $0) } ?? "—")
                            .font(.headline)
                    }
                    if let purchase = item.purchasePrice {
                        VStack {
                            Text("Paid").font(.caption).foregroundStyle(.secondary)
                            Text(String(format: "$%.2f", purchase)).font(.headline)
                        }
                    }
                    if let gain = item.unrealizedGain {
                        VStack {
                            Text("Gain").font(.caption).foregroundStyle(.secondary)
                            Text(String(format: "%+.2f", gain))
                                .font(.headline)
                                .foregroundStyle(gain >= 0 ? .green : .red)
                        }
                    }
                }

                Divider()

                // Details grid
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    GridRow {
                        Text("Status").foregroundStyle(.secondary)
                        StatusBadge(status: item.status)
                    }
                    GridRow {
                        Text("Condition").foregroundStyle(.secondary)
                        Text(item.condition.replacingOccurrences(of: "_", with: " ").capitalized)
                    }
                    GridRow {
                        Text("Quantity").foregroundStyle(.secondary)
                        Text("\(item.quantity)")
                    }
                    if let loc = item.sourceLocation {
                        GridRow {
                            Text("Source").foregroundStyle(.secondary)
                            Text(loc)
                        }
                    }
                    if let notes = item.notes {
                        GridRow {
                            Text("Notes").foregroundStyle(.secondary)
                            Text(notes).lineLimit(3)
                        }
                    }
                }
                .font(.subheadline)
                .padding(.horizontal)

                // Sell button
                if item.status != "sold" {
                    Button(action: { showSellSheet = true }) {
                        Label("Mark as Sold", systemImage: "dollarsign.circle")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.green)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.top)
        }
        .navigationTitle(item.card?.name ?? "Card")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showSellSheet) {
            NavigationStack {
                Form {
                    Section("Sale Price") {
                        TextField("Amount ($)", text: $salePrice)
                            .keyboardType(.decimalPad)
                    }
                    Section {
                        Button("Confirm Sale") {
                            if let price = Double(salePrice) {
                                Task { await vm.markSold(item: item, price: price) }
                            }
                            showSellSheet = false
                        }
                        .foregroundStyle(.green)
                    }
                }
                .navigationTitle("Mark as Sold")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showSellSheet = false }
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .onAppear {
            if let price = item.card?.marketPrice {
                salePrice = String(format: "%.2f", price)
            }
        }
    }
}
