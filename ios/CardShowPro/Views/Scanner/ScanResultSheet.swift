import SwiftUI

/// Shown when card scan confidence is 80-94% — vendor must confirm before logging.
struct ScanResultSheet: View {
    let match: CardMatch
    let isAwaitingConfirmation: Bool
    let onConfirm: (Double?, String, String) -> Void
    let onReject: () -> Void

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var selectedStatus = CardStatus.bought
    @State private var customPrice: String = ""

    private var displayPrice: String {
        if let p = match.marketPrice { return String(format: "$%.2f", p) }
        return "—"
    }

    private var confidencePct: Int { Int(match.confidence * 100) }
    private var confidenceTint: Color {
        match.confidence >= 0.95 ? Theme.Colors.green
            : match.confidence >= 0.80 ? Theme.Colors.amber
            : Theme.Colors.red
    }

    var body: some View {
        ZStack {
            Theme.Colors.bg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    // Confidence header
                    HStack(spacing: 6) {
                        Circle()
                            .fill(confidenceTint)
                            .frame(width: 8, height: 8)
                        Text("\(confidencePct)% MATCH")
                            .font(Theme.Typography.label)
                            .tracking(1)
                            .foregroundStyle(confidenceTint)
                    }
                    .padding(.top, Theme.Spacing.md)

                    // Card image + info
                    VStack(spacing: Theme.Spacing.md) {
                        cardImage
                            .frame(width: 140, height: 196)
                            .shadow(color: .black.opacity(0.4), radius: 16, y: 8)

                        VStack(spacing: 4) {
                            Text(match.name)
                                .font(Theme.Typography.headline)
                                .foregroundStyle(Theme.Colors.textPrimary)
                                .multilineTextAlignment(.center)
                            if let set = match.setName {
                                Text(set)
                                    .font(Theme.Typography.caption)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }
                        }

                        // Market price — big amber number
                        VStack(spacing: 2) {
                            Text("MARKET PRICE")
                                .font(Theme.Typography.label)
                                .tracking(1)
                                .foregroundStyle(Theme.Colors.textTertiary)
                            Text(displayPrice)
                                .font(Theme.Typography.priceLg)
                                .foregroundStyle(Theme.Colors.amber)
                        }
                    }

                    // Buy / Sell toggle — segmented control
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("ACTION")
                            .font(Theme.Typography.label)
                            .tracking(1)
                            .foregroundStyle(Theme.Colors.textTertiary)

                        HStack(spacing: 0) {
                            actionButton("BUY", status: .bought, tint: Theme.Colors.blue)
                            actionButton("SELL", status: .sold, tint: Theme.Colors.green)
                        }
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Radius.md)
                                .fill(Theme.Colors.surface)
                        )
                    }

                    // Price input
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text(selectedStatus == .bought ? "PAID" : "SOLD FOR")
                            .font(Theme.Typography.label)
                            .tracking(1)
                            .foregroundStyle(Theme.Colors.textTertiary)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("$")
                                .font(Theme.Typography.priceLg)
                                .foregroundStyle(Theme.Colors.textSecondary)
                            TextField("0.00", text: $customPrice)
                                .keyboardType(.decimalPad)
                                .font(Theme.Typography.priceLg)
                                .foregroundStyle(selectedStatus == .bought ? Theme.Colors.blue : Theme.Colors.green)
                        }
                        .padding(Theme.Spacing.md)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Radius.md)
                                .fill(Theme.Colors.surface)
                        )
                    }

                    // Log button — primary action
                    Button {
                        let price = Double(customPrice) ?? match.marketPrice
                        onConfirm(price, "near_mint", selectedStatus.rawValue)
                        dismiss()
                    } label: {
                        Text("LOG \(selectedStatus == .bought ? "BUY" : "SELL")")
                            .font(Theme.Typography.title)
                            .tracking(2)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Theme.Colors.amber)
                            .foregroundStyle(.black)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
                    }

                    if isAwaitingConfirmation {
                        Button {
                            onReject()
                            dismiss()
                        } label: {
                            Text("Not this card — search manually")
                                .font(Theme.Typography.body)
                                .foregroundStyle(Theme.Colors.textTertiary)
                        }
                    }
                }
                .padding(Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.lg)
            }
        }
        .onAppear {
            if let price = match.marketPrice {
                customPrice = String(format: "%.2f", price)
            }
        }
    }

    @ViewBuilder
    private var cardImage: some View {
        if let urlStr = match.imageUrlSm, let url = URL(string: urlStr) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img): img.resizable().aspectRatio(contentMode: .fit)
                default: Theme.Colors.surface
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        } else {
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .fill(Theme.Colors.surface)
                .overlay(
                    Image(systemName: "rectangle.portrait")
                        .font(.system(size: 32))
                        .foregroundStyle(Theme.Colors.textTertiary)
                )
        }
    }

    private func actionButton(_ label: String, status: CardStatus, tint: Color) -> some View {
        Button {
            selectedStatus = status
        } label: {
            Text(label)
                .font(Theme.Typography.label)
                .tracking(2)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(selectedStatus == status ? tint.opacity(0.2) : Color.clear)
                .foregroundStyle(selectedStatus == status ? tint : Theme.Colors.textTertiary)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md)
                        .stroke(selectedStatus == status ? tint : Color.clear, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
        .padding(2)
    }
}
