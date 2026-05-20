import SwiftUI

struct CardOverlayView: View {
    let cardRect: CGRect?
    let scanState: ScanState

    private var borderColor: Color {
        switch scanState {
        case .autoConfirmed: return .green
        case .awaitingConfirmation: return .yellow
        case .manualAssist: return .red
        case .scanning where cardRect != nil: return .white.opacity(0.8)
        default: return .clear
        }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Guide frame when no card detected
                if cardRect == nil, case .scanning = scanState {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.3), lineWidth: 2)
                        .frame(width: geo.size.width * 0.7, height: geo.size.height * 0.5)
                        .overlay(
                            Text("Point at card")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.6))
                                .offset(y: geo.size.height * 0.28)
                        )
                }

                // Card bounding box
                if let rect = cardRect {
                    let flipped = CGRect(
                        x: rect.minX * geo.size.width,
                        y: (1 - rect.maxY) * geo.size.height,
                        width: rect.width * geo.size.width,
                        height: rect.height * geo.size.height
                    )
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(borderColor, lineWidth: 3)
                        .frame(width: flipped.width, height: flipped.height)
                        .position(x: flipped.midX, y: flipped.midY)
                        .animation(.easeInOut(duration: 0.15), value: rect)
                }
            }
        }
    }
}
