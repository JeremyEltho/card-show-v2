import SwiftUI

struct ScanResultSheet: View {
    let match: CardMatch
    let isAwaitingConfirmation: Bool
    let onConfirm: (Double?, String, String) -> Void
    let onReject: () -> Void

    @Environment(AppState.self) private var appState
    @State private var selectedCondition = CardCondition.near_mint
    @State private var selectedStatus = CardStatus.bought
    @State private var customPrice: String = ""

    private var displayPrice: String {
        if let p = match.marketPrice { return String(format: "$%.2f", p) }
        return "Price unavailable"
    }

    private var confidenceBadgeColor: Color {
        match.confidence >= 0.95 ? .green : match.confidence >= 0.80 ? .yellow : .orange
    }

    var body: some View {
        VStack(spacing: 0) {
            // Handle bar
            Capsule()
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 40, height: 4)
                .padding(.top, 12)

            ScrollView {
                VStack(spacing: 20) {
                    // Card image + info
                    HStack(spacing: 16) {
                        if let urlStr = match.imageUrlSm, let url = URL(string: urlStr) {
                            AsyncImage(url: url) { img in
                                img.resizable().aspectRatio(contentMode: .fit)
                            } placeholder: {
                                RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.2))
                            }
                            .frame(width: 80, height: 112)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        } else {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.secondary.opacity(0.15))
                                .frame(width: 80, height: 112)
                                .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text(match.name)
                                .font(.headline)
                                .lineLimit(2)
                            if let set = match.setName {
                                Text(set)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            if let num = match.number {
                                Text("#\(num)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(displayPrice)
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundStyle(.green)

                            // Confidence badge
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(confidenceBadgeColor)
                                    .frame(width: 8, height: 8)
                                Text("\(Int(match.confidence * 100))% match")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal)

                    Divider()

                    // Status + condition pickers
                    VStack(spacing: 14) {
                        Picker("Status", selection: $selectedStatus) {
                            ForEach(CardStatus.allCases, id: \.self) { s in
                                Text(s.displayName).tag(s)
                            }
                        }
                        .pickerStyle(.segmented)

                        Picker("Condition", selection: $selectedCondition) {
                            ForEach([CardCondition.mint, .near_mint, .lightly_played, .moderately_played], id: \.self) { c in
                                Text(c.displayName).tag(c)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)

                        HStack {
                            Text("Price paid ($)")
                            Spacer()
                            TextField("Market price", text: $customPrice)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 100)
                        }

                        if !appState.activeShowName.isEmpty {
                            HStack {
                                Image(systemName: "mappin.circle")
                                    .foregroundStyle(.secondary)
                                Text(appState.activeShowName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.horizontal)

                    // Action buttons
                    VStack(spacing: 10) {
                        Button(action: {
                            let price = Double(customPrice) ?? match.marketPrice
                            onConfirm(price, selectedCondition.rawValue, selectedStatus.rawValue)
                        }) {
                            Label("Log Card", systemImage: "plus.circle.fill")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(Color.accentColor)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                        if isAwaitingConfirmation {
                            Button("Not Right — Search Again", action: onReject)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 32)
                }
                .padding(.top, 16)
            }
        }
        .onAppear {
            // Pre-fill with market price
            if let price = match.marketPrice {
                customPrice = String(format: "%.2f", price)
            }
        }
    }
}
