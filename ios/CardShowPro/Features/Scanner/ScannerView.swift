import SwiftUI
import AVFoundation

struct ScannerView: View {
    let logMode: LogMode
    let receiptMode: ReceiptMode
    @State private var vm = ScannerViewModel()
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    init(logMode: LogMode = .buy, receiptMode: ReceiptMode = .withReceipt) {
        self.logMode = logMode
        self.receiptMode = receiptMode
    }

    var body: some View {
        ZStack {
            // Camera preview fills the entire screen
            CameraPreviewView(layer: vm.previewLayer)
                .ignoresSafeArea()

            // Card guide frame with dimmed surround + detection overlay
            CardOverlayView(cardRect: vm.cardOverlayRect, scanState: vm.scanState)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            // Top brand bar
            VStack {
                topBar
                if let msg = vm.fastToast { fastToastBanner(msg) }
                Spacer()
                bottomHint
            }

            // Success overlay — appears after every successful log.
            // Vendor decides whether to scan more or go home.
            if vm.didJustLog {
                ScanSuccessOverlay(
                    item: vm.lastLoggedCard,
                    logMode: logMode,
                    onDone: {
                        vm.didJustLog = false
                        vm.lastLoggedCard = nil
                        dismiss()
                    },
                    onScanAnother: { vm.continueScanning() },
                    onUndo: { Task { await vm.undoLastLog() } }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: vm.didJustLog)
            }
        }
        .sheet(isPresented: Binding(
            get: { if case .awaitingConfirmation = vm.scanState { return true }; return false },
            set: { if !$0 { vm.dismissAndReset() } }
        )) {
            if case .awaitingConfirmation(let match) = vm.scanState {
                ScanResultSheet(
                    match: match,
                    logMode: logMode,
                    isAwaitingConfirmation: true,
                    confirmLabelOverride: tradeSheetLabel,
                    hidesPriceField: logMode == .trade,
                    onConfirm: { price, condition, status in
                        Task { await vm.confirmCard(match, price: price, condition: condition, status: status, sourceLocation: appState.activeShowName) }
                    },
                    onReject: { vm.dismissAndReset() }
                )
                .presentationDetents([.medium, .large])
                .presentationBackground(Theme.Colors.bg)
            }
        }
        .sheet(isPresented: Binding(
            get: { vm.scanState == .tradeReview },
            set: { if !$0 { vm.cancelTrade() } }
        )) {
            TradeSummarySheet(
                builder: vm.tradeBuilder,
                onConfirm: { Task { await vm.commitTrade() } },
                onCancel: { vm.cancelTrade() }
            )
            .presentationDetents([.large])
            .presentationBackground(Theme.Colors.bg)
        }
        .sheet(isPresented: Binding(
            get: { if case .manualAssist = vm.scanState { return true }; return false },
            set: { if !$0 { vm.dismissAndReset() } }
        )) {
            if case .manualAssist(let ocrHint) = vm.scanState {
                ManualAssistView(ocrHint: ocrHint) { match in
                    Task { await vm.confirmCard(match, price: match.marketPrice, condition: "near_mint", status: logMode.inventoryStatus, sourceLocation: appState.activeShowName) }
                }
                .presentationDetents([.medium, .large])
                .presentationBackground(Theme.Colors.bg)
            }
        }
        .task {
            vm.logMode = logMode
            vm.receiptMode = receiptMode
            await vm.startCamera()
            await vm.applyReceiptModeToScanner()
        }
        .onDisappear { Task { await vm.stopCamera() } }
        // Pause the OCR pipeline whenever a modal sheet is up. Camera preview
        // keeps streaming (cheap) but Vision + fuzzy match + overlay updates
        // halt — stops them from contending with the keyboard when the user
        // is typing in a price field.
        .onChange(of: vm.scanState) { _, newState in
            let shouldPause: Bool
            switch newState {
            case .awaitingConfirmation, .manualAssist, .tradeReview, .autoConfirmed:
                shouldPause = true
            case .idle, .scanning, .error:
                shouldPause = false
            }
            Task { await vm.setScannerPaused(shouldPause) }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: Theme.Spacing.sm) {
            // Mode pill — biggest signal on the screen so the vendor knows what
            // action will be taken when the scan auto-confirms. In trade mode,
            // the pill flips to "TRADE · GIVE" then "TRADE · GET" as the
            // builder fills.
            HStack(spacing: 6) {
                Image(systemName: logMode.icon)
                    .font(.system(size: 14, weight: .bold))
                Text(modePillText)
                    .font(Theme.Typography.label)
                    .tracking(2)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(logMode.tint))
            .foregroundStyle(.black)

            Spacer()

            if !appState.activeShowName.isEmpty {
                HStack(spacing: 6) {
                    Circle().fill(Theme.Colors.green).frame(width: 6, height: 6)
                    Text(appState.activeShowName.uppercased())
                        .font(Theme.Typography.label)
                        .tracking(1)
                        .foregroundStyle(Theme.Colors.green)
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(.ultraThinMaterial)
    }

    // MARK: - Trade-aware helpers

    /// What the mode pill says at the top of the camera view.
    /// Standard modes show "{TITLE} MODE"; trade flips between GIVE/GET as
    /// the two-card builder fills.
    private var modePillText: String {
        guard logMode == .trade else { return "\(logMode.title) MODE" }
        switch vm.tradeBuilder.stage {
        case .awaitingGive: return "TRADE · GIVE"
        case .awaitingGet:  return "TRADE · GET"
        case .review:       return "TRADE · REVIEW"
        }
    }

    /// What the confirm button on the sheet says when we're in trade mode.
    /// Nil means "use the default LOG <mode>" label.
    private var tradeSheetLabel: String? {
        guard logMode == .trade else { return nil }
        switch vm.tradeBuilder.stage {
        case .awaitingGive: return "NEXT"
        case .awaitingGet:  return "REVIEW"
        case .review:       return "REVIEW"
        }
    }

    // MARK: - Fast-mode toast banner

    /// Slim sticker-style banner shown after a fast-mode log. Reads as a
    /// receipt thermal print: monospaced, dashed border, slight rotation so
    /// it feels stamped on rather than rendered.
    private func fastToastBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(Theme.Colors.green)
            Text(message)
                .font(Theme.Typography.priceSm)
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .fill(Theme.Colors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .stroke(Theme.Colors.green,
                                style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                )
        )
        .rotationEffect(.degrees(-1.5))
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.top, Theme.Spacing.sm)
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: message)
    }

    // MARK: - Bottom hint

    private var bottomHint: some View {
        Group {
            switch vm.scanState {
            case .idle, .scanning:
                Text(vm.cardOverlayRect == nil ? "POINT AT A CARD" : "HOLD STEADY…")
                    .font(Theme.Typography.label)
                    .tracking(2)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(Capsule().fill(Color.black.opacity(0.5)))
                    .padding(.bottom, 24)
            default:
                EmptyView()
            }
        }
    }

}

// MARK: - Camera preview UIViewRepresentable

struct CameraPreviewView: UIViewRepresentable {
    let layer: AVCaptureVideoPreviewLayer?

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let layer else { return }
        layer.frame = uiView.bounds
        if layer.superlayer == nil {
            uiView.layer.addSublayer(layer)
        }
    }
}

// MARK: - Manual assist sheet (dark-themed)

struct ManualAssistView: View {
    let ocrHint: String
    let onSelect: (CardMatch) -> Void

    @State private var searchText: String
    @State private var results: [CardSearchResult] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>? = nil
    @Environment(\.dismiss) private var dismiss

    init(ocrHint: String, onSelect: @escaping (CardMatch) -> Void) {
        self.ocrHint = ocrHint
        self.onSelect = onSelect
        _searchText = State(initialValue: ocrHint)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.bg.ignoresSafeArea()

                VStack(spacing: 0) {
                    VStack(spacing: Theme.Spacing.sm) {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(Theme.Colors.amber)
                            Text("COULDN'T IDENTIFY")
                                .font(Theme.Typography.label)
                                .tracking(1)
                                .foregroundStyle(Theme.Colors.amber)
                        }
                        if !ocrHint.isEmpty {
                            Text("OCR read: \"\(ocrHint)\"")
                                .font(Theme.Typography.captionMono)
                                .foregroundStyle(Theme.Colors.textTertiary)
                        }
                    }
                    .padding(.top, Theme.Spacing.md)
                    .padding(.bottom, Theme.Spacing.md)

                    TextField("Search card name", text: $searchText)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .padding(Theme.Spacing.md)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Radius.md)
                                .fill(Theme.Colors.surface)
                        )
                        .padding(.horizontal, Theme.Spacing.md)
                        .onChange(of: searchText) { _, q in
                            // Debounce: cancel any in-flight search, then
                            // wait briefly before firing the new one. Avoids
                            // a network request per keystroke and the
                            // last-response-wins race.
                            searchTask?.cancel()
                            searchTask = Task {
                                try? await Task.sleep(for: .milliseconds(250))
                                guard !Task.isCancelled else { return }
                                await search(q)
                            }
                        }

                    if isSearching {
                        ProgressView()
                            .tint(Theme.Colors.amber)
                            .padding()
                    }

                    ScrollView {
                        LazyVStack(spacing: Theme.Spacing.sm) {
                            ForEach(results) { card in
                                Button {
                                    onSelect(CardMatch(
                                        cardId: card.id, name: card.name,
                                        setName: card.setName, number: card.number,
                                        imageUrlSm: card.imageUrlSm,
                                        confidence: 1.0, marketPrice: nil, pipeline: "manual"
                                    ))
                                    dismiss()
                                } label: {
                                    HStack(spacing: Theme.Spacing.md) {
                                        if let url = card.imageUrlSm.flatMap(URL.init) {
                                            CachedAsyncImage(url: url) { phase in
                                                switch phase {
                                                case .success(let img):
                                                    img.resizable().aspectRatio(contentMode: .fill)
                                                default:
                                                    Theme.Colors.surfaceHi
                                                }
                                            }
                                            .frame(width: 40, height: 56)
                                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                                        }
                                        VStack(alignment: .leading) {
                                            Text(card.name)
                                                .font(Theme.Typography.body)
                                                .foregroundStyle(Theme.Colors.textPrimary)
                                            if let set = card.setName {
                                                Text(set)
                                                    .font(Theme.Typography.caption)
                                                    .foregroundStyle(Theme.Colors.textTertiary)
                                            }
                                        }
                                        Spacer()
                                    }
                                    .padding(Theme.Spacing.md)
                                    .background(
                                        RoundedRectangle(cornerRadius: Theme.Radius.md)
                                            .fill(Theme.Colors.surface)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(Theme.Spacing.md)
                    }
                }
            }
            .navigationTitle("Manual Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
        }
        .task { await search(ocrHint) }
    }

    private func search(_ query: String) async {
        guard query.count >= 2 else { results = []; return }
        isSearching = true
        let fetched = await PokemonTCGService.shared.search(query: query, limit: 10)
        // If this Task was cancelled while we were waiting for the network,
        // don't clobber the visible results with stale data.
        guard !Task.isCancelled else { return }
        results = fetched
        isSearching = false
    }
}
