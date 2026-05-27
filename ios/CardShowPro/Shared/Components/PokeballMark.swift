import SwiftUI

/// Iconic pokeball mark drawn entirely in SwiftUI — no asset dependency.
/// Used as the home-screen logo and as the corner-badge "type symbol" on
/// the Pokemon-card-styled action buttons.
///
/// All measurements are derived from `size` directly (no GeometryReader)
/// since the mark is a fixed-size view. Cheaper layout, no propagation of
/// size invalidations through the view tree.
struct PokeballMark: View {
    var size: CGFloat = 28
    /// Slight tilt off-axis — feels stamped on, not engineered.
    var rotation: Double = -6

    /// Standard pokemon red. Slightly cooler than the existing Theme.Colors.red
    /// because we want the iconic "red & white" pop, not the Beckett ink red.
    private let red = Color(red: 0.92, green: 0.18, blue: 0.20)

    var body: some View {
        // Inset of the inner cream half (also = outer black ring thickness).
        let inset = size * 0.06

        ZStack {
            // Outer black ring
            Circle()
                .fill(Color.black)

            // Inner cream half: red top, white bottom.
            ZStack(alignment: .top) {
                Color.white
                red.frame(height: (size - inset * 2) * 0.5)
            }
            .frame(width: size - inset * 2, height: size - inset * 2)
            .clipShape(Circle())

            // Black equatorial band
            Rectangle()
                .fill(Color.black)
                .frame(height: size * 0.11)

            // White center button with black stroke
            Circle()
                .fill(Color.white)
                .overlay(Circle().stroke(Color.black, lineWidth: size * 0.04))
                .frame(width: size * 0.28, height: size * 0.28)
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(rotation))
        .shadow(color: .black.opacity(0.35), radius: size * 0.08, x: 1, y: size * 0.06)
    }
}
