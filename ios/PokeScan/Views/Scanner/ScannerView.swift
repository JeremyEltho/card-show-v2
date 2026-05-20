import SwiftUI
import AVFoundation

struct ScannerView: View {
    @State private var vm = ScannerViewModel()
    @Environment(AppState.self) private var appState

    var body: some View {
        ZStack {
            // Camera preview
            CameraPreviewView(layer: vm.previewLayer)
                .ignoresSafeArea()

            // Card overlay
            CardOverlayView(cardRect: vm.cardOverlayRect, scanState: vm.scanState)
                .ignoresSafeArea()

            // Top bar
            VStack {
                HStack {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.yellow)
                    Text("PokeScan")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Spacer()
                    if !appState.activeShowName.isEmpty {
                        Text(appState.activeShowName)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                }
                .padding()
                .background(.ultraThinMaterial)
                Spacer()
            }

            // Undo banner (auto-confirm)
            if vm.undoAvailable, case .autoConfirmed(let match) = vm.scanState {
                VStack {
                    Spacer()
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Logged: \(match.name)")
                                .font(.subheadline).fontWeight(.semibold)
                            if let price = match.marketPrice {
                                Text(String(format: "$%.2f", price))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button("Undo") {
                            Task { await vm.undoLastLog() }
                        }
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundStyle(.red)
                    }
                    .padding()
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                    .padding(.bottom, 100)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(isPresented: Binding(
            get: {
                if case .awaitingConfirmation = vm.scanState { return true }
                return false
            },
            set: { if !$0 { vm.dismissAndReset() } }
        )) {
            if case .awaitingConfirmation(let match) = vm.scanState {
                ScanResultSheet(
                    match: match,
                    isAwaitingConfirmation: true,
                    onConfirm: { price, condition, status in
                        Task { await vm.confirmCard(match, price: price, condition: condition, status: status, sourceLocation: appState.activeShowName) }
                    },
                    onReject: { vm.dismissAndReset() }
                )
                .presentationDetents([.medium, .large])
            }
        }
        .sheet(isPresented: Binding(
            get: { if case .manualAssist = vm.scanState { return true }; return false },
            set: { if !$0 { vm.dismissAndReset() } }
        )) {
            if case .manualAssist(let ocrHint) = vm.scanState {
                ManualAssistView(ocrHint: ocrHint) { match in
                    Task { await vm.confirmCard(match, price: match.marketPrice, condition: "near_mint", status: "bought", sourceLocation: appState.activeShowName) }
                }
                .presentationDetents([.medium, .large])
            }
        }
        .task {
            await vm.startCamera()
        }
        .onDisappear {
            Task { await vm.stopCamera() }
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

// MARK: - Manual assist sheet
struct ManualAssistView: View {
    let ocrHint: String
    let onSelect: (CardMatch) -> Void

    @State private var searchText: String
    @State private var results: [CardSearchResult] = []
    @State private var isSearching = false

    private let network = NetworkService.shared

    init(ocrHint: String, onSelect: @escaping (CardMatch) -> Void) {
        self.ocrHint = ocrHint
        self.onSelect = onSelect
        _searchText = State(initialValue: ocrHint)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                        Text("Couldn't identify card")
                            .fontWeight(.semibold)
                    }
                    Text("OCR read: \"\(ocrHint)\" — correct it below")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()

                TextField("Search card name", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)
                    .onChange(of: searchText) { _, q in
                        Task { await search(q) }
                    }

                if isSearching {
                    ProgressView().padding()
                }

                List(results) { card in
                    Button {
                        onSelect(CardMatch(
                            cardId: card.id, name: card.name,
                            setName: card.setName, number: card.number,
                            imageUrlSm: card.imageUrlSm,
                            confidence: 1.0, marketPrice: nil, pipeline: "manual"
                        ))
                    } label: {
                        HStack {
                            if let url = card.imageUrlSm.flatMap(URL.init) {
                                AsyncImage(url: url) { img in img.resizable().aspectRatio(contentMode: .fit) }
                                    placeholder: { Color.secondary.opacity(0.2) }
                                    .frame(width: 40, height: 56)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                            VStack(alignment: .leading) {
                                Text(card.name).fontWeight(.medium)
                                if let set = card.setName { Text(set).font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Manual Search")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task { await search(ocrHint) }
    }

    private func search(_ query: String) async {
        guard query.count >= 2 else { results = []; return }
        isSearching = true
        do {
            struct Resp: Decodable { let results: [CardSearchResult] }
            let encodedQ = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
            let resp: Resp = try await network.request("/cards/search?q=\(encodedQ)&limit=10")
            results = resp.results
        } catch { results = [] }
        isSearching = false
    }
}
