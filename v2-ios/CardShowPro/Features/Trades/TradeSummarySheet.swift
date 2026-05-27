import SwiftUI

/// Shown after the vendor has scanned both sides of a trade. Lays out
/// the two cards (GIVE on the left, GET on the right), lets the vendor
/// declare which side, if any, added cash on top, and commits both
/// inventory rows as a single linked transaction.
struct TradeSummarySheet: View {
    let builder: TradeBuilder
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @State private var cashText: String = ""

    var body: some View {
        ZStack {
            Theme.Colors.bg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    header
                    cardsRow
                    cashSection
                    confirmButton
                    cancelButton
                }
                .padding(Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.lg)
            }
        }
        .onAppear {
            cashText = builder.cashAmount > 0
                ? String(format: "%.2f", builder.cashAmount)
                : ""
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.left.arrow.right.circle.fill")
                    .foregroundStyle(Theme.Colors.amber)
                Text("REVIEW TRADE")
                    .font(Theme.Typography.label)
                    .tracking(2)
                    .foregroundStyle(Theme.Colors.amber)
            }
            Text("Confirm the two cards + any cash on the side.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, Theme.Spacing.md)
    }

    // MARK: - Cards row

    private var cardsRow: some View {
        HStack(spacing: Theme.Spacing.md) {
            tradeCardView(label: "GIVE",
                          tint: Theme.Colors.red,
                          card: builder.giveCard)
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(Theme.Colors.amber)
            tradeCardView(label: "GET",
                          tint: Theme.Colors.green,
                          card: builder.getCard)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func tradeCardView(label: String, tint: Color, card: CardMatch?) -> some View {
        VStack(spacing: 6) {
            Text(label)
                .font(Theme.Typography.label)
                .tracking(2)
                .foregroundStyle(tint)
            cardImage(for: card)
                .frame(width: 110, height: 154)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md)
                        .stroke(tint.opacity(0.6), lineWidth: 2)
                )
                .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
            Text(card?.name ?? "—")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .tracking(0.5)
                .foregroundStyle(Theme.Colors.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func cardImage(for card: CardMatch?) -> some View {
        if let captured = card?.capturedImage {
            Image(uiImage: captured)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else if let urlStr = card?.imageUrlSm, let url = URL(string: urlStr) {
            CachedAsyncImage(url: url) { phase in
                switch phase {
                case .success(let img): img.resizable().aspectRatio(contentMode: .fill)
                default: Theme.Colors.surface
                }
            }
        } else {
            Theme.Colors.surface
        }
    }

    // MARK: - Cash section

    private var cashSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("CASH ON THE SIDE")
                .font(Theme.Typography.label)
                .tracking(1.5)
                .foregroundStyle(Theme.Colors.textTertiary)

            HStack(spacing: 6) {
                ForEach(TradeBuilder.CashSide.allCases) { side in
                    Button {
                        builder.cashSide = side
                        if side == .none {
                            cashText = ""
                            builder.cashAmount = 0
                        }
                    } label: {
                        cashChip(side: side, selected: builder.cashSide == side)
                    }
                    .buttonStyle(.plain)
                }
            }

            if builder.cashSide != .none {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("$")
                        .font(Theme.Typography.priceLg)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    TextField("0.00", text: $cashText)
                        .keyboardType(.decimalPad)
                        .font(Theme.Typography.priceLg)
                        .foregroundStyle(Theme.Colors.amber)
                        .onChange(of: cashText) { _, newValue in
                            builder.cashAmount = Double(newValue) ?? 0
                        }
                }
                .padding(Theme.Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.md)
                        .fill(Theme.Colors.surface)
                )
            }
        }
    }

    private func cashChip(side: TradeBuilder.CashSide, selected: Bool) -> some View {
        Text(side.title)
            .font(Theme.Typography.label)
            .tracking(1)
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .fill(selected ? Theme.Colors.amber : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                            .stroke(selected ? Theme.Colors.amber : Theme.Colors.border,
                                    style: StrokeStyle(lineWidth: 1.5,
                                                       dash: selected ? [] : [4, 3]))
                    )
            )
            .foregroundStyle(selected ? .black : Theme.Colors.textSecondary)
    }

    // MARK: - Buttons

    private var confirmButton: some View {
        Button(action: onConfirm) {
            Text("CONFIRM TRADE")
                .font(Theme.Typography.title)
                .tracking(2)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Theme.Colors.amber)
                .foregroundStyle(.black)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
        }
        .disabled(builder.giveCard == nil || builder.getCard == nil)
    }

    private var cancelButton: some View {
        Button(action: onCancel) {
            Text("Cancel — don't log this trade")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textTertiary)
        }
    }
}
