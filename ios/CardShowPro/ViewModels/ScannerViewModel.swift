import Foundation
@preconcurrency import AVFoundation
import Observation

enum ScanState: Equatable {
    case idle
    case scanning
    case autoConfirmed(CardMatch)        // ≥ 95% — auto-logged, show undo banner
    case awaitingConfirmation(CardMatch) // 80–94% — ask user
    case manualAssist(String)           // < 80% — show OCR text + search
    case error(String)

    static func == (lhs: ScanState, rhs: ScanState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.scanning, .scanning): return true
        case (.error(let a), .error(let b)): return a == b
        case (.manualAssist(let a), .manualAssist(let b)): return a == b
        default: return false
        }
    }
}

@Observable
final class ScannerViewModel: CardScannerDelegate {
    var scanState: ScanState = .idle
    var previewLayer: AVCaptureVideoPreviewLayer?
    var cardOverlayRect: CGRect?
    var isLoggingToInventory = false
    var lastLoggedCard: LocalInventoryItem?
    var undoAvailable = false

    /// Vendor action context — controls the default status when logging a scan,
    /// and what the ScanResultSheet pre-selects. Set by the calling view.
    var logMode: LogMode = .buy

    private let scannerService = CardScannerService()

    // MARK: - Camera

    func startCamera() async {
        do {
            let layer = try await scannerService.startSession()
            await MainActor.run {
                self.previewLayer = layer
                self.scanState = .scanning
            }
            await scannerService.setDelegate(self)
        } catch {
            scanState = .error("Camera not available: \(error.localizedDescription)")
        }
    }

    func stopCamera() async {
        await scannerService.stopSession()
    }

    // MARK: - CardScannerDelegate

    nonisolated func scannerDidMatch(_ match: CardMatch) {
        Task { @MainActor in
            guard case .scanning = self.scanState else { return }
            await self.handleMatch(match)
        }
    }

    nonisolated func scannerDidUpdateOverlay(rect: CGRect?, in viewBounds: CGRect) {
        Task { @MainActor in self.cardOverlayRect = rect }
    }

    @MainActor
    private func handleMatch(_ match: CardMatch) async {
        let confidence = match.confidence

        if confidence >= 0.95 {
            // Auto-confirm: log immediately using the current mode (buy/sell/trade)
            scanState = .autoConfirmed(match)
            await logCard(match, status: logMode.inventoryStatus, auto: true)
            undoAvailable = true
            // Reset after 3 seconds
            try? await Task.sleep(for: .seconds(3))
            undoAvailable = false
            scanState = .scanning

        } else if confidence >= 0.80 {
            scanState = .awaitingConfirmation(match)

        } else {
            // Extract OCR hint from match name as best guess
            let hint = match.name
            scanState = .manualAssist(hint)
        }
    }

    // MARK: - User actions

    func confirmCard(_ match: CardMatch, price: Double?, condition: String, status: String, sourceLocation: String) async {
        isLoggingToInventory = true
        defer { isLoggingToInventory = false }

        var enriched = match
        if let price { enriched.marketPrice = price }

        await logCard(enriched, status: status, condition: condition, purchasePrice: price, sourceLocation: sourceLocation, auto: false)
        scanState = .scanning
    }

    func dismissAndReset() {
        scanState = .scanning
    }

    func undoLastLog() async {
        if let item = lastLoggedCard {
            await MainActor.run { InventoryService.shared.delete(item: item) }
        }
        lastLoggedCard = nil
        undoAvailable = false
    }

    // MARK: - Logging (local-only — no backend)

    private func logCard(
        _ match: CardMatch,
        status: String = "bought",
        condition: String = "near_mint",
        purchasePrice: Double? = nil,
        sourceLocation: String? = nil,
        auto: Bool
    ) async {
        let item = await MainActor.run {
            InventoryService.shared.add(
                card: match,
                purchasePrice: purchasePrice ?? match.marketPrice,
                status: status,
                condition: condition,
                sourceLocation: sourceLocation ?? ""
            )
        }
        lastLoggedCard = item
    }
}

// Extension to set delegate on the actor
extension CardScannerService {
    func setDelegate(_ delegate: any CardScannerDelegate) {
        self.delegate = delegate
    }
}
