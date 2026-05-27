import SwiftUI

/// Garage-sale-sticker price tag. Yellow circular paper with a hand-drawn
/// dashed border, rotated slightly off-axis like it was slapped on.
/// Used to highlight key dollar amounts in the UI.
struct PriceTag: View {
    let amount: Double
    var caption: String? = nil
    var size: CGFloat = 78
    var rotation: Double = -8

    private var formatted: String {
        if amount >= 1000 {
            return String(format: "$%.0fK", amount / 1000)
        }
        return String(format: "$%.0f", amount)
    }

    var body: some View {
        ZStack {
            // Outer dashed ring — sticker paper edge
            Circle()
                .stroke(Color.black.opacity(0.85),
                        style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .padding(2)

            // Yellow body
            Circle()
                .fill(Theme.Colors.amber)
                .padding(5)

            VStack(spacing: 0) {
                if let caption {
                    Text(caption.uppercased())
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .tracking(1)
                        .foregroundStyle(.black.opacity(0.75))
                }
                Text(formatted)
                    .font(.system(size: size * 0.32, weight: .black, design: .monospaced))
                    .foregroundStyle(.black)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }
            .padding(.horizontal, 6)
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(rotation))
        .shadow(color: .black.opacity(0.4), radius: 4, x: 1, y: 3)
    }
}

/// Inline price chip — smaller, rectangular receipt-style. For dense rows.
struct PriceChip: View {
    let amount: Double
    var tint: Color = Theme.Colors.amber
    var label: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let label {
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(tint.opacity(0.7))
            }
            Text(String(format: "$%.2f", amount))
                .font(Theme.Typography.priceSm)
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(tint.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(tint.opacity(0.4), lineWidth: 1)
                )
        )
    }
}
