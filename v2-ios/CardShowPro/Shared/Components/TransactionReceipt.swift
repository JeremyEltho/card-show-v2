import SwiftUI
import UIKit

/// Printable transaction receipt. Designed to be rendered to a UIImage by
/// ImageRenderer and saved to the photo library. The whole view sits on a
/// parchment paper background with perforated top/bottom edges and uses the
/// same vendor-booth typographic mix as the rest of the app.
///
/// Fixed width of 360pt — rasterising at 3x produces a 1080-wide image that
/// reads well shared in iMessage or printed at 4×6.
///
/// The card image must be supplied pre-loaded (`cardImage`) because
/// ImageRenderer takes a synchronous snapshot — AsyncImage hasn't resolved
/// by the time the bitmap is grabbed. `ReceiptExporter` handles the prefetch.
struct TransactionReceipt: View {
    let item: LocalInventoryItem
    var cardImage: UIImage? = nil
    var includeImage: Bool = true

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM/dd/yyyy · hh:mma"
        return f
    }()

    private var displayPrice: Double? {
        item.status == "sold" ? (item.salePrice ?? item.purchasePrice) : item.purchasePrice
    }

    private var actionLabel: String {
        switch item.status {
        case "sold":   return "SELL"
        case "traded": return "TRADE"
        default:       return "BUY"
        }
    }

    private var actionTint: Color {
        switch item.status {
        case "sold":   return Theme.Colors.green
        case "traded": return Theme.Colors.amber
        default:       return Theme.Colors.blue
        }
    }

    private var serial: String {
        // CSP-2026-XXXX — first 8 chars of clientId, uppercased
        let suffix = String(item.clientId.replacingOccurrences(of: "-", with: "").prefix(8)).uppercased()
        let year = Calendar.current.component(.year, from: item.acquiredAt)
        return "CSP-\(year)-\(suffix)"
    }

    var body: some View {
        VStack(spacing: 0) {
            perforation(.top)

            VStack(spacing: 14) {
                header
                divider
                cardSection
                divider
                fieldsSection
                if let notes = item.notes, !notes.isEmpty {
                    divider
                    notesSection(notes)
                }
                divider
                priceFooter
                footerMeta
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 22)
            .background(Theme.Colors.parchment)

            perforation(.bottom)
        }
        .frame(width: 360)
        .background(Theme.Colors.parchment)
        .foregroundStyle(Color.black)
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                // Tiny rotated foil-card mark — same vibe as the home logo
                ZStack {
                    Circle().fill(Color.black).frame(width: 22, height: 22)
                    Image(systemName: "rectangle.dashed.badge.record")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(Theme.Colors.amber)
                }
                .rotationEffect(.degrees(-4))

                Text("CARDSHOW PRO")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .tracking(3)
                Spacer()
            }

            HStack {
                Text(actionLabel)
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .tracking(2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(actionTint)
                    .foregroundStyle(.black)
                Text("· RECEIPT ·")
                    .font(.system(size: 10, weight: .heavy, design: .serif))
                    .italic()
                    .tracking(1.5)
                    .foregroundStyle(.black.opacity(0.6))
                Spacer()
                Text(Self.dateFormatter.string(from: item.acquiredAt))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.black.opacity(0.7))
            }
        }
    }

    @ViewBuilder
    private var cardSection: some View {
        if includeImage {
            HStack(alignment: .top, spacing: 14) {
                cardImageView
                    .frame(width: 90, height: 126)
                    .background(Color.black.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.black.opacity(0.4), lineWidth: 0.5)
                    )
                cardMeta
            }
        } else {
            // No-image layout — meta takes the full width, plus a small label
            // up top so the receipt still reads as "card receipt" without
            // the visual.
            VStack(alignment: .leading, spacing: 6) {
                Text("CARD")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(.black.opacity(0.5))
                cardMeta
            }
        }
    }

    private var cardMeta: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Card name only — set name isn't shown because the scanner only
            // identifies the name, not the specific printing.
            Text(item.cardName ?? "Unknown card")
                .font(.system(size: 18, weight: .black, design: .rounded))
                .lineLimit(3)
            Spacer(minLength: 0)
            Text(serial)
                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                .tracking(1)
                .foregroundStyle(.black.opacity(0.55))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var fieldsSection: some View {
        VStack(spacing: 5) {
            statusRow
            if let p = item.purchasePrice {
                fieldRow("PAID", value: String(format: "$%.2f", p), mono: true)
            }
            if let s = item.salePrice {
                fieldRow("SOLD FOR", value: String(format: "$%.2f", s), mono: true)
            }
            if let m = item.marketPrice {
                fieldRow("MARKET", value: String(format: "$%.2f", m), mono: true,
                         tint: .black.opacity(0.5))
            }
            fieldRow("CONDITION", value: prettifyCondition(item.condition))
            if let src = item.sourceLocation, !src.isEmpty {
                fieldRow("SOURCE", value: src)
            }
            if let cp = item.counterparty, !cp.isEmpty {
                fieldRow("PARTY", value: cp)
            }
            if let pay = item.paymentMethod, !pay.isEmpty {
                fieldRow("PAYMENT", value: pay)
            }
        }
    }

    private var statusRow: some View {
        HStack {
            Text("STATUS")
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .tracking(1.5)
                .foregroundStyle(.black.opacity(0.55))
            Spacer()
            // Hero-sized rubber stamp — same dashed-border vibe as StatusPill
            Text(stampLabel)
                .font(.system(size: 14, weight: .heavy, design: .serif))
                .italic()
                .tracking(1.5)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(actionTint, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                )
                .foregroundStyle(actionTint)
                .rotationEffect(.degrees(-2))
        }
    }

    private var stampLabel: String {
        switch item.status {
        case "sold":    return "SOLD"
        case "traded":  return "TRADED"
        case "holding": return "IN STOCK"
        default:        return "BOUGHT"
        }
    }

    private func notesSection(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("NOTES")
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .tracking(1.5)
                .foregroundStyle(.black.opacity(0.55))
            Text("\u{201C}\(notes)\u{201D}")
                .font(.system(size: 12, weight: .regular, design: .serif))
                .italic()
                .foregroundStyle(.black.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var priceFooter: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("TOTAL")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(.black.opacity(0.55))
                Text(displayPrice.map { String(format: "$%.2f", $0) } ?? "—")
                    .font(.system(size: 28, weight: .black, design: .monospaced))
                    .foregroundStyle(.black)
            }
            Spacer()
            if let price = displayPrice, price > 0 {
                PriceTag(amount: price,
                         caption: actionLabel,
                         size: 76,
                         rotation: -8)
            }
        }
    }

    private var footerMeta: some View {
        VStack(spacing: 2) {
            let vendor = AppSettings.shared.vendorName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !vendor.isEmpty {
                Text(vendor.uppercased())
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(.black.opacity(0.75))
            }
            Text("Thank you for using CardShow Pro")
                .font(.system(size: 10, weight: .semibold, design: .serif))
                .italic()
                .foregroundStyle(.black.opacity(0.55))
            Text(serial)
                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                .tracking(2)
                .foregroundStyle(.black.opacity(0.45))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
    }

    // MARK: - Building blocks

    private func fieldRow(_ label: String, value: String,
                          mono: Bool = false, tint: Color = .black) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .tracking(1.5)
                .foregroundStyle(.black.opacity(0.55))
            Spacer()
            Text(value)
                .font(mono
                      ? .system(size: 13, weight: .bold, design: .monospaced)
                      : .system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.black.opacity(0.35))
            .frame(height: 1)
            .overlay(
                // Dashed look via an overlay — works correctly in ImageRenderer
                GeometryReader { geo in
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: 0.5))
                        path.addLine(to: CGPoint(x: geo.size.width, y: 0.5))
                    }
                    .stroke(Theme.Colors.parchment,
                            style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
            )
    }

    @ViewBuilder
    private var cardImageView: some View {
        if let cardImage {
            Image(uiImage: cardImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else if let urlStr = item.cardImageUrl, let url = URL(string: urlStr) {
            // Fallback for in-app preview only — never reached during a real
            // receipt save because ReceiptExporter pre-fetches the image.
            CachedAsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().aspectRatio(contentMode: .fill)
                default:
                    placeholderImage
                }
            }
        } else {
            placeholderImage
        }
    }

    private var placeholderImage: some View {
        ZStack {
            Color.black.opacity(0.06)
            Image(systemName: "rectangle.portrait")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.black.opacity(0.3))
        }
    }

    private func prettifyCondition(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: " ").capitalized
    }

    // MARK: - Perforated edge

    /// Decorative scalloped paper edge. Used on the top and bottom of the
    /// receipt so the rasterised PNG reads as "a piece of paper".
    private func perforation(_ side: PerforationSide) -> some View {
        let count = 22
        return HStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { _ in
                Circle()
                    .fill(Color.clear)
                    .frame(width: 12, height: 12)
                    .overlay(
                        Circle()
                            .fill(Color.black.opacity(0.0001)) // keep shape stable
                    )
            }
        }
        .frame(height: 6)
        .background(
            HStack(spacing: 0) {
                ForEach(0..<count, id: \.self) { _ in
                    Circle()
                        .fill(Theme.Colors.bg)
                        .frame(width: 8, height: 8)
                        .offset(y: side == .top ? -1 : 1)
                }
            }
            .frame(maxWidth: .infinity)
        )
    }

    private enum PerforationSide { case top, bottom }
}
