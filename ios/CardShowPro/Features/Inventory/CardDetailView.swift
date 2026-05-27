import SwiftUI

/// Editable card detail. Tap any row in TransactionsView to land here.
/// Vendors can:
///   - Edit notes, condition, prices, source, payment method, counterparty
///   - Change the status (e.g. promote bought → sold)
///   - Delete the entry
struct CardDetailView: View {
    let item: LocalInventoryItem
    let vm: InventoryViewModel
    @Environment(\.dismiss) private var dismiss

    // Editable fields — populated from the item on .task
    @State private var status: String = "bought"
    @State private var condition: String = "near_mint"
    @State private var purchasePriceText: String = ""
    @State private var salePriceText: String = ""
    @State private var sourceLocation: String = ""
    @State private var paymentMethod: String = ""
    @State private var counterparty: String = ""
    @State private var notes: String = ""
    @State private var showDeleteConfirm = false
    @State private var showSellSheet = false
    @State private var receiptToast: ReceiptToast? = nil
    /// Loaded once on appear so the disk-backed UIImage isn't fetched on every
    /// keystroke in the price fields (each keystroke re-evaluates body).
    @State private var capturedImage: UIImage? = nil

    private enum ReceiptToast: Equatable {
        case saved, failed(String)
    }

    private let conditions = ["mint", "near_mint", "lightly_played", "moderately_played", "heavily_played", "damaged"]
    private let paymentMethods = ["", "Cash", "Venmo", "Zelle", "PayPal", "Card", "Trade"]
    private let statuses = ["bought", "sold", "traded"]

    var body: some View {
        ZStack {
            Theme.Colors.bg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: Theme.Spacing.md) {
                    heroImage
                    titleBlock
                    if status == "bought" || status == "holding" {
                        sellCTA
                    }
                    statusPicker
                    priceSection
                    detailsSection
                    notesSection
                }
                .padding(Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.xl)
            }
        }
        .navigationTitle(item.cardName ?? "Card")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.Colors.bg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") { save() }
                    .foregroundStyle(Theme.Colors.amber)
                    .fontWeight(.semibold)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Section("Receipt") {
                        Button {
                            saveReceipt(includeImage: true)
                        } label: {
                            Label("Save with card image", systemImage: "photo.fill.on.rectangle.fill")
                        }
                        Button {
                            saveReceipt(includeImage: false)
                        } label: {
                            Label("Save text only", systemImage: "doc.plaintext")
                        }
                    }
                    Section("Status") {
                        Button {
                            status = "sold"
                            save()
                        } label: {
                            Label("Mark as sold", systemImage: "tag.fill")
                        }
                        .disabled(status == "sold")
                        Button {
                            status = "traded"
                            save()
                        } label: {
                            Label("Mark as traded", systemImage: "arrow.left.arrow.right")
                        }
                        .disabled(status == "traded")
                    }
                    Section {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("Delete card", systemImage: "trash.fill")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(Theme.Colors.amber)
                }
            }
        }
        .overlay(alignment: .top) { receiptToastView }
        .confirmationDialog("Delete this card?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task {
                    await vm.delete(item: item)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showSellSheet) {
            // Reuses the existing SellSheet from InventoryRowComponents.swift.
            // On confirm, flips the SAME LocalInventoryItem from bought/holding
            // to sold — no duplicate row — and pops back so the user sees
            // the updated stock count.
            SellSheet(item: item) { price in
                InventoryService.shared.markSold(item: item, price: price)
                Task { await vm.load() }
                showSellSheet = false
                dismiss()
            }
            .presentationDetents([.medium])
            .presentationBackground(Theme.Colors.bg)
        }
        .onAppear {
            loadFromItem()
            capturedImage = CardImageStore.load(item.capturedImagePath)
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var heroImage: some View {
        // Prefer the live camera capture saved at scan time. Stock art is
        // the secondary fallback (only when no captured photo exists, e.g.
        // legacy entries or manual-search additions). The captured image is
        // loaded once into @State on appear so the disk-backed UIImage isn't
        // fetched on every keystroke as the price fields update.
        if let local = capturedImage {
            Image(uiImage: local)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 200, maxHeight: 280)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                .shadow(color: .black.opacity(0.5), radius: 24, y: 12)
        } else if let url = item.cardImageUrl.flatMap(URL.init) {
            CachedAsyncImage(url: url) { phase in
                switch phase {
                case .success(let img): img.resizable().aspectRatio(contentMode: .fit)
                default: Theme.Colors.surface
                }
            }
            .frame(maxWidth: 200, maxHeight: 280)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            .shadow(color: .black.opacity(0.5), radius: 24, y: 12)
        }
    }

    private var titleBlock: some View {
        VStack(spacing: Theme.Spacing.xs) {
            // Card name only — the scanner identifies the name, not the
            // specific printing/set, so we don't surface the API's guess.
            Text(item.cardName ?? item.cardId)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
                .multilineTextAlignment(.center)
            if let market = extractMarketPrice(from: item) {
                Text("MARKET · " + String(format: "$%.2f", market))
                    .font(Theme.Typography.label)
                    .tracking(1.5)
                    .foregroundStyle(Theme.Colors.amber)
                    .padding(.top, 4)
            }
        }
    }

    // MARK: - Sell CTA
    //
    // Big green button shown only when the card is still in stock (bought
    // or holding). Opens SellSheet → user enters the sale price → the
    // SAME inventory row flips status to "sold" and gains a salePrice.
    // Stock count drops by 1, no duplicate row created.

    private var sellCTA: some View {
        Button {
            showSellSheet = true
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "tag.fill")
                    .font(.system(size: 16, weight: .heavy))
                Text("SELL THIS CARD")
                    .font(Theme.Typography.title)
                    .tracking(2)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .opacity(0.6)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .padding(.horizontal, Theme.Spacing.lg)
            .background(Theme.Colors.green)
            .foregroundStyle(.black)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
            .shadow(color: Theme.Colors.green.opacity(0.3), radius: 12, y: 4)
        }
        .buttonStyle(.plain)
    }

    private var statusPicker: some View {
        sectionCard("STATUS") {
            HStack(spacing: 0) {
                ForEach(statuses, id: \.self) { s in
                    Button { status = s } label: {
                        Text(s.uppercased())
                            .font(Theme.Typography.label)
                            .tracking(1.5)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(status == s ? tint(for: s).opacity(0.2) : Color.clear)
                            .foregroundStyle(status == s ? tint(for: s) : Theme.Colors.textTertiary)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(status == s ? tint(for: s) : Color.clear, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(2)
                }
            }
        }
    }

    private var priceSection: some View {
        sectionCard("PRICES") {
            VStack(spacing: 8) {
                priceField(label: "PAID", value: $purchasePriceText, tint: Theme.Colors.blue)
                Divider().background(Theme.Colors.divider)
                priceField(label: "SOLD FOR", value: $salePriceText, tint: Theme.Colors.green)
            }
        }
    }

    private var detailsSection: some View {
        sectionCard("DETAILS") {
            VStack(spacing: 8) {
                Picker("Condition", selection: $condition) {
                    ForEach(conditions, id: \.self) { c in
                        Text(c.replacingOccurrences(of: "_", with: " ").capitalized).tag(c)
                    }
                }
                .pickerStyle(.menu)
                .tint(Theme.Colors.amber)

                Divider().background(Theme.Colors.divider)

                textField(label: "Source", text: $sourceLocation, placeholder: "e.g. GameStop Nationals")
                Divider().background(Theme.Colors.divider)
                textField(label: "Counterparty", text: $counterparty, placeholder: "who you bought from / sold to")
                Divider().background(Theme.Colors.divider)

                HStack {
                    Text("Payment")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Spacer()
                    Picker("Payment", selection: $paymentMethod) {
                        ForEach(paymentMethods, id: \.self) { p in
                            Text(p.isEmpty ? "—" : p).tag(p)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Theme.Colors.amber)
                }
            }
        }
    }

    private var notesSection: some View {
        sectionCard("NOTES") {
            ZStack(alignment: .topLeading) {
                if notes.isEmpty {
                    Text("Free-form notes — anything you want to remember")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .padding(.top, 8)
                        .padding(.leading, 4)
                }
                TextEditor(text: $notes)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 80)
            }
        }
    }

    // MARK: - Helpers

    private func tint(for status: String) -> Color {
        switch status {
        case "bought": return Theme.Colors.blue
        case "sold":   return Theme.Colors.green
        case "traded": return Theme.Colors.amber
        default:       return Theme.Colors.textSecondary
        }
    }

    @ViewBuilder
    private func sectionCard<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title)
                .font(Theme.Typography.label).tracking(1)
                .foregroundStyle(Theme.Colors.textTertiary)
                .padding(.horizontal, Theme.Spacing.sm)
            VStack { content() }
                .padding(Theme.Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.md)
                        .fill(Theme.Colors.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.md)
                                .stroke(Theme.Colors.border, lineWidth: 1)
                        )
                )
        }
    }

    private func priceField(label: String, value: Binding<String>, tint: Color) -> some View {
        HStack {
            Text(label).font(Theme.Typography.label).tracking(1)
                .foregroundStyle(Theme.Colors.textTertiary)
                .frame(width: 90, alignment: .leading)
            Spacer()
            Text("$").foregroundStyle(Theme.Colors.textSecondary)
            TextField("0.00", text: value)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 110)
                .font(Theme.Typography.priceMd)
                .foregroundStyle(tint)
        }
    }

    private func textField(label: String, text: Binding<String>, placeholder: String) -> some View {
        HStack {
            Text(label)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
            Spacer()
            TextField(placeholder, text: text)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(Theme.Colors.textPrimary)
                .font(Theme.Typography.body)
        }
    }

    // MARK: - Load / save

    private func loadFromItem() {
        status = item.status
        condition = item.condition
        purchasePriceText = item.purchasePrice.map { String(format: "%.2f", $0) } ?? ""
        salePriceText = item.salePrice.map { String(format: "%.2f", $0) } ?? ""
        sourceLocation = item.sourceLocation ?? ""
        paymentMethod = item.paymentMethod ?? ""
        counterparty = item.counterparty ?? ""
        notes = item.notes ?? ""
    }

    // MARK: - Receipt

    @ViewBuilder
    private var receiptToastView: some View {
        if let toast = receiptToast {
            let (label, icon, tint): (String, String, Color) = {
                switch toast {
                case .saved:        return ("RECEIPT SAVED TO PHOTOS", "checkmark.seal.fill", Theme.Colors.green)
                case .failed(let m): return (m.uppercased(), "exclamationmark.triangle.fill", Theme.Colors.red)
                }
            }()
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .heavy))
                Text(label)
                    .font(Theme.Typography.label)
                    .tracking(1.5)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.pill)
                    .fill(Theme.Colors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.pill)
                            .stroke(tint, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    )
            )
            .foregroundStyle(tint)
            .padding(.top, Theme.Spacing.sm)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private func saveReceipt(includeImage: Bool = true) {
        Task { @MainActor in
            do {
                _ = try await ReceiptExporter.save(item: item, includeImage: includeImage)
                withAnimation(.spring()) { receiptToast = .saved }
                try? await Task.sleep(for: .seconds(2))
                withAnimation { receiptToast = nil }
            } catch {
                withAnimation(.spring()) {
                    receiptToast = .failed("Save failed")
                }
                try? await Task.sleep(for: .seconds(2))
                withAnimation { receiptToast = nil }
            }
        }
    }

    private func save() {
        InventoryService.shared.update(
            item: item,
            status: status,
            condition: condition,
            purchasePrice: Double(purchasePriceText),
            salePrice: Double(salePriceText),
            notes: notes,
            sourceLocation: sourceLocation,
            paymentMethod: paymentMethod,
            counterparty: counterparty
        )
        Task { await vm.load() }
        dismiss()
    }
}
