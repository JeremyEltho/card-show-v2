import Foundation
@preconcurrency import AVFoundation
import Observation

enum ScanState: Equatable {
    case idle
    case scanning
    case autoConfirmed(CardMatch)        // ≥ 95% — auto-logged, show undo banner
    case awaitingConfirmation(CardMatch) // 80–94% — ask user
    case manualAssist(String)            // < 80% — show OCR hint + search
    case tradeReview                     // both trade cards captured, summary sheet up
    case error(String)

    static func == (lhs: ScanState, rhs: ScanState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.scanning, .scanning), (.tradeReview, .tradeReview): return true
        case (.error(let a), .error(let b)): return a == b
        case (.manualAssist(let a), .manualAssist(let b)): return a == b
        default: return false
        }
    }
}

/// In-progress trade: two cards (give + get) plus an optional cash side
/// adjustment. Lives on the ScannerViewModel for the duration of a single
/// trade. `reset()` clears it for the next one.
@Observable
final class TradeBuilder {
    var giveCard: CardMatch?
    var getCard: CardMatch?
    var cashSide: CashSide = .none
    var cashAmount: Double = 0

    enum CashSide: String, CaseIterable, Identifiable {
        case none, mine, theirs
        var id: String { rawValue }
        var title: String {
            switch self {
            case .none:   return "EVEN"
            case .mine:   return "I PAID CASH"
            case .theirs: return "THEY PAID CASH"
            }
        }
    }

    enum Stage { case awaitingGive, awaitingGet, review }

    var stage: Stage {
        if giveCard == nil { return .awaitingGive }
        if getCard  == nil { return .awaitingGet }
        return .review
    }

    func reset() {
        giveCard = nil
        getCard = nil
        cashSide = .none
        cashAmount = 0
    }
}

@Observable @MainActor
final class ScannerViewModel: CardScannerDelegate {
    var scanState: ScanState = .idle
    var previewLayer: AVCaptureVideoPreviewLayer?
    var cardOverlayRect: CGRect?
    var isLoggingToInventory = false
    var lastLoggedCard: LocalInventoryItem?

    /// Set to true right after a successful log. Drives the success overlay,
    /// which offers DONE / SCAN ANOTHER / UNDO.
    var didJustLog: Bool = false

    /// Vendor action context — controls the default status when logging a scan,
    /// and what the ScanResultSheet pre-selects. Set by the calling view.
    var logMode: LogMode = .buy

    /// Whether the scanner runs in deliberate receipt-on-each-scan mode or
    /// fast bulk-scan mode. Set by ScannerView from LogActionPickerView.
    var receiptMode: ReceiptMode = .withReceipt

    /// Transient banner message used in fast mode. Cleared after ~1.5s.
    var fastToast: String? = nil

    /// Two-card trade workflow state. Only meaningful when logMode == .trade.
    let tradeBuilder = TradeBuilder()

    /// While true, the scanner pauses detection — used between scans to avoid
    /// instantly re-logging the same card before the user moves the phone.
    var isPausedAfterLog: Bool = false

    private let scannerService = CardScannerService()

    // MARK: - Camera

    func startCamera() async {
        do {
            let layer = try await scannerService.startSession()
            self.previewLayer = layer
            self.scanState = .scanning
            await scannerService.setDelegate(self)
        } catch {
            scanState = .error("Camera not available: \(error.localizedDescription)")
        }
    }

    func stopCamera() async {
        await scannerService.stopSession()
    }

    /// Forward the current receiptMode to the scanner. Fast mode tunes the
    /// scanner for snappier detection (tighter frame gate, no rectangle
    /// detection, no API enrichment).
    func applyReceiptModeToScanner() async {
        await scannerService.setFastMode(receiptMode == .fast)
    }

    /// Halt or resume the scanner's OCR pipeline based on whether a modal
    /// sheet is currently consuming attention. ScannerView calls this
    /// whenever scanState transitions.
    func setScannerPaused(_ paused: Bool) async {
        await scannerService.setPaused(paused)
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

    // MARK: - Router
    //
    // Routing is the SAME for both modes — the confirmation sheet always
    // appears at >=0.80 so the vendor can sanity-check the match and set
    // the price. Mode only controls the post-confirm UX:
    //
    //   WITH RECEIPT → success overlay with one-tap SAVE RECEIPT button
    //   FAST         → brief sticker toast banner, immediate return to scan
    //
    //   >= 0.80 → .awaitingConfirmation (sheet)
    //   < 0.80  → .manualAssist
    //
    // The downstream scanner only drops below 0.40, so every tier above is
    // reachable from the live scan stream.

    private func handleMatch(_ match: CardMatch) async {
        guard !didJustLog, !isPausedAfterLog else { return }
        if case .awaitingConfirmation = scanState { return }
        if case .manualAssist        = scanState { return }
        if case .autoConfirmed       = scanState { return }

        if match.confidence >= 0.80 {
            scanState = .awaitingConfirmation(match)
        } else {
            scanState = .manualAssist(match.name)
        }
    }

    // MARK: - User actions

    func confirmCard(_ match: CardMatch, price: Double?, condition: String,
                     status: String, sourceLocation: String) async {
        // Trade mode is a two-card workflow — confirm doesn't log immediately,
        // it accumulates the side onto the TradeBuilder. The final commit
        // (with optional cash adjustment) is the TradeSummarySheet.
        if logMode == .trade {
            await advanceTrade(with: match)
            return
        }

        isLoggingToInventory = true
        defer { isLoggingToInventory = false }

        var enriched = match
        if let price { enriched.marketPrice = price }

        await logCard(enriched, status: status, condition: condition,
                      purchasePrice: price, sourceLocation: sourceLocation, auto: false)

        switch receiptMode {
        case .withReceipt:
            didJustLog = true
        case .fast:
            // No overlay in fast mode — flash a brief toast and resume.
            showFastToast(for: enriched, price: price)
        }
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
        isPausedAfterLog = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            isPausedAfterLog = false
        }
    }

    func undoLastLog() async {
        if let item = lastLoggedCard {
            InventoryService.shared.delete(item: item)
        }
        lastLoggedCard = nil
        didJustLog = false
        scanState = .scanning
    }

    // MARK: - Trade workflow

    /// Push a confirmed match onto the TradeBuilder. First push fills the
    /// "give" side; second push fills the "get" side and raises the
    /// TradeSummarySheet for the cash-adjustment step.
    private func advanceTrade(with match: CardMatch) async {
        switch tradeBuilder.stage {
        case .awaitingGive:
            tradeBuilder.giveCard = match
            scanState = .scanning
        case .awaitingGet:
            tradeBuilder.getCard = match
            scanState = .tradeReview
        case .review:
            // Already at review — no-op; sheet handles commit/cancel.
            break
        }
    }

    /// Write both inventory items for the in-progress trade and clear the
    /// builder. Both rows are status="traded", share a fresh tradeId, and
    /// carry a notes line describing the other side + any cash adjustment.
    func commitTrade() async {
        guard let give = tradeBuilder.giveCard,
              let get  = tradeBuilder.getCard else { return }
        isLoggingToInventory = true
        defer { isLoggingToInventory = false }

        let tradeId = UUID().uuidString
        let cashLine = cashNote()

        let giveImagePath = give.capturedImage.flatMap { CardImageStore.save($0) }
        let getImagePath  = get.capturedImage.flatMap  { CardImageStore.save($0) }

        let giveNotes = "Traded away for \(get.name).\(cashLine)"
        let getNotes  = "Traded \(give.name) for this.\(cashLine)"

        InventoryService.shared.add(
            card: give,
            purchasePrice: nil,
            status: "traded",
            condition: "near_mint",
            sourceLocation: "",
            capturedImagePath: giveImagePath,
            tradeId: tradeId,
            notes: giveNotes
        )
        let getItem = InventoryService.shared.add(
            card: get,
            purchasePrice: nil,
            status: "traded",
            condition: "near_mint",
            sourceLocation: "",
            capturedImagePath: getImagePath,
            tradeId: tradeId,
            notes: getNotes
        )

        // Surface the just-logged "get" card on the success overlay. Use the
        // value returned by add() directly — no need to re-scan the table.
        lastLoggedCard = getItem

        switch receiptMode {
        case .withReceipt:
            didJustLog = true
        case .fast:
            showFastToast(for: get, price: nil)
        }

        tradeBuilder.reset()
        scanState = .scanning
    }

    /// User backed out of the summary sheet. Drop the partially-built trade
    /// and return to scanning.
    func cancelTrade() {
        tradeBuilder.reset()
        scanState = .scanning
    }

    private func cashNote() -> String {
        switch tradeBuilder.cashSide {
        case .none:   return ""
        case .mine:   return String(format: " I paid +$%.2f cash.", tradeBuilder.cashAmount)
        case .theirs: return String(format: " They paid +$%.2f cash.", tradeBuilder.cashAmount)
        }
    }

    // MARK: - Fast-mode toast
    //
    // Both modes always show the confirmation sheet for >=0.80 matches. After
    // the user confirms in FAST mode, this transient toast replaces the
    // success overlay so the scanner can immediately resume.

    /// Set the transient toast banner and arm a 1.5s pause so the same card
    /// can't immediately re-log.
    private func showFastToast(for match: CardMatch, price: Double?) {
        let priceStr = price.map { String(format: "$%.0f", $0) } ?? "—"
        fastToast = "\(logMode.title) · \(match.name) · \(priceStr)"
        isPausedAfterLog = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            fastToast = nil
            isPausedAfterLog = false
        }
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
        // Persist the live camera capture to disk, if we have one. The
        // returned filename is stored on the inventory item so the receipt
        // exporter (and CardDetailView) can load the real photo later
        // instead of falling back to pokemontcg.io stock art.
        let capturedPath: String? = match.capturedImage.flatMap { CardImageStore.save($0) }

        let item = InventoryService.shared.add(
            card: match,
            purchasePrice: purchasePrice ?? match.marketPrice,
            status: status,
            condition: condition,
            sourceLocation: sourceLocation ?? "",
            capturedImagePath: capturedPath
        )
        lastLoggedCard = item
    }
}

// Set delegate on the actor from outside.
extension CardScannerService {
    func setDelegate(_ delegate: any CardScannerDelegate) {
        self.delegate = delegate
    }
}
