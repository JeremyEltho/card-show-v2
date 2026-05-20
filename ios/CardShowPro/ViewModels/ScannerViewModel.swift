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
    var lastLoggedCard: InventoryItem?
    var undoAvailable = false

    private let scannerService = CardScannerService()
    private let network = NetworkService.shared

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
            // Auto-confirm: log immediately
            scanState = .autoConfirmed(match)
            await logCard(match, auto: true)
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
        guard let item = lastLoggedCard else { return }
        try? await network.delete("/inventory/\(item.id)")
        lastLoggedCard = nil
        undoAvailable = false
    }

    // MARK: - Logging

    private func logCard(
        _ match: CardMatch,
        status: String = "bought",
        condition: String = "near_mint",
        purchasePrice: Double? = nil,
        sourceLocation: String? = nil,
        auto: Bool
    ) async {
        let req = CreateInventoryRequest(
            cardId: match.cardId,
            status: status,
            condition: condition,
            quantity: 1,
            purchasePrice: purchasePrice ?? match.marketPrice,
            salePrice: nil,
            marketPriceAtScan: match.marketPrice,
            notes: auto ? "Auto-logged (confidence: \(Int(match.confidence * 100))%)" : nil,
            sourceLocation: sourceLocation,
            paymentMethod: nil,
            clientId: UUID().uuidString
        )
        do {
            let item: InventoryItem = try await network.post("/inventory", body: req)
            lastLoggedCard = item
        } catch {
            // Silently fail — item saved offline via SwiftData if needed
        }
    }
}

// Extension to set delegate on the actor
extension CardScannerService {
    func setDelegate(_ delegate: any CardScannerDelegate) {
        self.delegate = delegate
    }
}
