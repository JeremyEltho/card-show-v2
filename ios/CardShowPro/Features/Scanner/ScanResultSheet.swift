import SwiftUI

/// Shown when card scan confidence is 80-94% — vendor must confirm before logging.
/// The vendor's pre-selected LogMode (buy/sell/trade) is already known, so we lock
/// the action header instead of asking again.
struct ScanResultSheet: View {
    let match: CardMatch
    let logMode: LogMode
    let isAwaitingConfirmation: Bool
    /// Override the confirm-button label. Trade mode passes "NEXT" for the
    /// first scan and "REVIEW" for the second. Nil → use logMode.title.
    var confirmLabelOverride: String? = nil
    /// Trade mode hides the per-card price field because trades are
    /// transacted as a pair with optional cash adjustment, not per card.
    var hidesPriceField: Bool = false
    let onConfirm: (Double?, String, String) -> Void
    let onReject: () -> Void

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
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

                        // Card name only — we don't display the set because the
                        // PokemonTCG lookup just picks the first match for the
                        // name and the set is a guess (could be any printing).
                        Text(match.name)
                            .font(Theme.Typography.headline)
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .multilineTextAlignment(.center)

                        // Market price — only shown when we actually have one
                        // (fast mode skips the API lookup, so the field is nil).
                        if match.marketPrice != nil {
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
                    }

                    // Locked-mode header — vendor already picked Buy/Sell/Trade upstream
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: logMode.icon)
                            .font(.system(size: 18, weight: .bold))
                        Text("\(logMode.title) MODE")
                            .font(Theme.Typography.label)
                            .tracking(2)
                        Spacer()
                        Text(logMode.subtitle)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(.black.opacity(0.7))
                    }
                    .padding(Theme.Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.md)
                            .fill(logMode.tint)
                    )
                    .foregroundStyle(.black)

                    // Price input — hidden in trade mode (per-card price
                    // doesn't apply; cash adjustment happens once on the
                    // TradeSummarySheet).
                    if !hidesPriceField {
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            Text(priceLabel)
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
                                    .foregroundStyle(logMode.tint)
                            }
                            .padding(Theme.Spacing.md)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.Radius.md)
                                    .fill(Theme.Colors.surface)
                            )
                        }
                    }

                    // Confirm button — label overridable for the trade flow.
                    Button {
                        let price = hidesPriceField ? nil : (Double(customPrice) ?? match.marketPrice)
                        onConfirm(price, "near_mint", logMode.inventoryStatus)
                        dismiss()
                    } label: {
                        Text(confirmLabelOverride ?? "LOG \(logMode.title)")
                            .font(Theme.Typography.title)
                            .tracking(2)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(logMode.tint)
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
        // Prefer the live camera photo of the actual card the vendor is
        // holding — same image that will land on the receipt. Falls back to
        // pokemontcg.io stock art only when no capture is available (e.g.
        // manual-search flow).
        if let captured = match.capturedImage {
            Image(uiImage: captured)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        } else if let urlStr = match.imageUrlSm, let url = URL(string: urlStr) {
            CachedAsyncImage(url: url) { phase in
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

    private var priceLabel: String {
        switch logMode {
        case .buy:   return "PAID"
        case .sell:  return "SOLD FOR"
        case .trade: return "VALUE (FOR YOUR RECORDS)"
        }
    }
}
