import SwiftUI

/// Subtle repeating pattern inspired by the swirly back of a Pokémon card.
/// Drawn as Canvas at low opacity so it reads as table-felt texture, not as
/// distracting decoration. Use as a background layer behind content.
struct CardBackPattern: View {
    var color: Color = Color.white.opacity(0.045)
    var spacing: CGFloat = 32

    var body: some View {
        Canvas { context, size in
            let cols = Int(size.width / spacing) + 2
            let rows = Int(size.height / spacing) + 2
            let r: CGFloat = spacing * 0.18

            for row in 0..<rows {
                for col in 0..<cols {
                    // Stagger every other row by half-spacing for honeycomb feel
                    let xOffset = (row % 2 == 0) ? 0.0 : spacing / 2
                    let cx = CGFloat(col) * spacing + xOffset
                    let cy = CGFloat(row) * spacing

                    // Outer dot
                    let dot = Path(ellipseIn: CGRect(x: cx - r, y: cy - r,
                                                     width: r * 2, height: r * 2))
                    context.fill(dot, with: .color(color))

                    // Inner ring around it (subtle, smaller)
                    let ring = Path(ellipseIn: CGRect(x: cx - r * 2.2, y: cy - r * 2.2,
                                                      width: r * 4.4, height: r * 4.4))
                    context.stroke(ring, with: .color(color.opacity(0.5)), lineWidth: 0.5)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// Diagonal "convention badge" pattern — alternating felt-green stripes for
/// section dividers and lanyard / nameplate accents.
struct ConventionStripes: View {
    var spacing: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                let count = Int((size.width + size.height) / spacing) + 1
                for i in 0...count {
                    let x = CGFloat(i) * spacing
                    var p = Path()
                    p.move(to: CGPoint(x: x, y: 0))
                    p.addLine(to: CGPoint(x: x - size.height, y: size.height))
                    context.stroke(p, with: .color(Color.black.opacity(0.08)),
                                   lineWidth: spacing / 2)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .allowsHitTesting(false)
    }
}
