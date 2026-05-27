import SwiftUI

/// Animated holographic shimmer — looks like the edge of a foil Pokémon card
/// catching the light. Used on primary CTAs and key value displays.
struct HoloShimmer: ViewModifier {
    /// Stroke thickness for the shimmer border.
    var lineWidth: CGFloat = 2
    /// Corner radius applied to the stroke.
    var cornerRadius: CGFloat = Theme.Radius.lg
    /// Animation duration for one full rotation.
    var duration: Double = 3.5

    @State private var phase: Double = 0
    @State private var isAnimating: Bool = false

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        AngularGradient(
                            colors: [
                                Theme.Colors.holo1, Theme.Colors.holo2, Theme.Colors.holo3,
                                Theme.Colors.holo4, Theme.Colors.holo5, Theme.Colors.holo6,
                                Theme.Colors.holo1
                            ],
                            center: .center,
                            angle: .degrees(phase)
                        ),
                        lineWidth: lineWidth
                    )
            )
            .onAppear { startAnimating() }
            .onDisappear { stopAnimating() }
    }

    private func startAnimating() {
        guard !isAnimating else { return }
        isAnimating = true
        withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
            phase = 360
        }
    }

    /// Halt the continuous rotation when the host view leaves the screen.
    /// Without this the .repeatForever animation keeps churning the run loop
    /// even when the holo border isn't visible.
    private func stopAnimating() {
        isAnimating = false
        withAnimation(.linear(duration: 0)) {
            phase = 0
        }
    }
}

extension View {
    func holoShimmer(lineWidth: CGFloat = 2,
                     cornerRadius: CGFloat = Theme.Radius.lg,
                     duration: Double = 3.5) -> some View {
        modifier(HoloShimmer(lineWidth: lineWidth, cornerRadius: cornerRadius, duration: duration))
    }
}

/// Solid holo gradient fill (no animation) — useful for big surface fills
/// like the success overlay backdrop or hero numbers.
struct HoloFill: View {
    var radius: CGFloat = Theme.Radius.lg
    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Theme.Colors.holo1, Theme.Colors.holo3, Theme.Colors.holo5, Theme.Colors.holo6],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }
}
