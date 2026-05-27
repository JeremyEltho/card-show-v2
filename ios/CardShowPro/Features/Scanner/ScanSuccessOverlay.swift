import SwiftUI
import UIKit

/// Fullscreen success overlay shown after a successful scan + log.
/// Vendor picks one of three actions:
///   - DONE         → pops back to home
///   - SCAN ANOTHER → resumes scanning (multi-scan / bulk-buy mode)
///   - UNDO         → deletes the just-logged item and resumes scanning
struct ScanSuccessOverlay: View {
    let item: LocalInventoryItem?
    let logMode: LogMode
    let onDone: () -> Void
    let onScanAnother: () -> Void
    let onUndo: () -> Void

    @State private var receiptState: ReceiptState = .idle
    @State private var includeImageInReceipt: Bool = true

    private enum ReceiptState: Equatable {
        case idle, saving, saved, failed(String)
    }

    var body: some View {
        ZStack {
            // Dim the camera fully — this is a modal moment
            Color.black.opacity(0.78).ignoresSafeArea()

            VStack(spacing: Theme.Spacing.lg) {
                Spacer()

                // Big checkmark + mode tag
                ZStack {
                    Circle()
                        .fill(logMode.tint.opacity(0.18))
                        .frame(width: 96, height: 96)
                    Image(systemName: "checkmark")
                        .font(.system(size: 44, weight: .heavy))
                        .foregroundStyle(logMode.tint)
                }

                VStack(spacing: 4) {
                    Text("\(logMode.title) LOGGED")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .tracking(3)
                        .foregroundStyle(logMode.tint)

                    Text(item?.cardName ?? "Card")
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Theme.Spacing.lg)

                    if let price = item?.purchasePrice ?? item?.salePrice {
                        Text(String(format: "$%.2f", price))
                            .font(Theme.Typography.priceLg)
                            .foregroundStyle(logMode.tint)
                            .padding(.top, 4)
                    }
                }

                Spacer()

                // Action stack — SCAN ANOTHER is primary, RECEIPT is the
                // optional vendor-record step, DONE / UNDO are secondary.
                VStack(spacing: Theme.Spacing.sm) {
                    Button(action: onScanAnother) {
                        Label("SCAN ANOTHER", systemImage: "viewfinder")
                            .font(Theme.Typography.title)
                            .tracking(2)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(logMode.tint)
                            .foregroundStyle(.black)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
                    }

                    imageToggleRow
                    receiptButton

                    Button(action: onDone) {
                        Text("DONE")
                            .font(Theme.Typography.title)
                            .tracking(2)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.Radius.lg)
                                    .stroke(Theme.Colors.border, lineWidth: 1)
                            )
                            .foregroundStyle(Theme.Colors.textPrimary)
                    }

                    Button(action: onUndo) {
                        Label("UNDO", systemImage: "arrow.uturn.backward")
                            .font(Theme.Typography.label)
                            .tracking(2)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .foregroundStyle(Theme.Colors.red)
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.xl)
            }
        }
    }

    // MARK: - Receipt

    private var imageToggleRow: some View {
        Button {
            includeImageInReceipt.toggle()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            // Re-allow a save if the user changes their mind after a save
            if case .saved = receiptState { receiptState = .idle }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: includeImageInReceipt ? "checkmark.square.fill" : "square")
                    .font(.system(size: 16, weight: .heavy))
                Text("INCLUDE CARD IMAGE")
                    .font(Theme.Typography.label)
                    .tracking(1.5)
                Spacer()
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .foregroundStyle(includeImageInReceipt
                             ? Theme.Colors.amber
                             : Theme.Colors.textTertiary)
        }
        .buttonStyle(.plain)
    }

    private var receiptButton: some View {
        Button(action: saveReceipt) {
            HStack(spacing: 8) {
                Image(systemName: receiptIcon)
                    .font(.system(size: 16, weight: .heavy))
                Text(receiptLabel)
                    .font(Theme.Typography.label)
                    .tracking(2)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.lg)
                    .fill(receiptBg)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.lg)
                            .stroke(receiptStroke,
                                    style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    )
            )
            .foregroundStyle(receiptFg)
        }
        .disabled(item == nil || receiptState == .saving || receiptState == .saved)
    }

    private var receiptIcon: String {
        switch receiptState {
        case .idle:    return "doc.text"
        case .saving:  return "ellipsis"
        case .saved:   return "checkmark.seal.fill"
        case .failed:  return "exclamationmark.triangle.fill"
        }
    }

    private var receiptLabel: String {
        switch receiptState {
        case .idle:    return "SAVE RECEIPT"
        case .saving:  return "SAVING…"
        case .saved:   return "SAVED TO PHOTOS"
        case .failed:  return "TRY AGAIN"
        }
    }

    private var receiptBg: Color {
        switch receiptState {
        case .saved:    return Theme.Colors.greenSoft
        case .failed:   return Theme.Colors.redSoft
        default:        return Theme.Colors.amberSoft
        }
    }

    private var receiptStroke: Color {
        switch receiptState {
        case .saved:    return Theme.Colors.green
        case .failed:   return Theme.Colors.red
        default:        return Theme.Colors.amber
        }
    }

    private var receiptFg: Color {
        switch receiptState {
        case .saved:    return Theme.Colors.green
        case .failed:   return Theme.Colors.red
        default:        return Theme.Colors.amber
        }
    }

    private func saveReceipt() {
        guard let item, receiptState != .saving else { return }
        receiptState = .saving
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        Task { @MainActor in
            do {
                _ = try await ReceiptExporter.save(item: item,
                                                   includeImage: includeImageInReceipt)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                receiptState = .saved
            } catch {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                receiptState = .failed(error.localizedDescription)
                // Roll back to idle so the user can retry after a beat.
                try? await Task.sleep(for: .seconds(2))
                if case .failed = receiptState { receiptState = .idle }
            }
        }
    }
}
