import SwiftUI

/// Wraps any content to look like a vintage Pokemon TCG card laid flat on the
/// felt-green table: thick yellow outer border, cream parchment inner face,
/// black-bordered illustration window, attack-list-style footer.
///
/// The "rare" variant (`isHolo = true`) adds the animated holographic
/// shimmer to the illustration window — same effect that goes on real foil
/// cards. Used as the visual shell for HomeView's action buttons.
struct PokemonCardFrame<Illustration: View, Footer: View>: View {
    let title: String
    let rarity: String
    let isHolo: Bool
    let illustration: Illustration
    let footer: Footer

    /// Slight rotation makes the card feel placed-by-hand rather than rendered.
    var rotation: Double = -1.2

    /// Vintage Pokemon yellow — warmer than the existing amber so it reads
    /// as "card border" rather than "sticker tag".
    private let cardYellow = Color(red: 0.97, green: 0.81, blue: 0.18)
    /// Cream card face — slightly more yellow than the existing parchment.
    private let cardFace = Color(red: 0.97, green: 0.93, blue: 0.82)

    init(title: String,
         rarity: String,
         isHolo: Bool = false,
         rotation: Double = -1.2,
         @ViewBuilder illustration: () -> Illustration,
         @ViewBuilder footer: () -> Footer) {
        self.title = title
        self.rarity = rarity
        self.isHolo = isHolo
        self.rotation = rotation
        self.illustration = illustration()
        self.footer = footer()
    }

    var body: some View {
        VStack(spacing: 0) {
            titleStrip
            illustrationWindow
            footerStrip
        }
        .padding(8)
        .background(
            // Inner cream card face
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(cardFace)
        )
        .padding(6)
        .background(
            // Outer yellow border
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(cardYellow)
                .overlay(
                    // Thin inner black ring — matches the look of a real
                    // pokemon card border-on-border.
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.black.opacity(0.45), lineWidth: 0.75)
                        .padding(6)
                )
        )
        .rotationEffect(.degrees(rotation))
        .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
    }

    // MARK: - Title strip
    // Card name on the left, rarity row + pokeball "type symbol" on the right.

    private var titleStrip: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 19, weight: .heavy, design: .rounded))
                .tracking(1.5)
                .foregroundStyle(Color.black)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer(minLength: 4)

            Text(rarity)
                .font(.system(size: 9, weight: .heavy, design: .serif))
                .italic()
                .tracking(1)
                .foregroundStyle(Color.black.opacity(0.6))

            PokeballMark(size: 18, rotation: -8)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 6)
    }

    // MARK: - Illustration window
    // Black-framed inset area, optionally holo-foil-shimmering for "rare"
    // cards. Holds the icon / hero glyph passed in by the caller.

    private var illustrationWindow: some View {
        ZStack {
            // Background fill — holo cards get a rainbow gradient base so the
            // animated shimmer on top has something to play against; basic
            // cards get a moody dark blue (think classic Pokemon card art).
            Group {
                if isHolo {
                    LinearGradient(
                        colors: [
                            Theme.Colors.holo1, Theme.Colors.holo2,
                            Theme.Colors.holo3, Theme.Colors.holo4,
                            Theme.Colors.holo5, Theme.Colors.holo6
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                } else {
                    LinearGradient(
                        colors: [
                            Color(red: 0.12, green: 0.20, blue: 0.34),
                            Color(red: 0.06, green: 0.12, blue: 0.22)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }

            illustration
        }
        .frame(height: 110)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(Color.black, lineWidth: 2)
        )
        .holoShimmerIf(isHolo, lineWidth: 2.5, cornerRadius: 4, duration: 4)
    }

    // MARK: - Footer
    // Attack-list-style band: black hairline divider, footer text.

    private var footerStrip: some View {
        VStack(spacing: 4) {
            Rectangle()
                .fill(Color.black.opacity(0.55))
                .frame(height: 1)
                .padding(.horizontal, 2)
                .padding(.top, 6)
            footer
                .padding(.horizontal, 4)
                .padding(.bottom, 2)
        }
    }
}

private extension View {
    /// HoloShimmer only when condition is true. Keeps callers terse.
    @ViewBuilder
    func holoShimmerIf(_ condition: Bool,
                       lineWidth: CGFloat,
                       cornerRadius: CGFloat,
                       duration: Double) -> some View {
        if condition {
            self.holoShimmer(lineWidth: lineWidth,
                             cornerRadius: cornerRadius,
                             duration: duration)
        } else {
            self
        }
    }
}
