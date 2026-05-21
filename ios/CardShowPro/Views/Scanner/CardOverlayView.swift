import SwiftUI

/// Camera overlay with a centered card-shaped guide frame.
/// - When no card is detected: shows the guide frame with a dimmed surround
///   so the vendor knows exactly where to place the card.
/// - When a card is detected: highlights the detected card with corner brackets
///   in a confidence-coloured outline.
struct CardOverlayView: View {
    let cardRect: CGRect?
    let scanState: ScanState

    // Standard Pokémon card aspect ratio: 63mm × 88mm = 1 : 1.397
    private let cardAspect: CGFloat = 1.4

    private var detectedBorderColor: Color {
        switch scanState {
        case .autoConfirmed: return Theme.Colors.green
        case .awaitingConfirmation: return Theme.Colors.amber
        case .manualAssist: return Theme.Colors.red
        case .scanning where cardRect != nil: return Theme.Colors.green
        default: return .clear
        }
    }

    var body: some View {
        GeometryReader { geo in
            let guide = guideFrameRect(in: geo.size)

            ZStack {
                // Dimmed surround — covers the screen with a hole cut out for the card frame
                Path { p in
                    p.addRect(CGRect(origin: .zero, size: geo.size))
                    p.addRoundedRect(in: guide, cornerSize: CGSize(width: 16, height: 16))
                }
                .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
                .allowsHitTesting(false)

                // The bright guide-frame border itself
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Theme.Colors.amber.opacity(0.85), lineWidth: 2)
                    .frame(width: guide.width, height: guide.height)
                    .position(x: guide.midX, y: guide.midY)

                // Corner brackets on top for emphasis
                CornerBrackets()
                    .stroke(Theme.Colors.amber, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: guide.width, height: guide.height)
                    .position(x: guide.midX, y: guide.midY)

                // Hint label below the frame
                if cardRect == nil, case .scanning = scanState {
                    Text("FIT CARD INSIDE FRAME")
                        .font(Theme.Typography.label)
                        .tracking(2)
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.black.opacity(0.55)))
                        .position(x: guide.midX, y: guide.maxY + 24)
                }

                // Detected card highlight — drawn over the guide when a card is found
                if let rect = cardRect {
                    let detected = CGRect(
                        x: rect.minX * geo.size.width,
                        y: (1 - rect.maxY) * geo.size.height,
                        width: rect.width * geo.size.width,
                        height: rect.height * geo.size.height
                    )
                    CornerBrackets()
                        .stroke(detectedBorderColor,
                                style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .frame(width: detected.width, height: detected.height)
                        .position(x: detected.midX, y: detected.midY)
                        .shadow(color: detectedBorderColor.opacity(0.5), radius: 10)
                        .animation(.easeInOut(duration: 0.15), value: rect)
                }
            }
        }
    }

    /// Compute the centered card-frame rectangle for the given canvas size.
    /// Frame width is ~78% of the screen width, clamped to fit the screen vertically
    /// with comfortable padding for top/bottom UI elements.
    private func guideFrameRect(in size: CGSize) -> CGRect {
        let topInset: CGFloat = 100      // leaves room for the top brand bar
        let bottomInset: CGFloat = 160   // leaves room for tab bar + hint label
        let availableHeight = size.height - topInset - bottomInset

        let desiredWidth = size.width * 0.78
        let desiredHeight = desiredWidth * cardAspect

        let height = min(desiredHeight, availableHeight)
        let width = height / cardAspect

        let x = (size.width - width) / 2
        let y = topInset + (availableHeight - height) / 2
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

// MARK: - Corner brackets shape

struct CornerBrackets: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let len = min(rect.width, rect.height) * 0.12   // bracket arm length

        // Top-left
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + len))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + len, y: rect.minY))
        // Top-right
        p.move(to: CGPoint(x: rect.maxX - len, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + len))
        // Bottom-left
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY - len))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + len, y: rect.maxY))
        // Bottom-right
        p.move(to: CGPoint(x: rect.maxX - len, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - len))

        return p
    }
}
