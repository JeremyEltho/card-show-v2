import SwiftUI

/// Faded pokeball watermark, tiled across the background. Sits over the
/// existing CardBackPattern (felt-table swirl) on HomeView — adds
/// unmistakable pokemon vibes without competing with foreground content.
///
/// All tiles are drawn in a single SwiftUI `Canvas` pass — much cheaper than
/// instantiating ~150 individual `PokeballMark` views, which was making the
/// home screen feel heavy on real devices.
struct PokeballPattern: View {
    /// Tile size in points. Each pokeball is roughly half this.
    var cellSize: CGFloat = 72
    /// Watermark opacity. Keep very low — this is texture, not signal.
    var opacity: Double = 0.06

    /// Standard pokemon red, dimmed via the parent opacity modifier.
    private let red = Color(red: 0.92, green: 0.18, blue: 0.20)

    var body: some View {
        Canvas(opaque: false) { ctx, size in
            let cols = Int(size.width / cellSize) + 2
            let rows = Int(size.height / cellSize) + 2
            let ballSize = cellSize * 0.5

            for row in 0..<rows {
                for col in 0..<cols {
                    let xShift: CGFloat = (row % 2 == 0) ? 0 : cellSize / 2
                    let cx = CGFloat(col) * cellSize + xShift
                    let cy = CGFloat(row) * cellSize * 0.9
                    drawPokeball(in: ctx, center: CGPoint(x: cx, y: cy), size: ballSize)
                }
            }
        }
        .opacity(opacity)
        .allowsHitTesting(false)
    }

    /// Stamps a single pokeball at `center`. Five primitives, one Canvas
    /// drawing context — orders of magnitude cheaper than a SwiftUI view tree.
    private func drawPokeball(in ctx: GraphicsContext, center: CGPoint, size: CGFloat) {
        let rect = CGRect(x: center.x - size / 2,
                          y: center.y - size / 2,
                          width: size, height: size)

        // Outer black ring (full circle).
        ctx.fill(Path(ellipseIn: rect), with: .color(.black))

        // Inset cream-white core.
        let inset = size * 0.06
        let inner = rect.insetBy(dx: inset, dy: inset)
        ctx.fill(Path(ellipseIn: inner), with: .color(.white))

        // Red top half — clip to inner ellipse, fill upper rectangle.
        ctx.drawLayer { layer in
            layer.clip(to: Path(ellipseIn: inner))
            let topHalf = CGRect(x: inner.minX, y: inner.minY,
                                 width: inner.width, height: inner.height / 2)
            layer.fill(Path(topHalf), with: .color(red))
        }

        // Black equatorial band.
        let bandHeight = size * 0.10
        let band = CGRect(x: rect.minX, y: center.y - bandHeight / 2,
                          width: size, height: bandHeight)
        ctx.fill(Path(band), with: .color(.black))

        // Centre button (outer black + inner white).
        let outerBtn = size * 0.22
        let outerRect = CGRect(x: center.x - outerBtn / 2,
                               y: center.y - outerBtn / 2,
                               width: outerBtn, height: outerBtn)
        ctx.fill(Path(ellipseIn: outerRect), with: .color(.black))
        let innerBtn = outerBtn * 0.6
        let innerRect = CGRect(x: center.x - innerBtn / 2,
                               y: center.y - innerBtn / 2,
                               width: innerBtn, height: innerBtn)
        ctx.fill(Path(ellipseIn: innerRect), with: .color(.white))
    }
}
