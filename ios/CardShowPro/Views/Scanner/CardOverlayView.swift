import SwiftUI

struct CardOverlayView: View {
    let cardRect: CGRect?
    let scanState: ScanState

    private var borderColor: Color {
        switch scanState {
        case .autoConfirmed: return Theme.Colors.green
        case .awaitingConfirmation: return Theme.Colors.amber
        case .manualAssist: return Theme.Colors.red
        case .scanning where cardRect != nil: return Theme.Colors.amber
        default: return .clear
        }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Guide frame when no card detected — corner brackets only
                if cardRect == nil, case .scanning = scanState {
                    GuideFrame()
                        .stroke(Theme.Colors.amber.opacity(0.6), lineWidth: 2)
                        .frame(width: geo.size.width * 0.78, height: geo.size.width * 0.78 * 1.4)
                }

                // Card bounding box with confidence-coloured corners
                if let rect = cardRect {
                    let flipped = CGRect(
                        x: rect.minX * geo.size.width,
                        y: (1 - rect.maxY) * geo.size.height,
                        width: rect.width * geo.size.width,
                        height: rect.height * geo.size.height
                    )
                    CornerBrackets()
                        .stroke(borderColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: flipped.width, height: flipped.height)
                        .position(x: flipped.midX, y: flipped.midY)
                        .animation(.easeInOut(duration: 0.15), value: rect)
                        .shadow(color: borderColor.opacity(0.5), radius: 8)
                }
            }
        }
    }
}

// MARK: - Corner brackets (4 L-shaped corners)

struct CornerBrackets: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let len = min(rect.width, rect.height) * 0.15

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

struct GuideFrame: Shape {
    func path(in rect: CGRect) -> Path {
        CornerBrackets().path(in: rect)
    }
}
