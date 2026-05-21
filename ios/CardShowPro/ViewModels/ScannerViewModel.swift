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

    /// Set to true right after a successful log. Drives the success overlay.
    /// The overlay then offers DONE / SCAN ANOTHER / UNDO.
    var didJustLog: Bool = false

    /// Vendor action context — controls the default status when logging a scan,
    /// and what the ScanResultSheet pre-selects. Set by the calling view.
    var logMode: LogMode = .buy

    /// While true, the scanner pauses detection — used between scans to avoid
    /// instantly re-logging the same card before the user moves the phone.
    var isPausedAfterLog: Bool = false

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
        // Ignore new detections while a sheet is open, the success overlay is up,
        // or we're paused between scans.
        guard !didJustLog, !isPausedAfterLog else { return }
        // If a confirmation sheet is already showing for this scan, don't replace it
        if case .awaitingConfirmation = scanState { return }
        if case .manualAssist = scanState { return }

        let confidence = match.confidence

        // Vendors always need to enter the price they actually paid (it almost never
        // equals the market price). Even at very high card-ID confidence we still
        // show the result sheet so the price can be edited before logging.
        if confidence >= 0.80 {
            scanState = .awaitingConfirmation(match)
        } else {
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
        // Sheet-driven confirms also raise the success overlay
        didJustLog = true
        scanState = .scanning
    }

    func dismissAndReset() {
        scanState = .scanning
    }

    /// Called by the success overlay's "SCAN ANOTHER" button. Clears the
    /// just-logged flag and starts a short pause so the same card doesn't
    /// immediately re-fire before the vendor moves the phone.
    func continueScanning() {
        didJustLog = false
        lastLoggedCard = nil
        scanState = .scanning
        // Brief pause to give the user time to swap cards
        isPausedAfterLog = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            isPausedAfterLog = false
        }
    }

    func undoLastLog() async {
        if let item = lastLoggedCard {
            await MainActor.run { InventoryService.shared.delete(item: item) }
        }
        lastLoggedCard = nil
        didJustLog = false
        scanState = .scanning
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
