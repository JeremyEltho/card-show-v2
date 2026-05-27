import SwiftUI

/// Root view. Three big action buttons — Log, History, Profile.
/// Convention-booth aesthetic: felt-green table surface, card-back pattern,
/// holographic shimmer on the primary LOG action.
struct HomeView: View {
    @Environment(AppState.self) private var appState
    @State private var settings = AppSettings.shared
    @State private var todaySummary: InventoryService.TodaySummary?
    @State private var stockCount: Int = 0
    @State private var recentItems: [LocalInventoryItem] = []
    @State private var topHoldings: [LocalInventoryItem] = []
    @State private var showSettings = false
    @State private var searchText: String = ""
    @State private var navigateToSearch: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.bg.ignoresSafeArea()

                // Subtle card-back swirl pattern — table-felt energy without
                // shouting. Sits behind everything else.
                CardBackPattern()
                    .ignoresSafeArea()

                // Faded pokeball watermark on top of the felt — unmistakable
                // pokemon vibes without competing with foreground content.
                PokeballPattern()
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: Theme.Spacing.lg) {
                        header
                        searchBar
                        todayDashboard
                        if settings.dailyTarget > 0 { dailyTargetSection }
                        logCardSection
                        if !recentItems.isEmpty { recentScansSection }
                        if !topHoldings.isEmpty { topHoldingsSection }
                        historyRow
                        stockSnapshot
                        Spacer(minLength: 24)
                    }
                    .padding(Theme.Spacing.lg)
                }
                .refreshable { await refresh() }
            }
            // Programmatic destination driven by the search bar's submit.
            .navigationDestination(isPresented: $navigateToSearch) {
                TransactionsView(initialSearch: searchText)
            }
            .navigationBarHidden(true)
        }
        .preferredColorScheme(.dark)
        // .onAppear fires every time HomeView becomes visible (including
        // after popping back from the scanner / settings sheet / detail
        // screens). .task only fires on initial mount, which left the
        // dashboard stale after a scan-and-sell.
        .onAppear { Task { await refresh() } }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .onDisappear { Task { await refresh() } }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: Theme.Spacing.sm) {
            HStack(spacing: 10) {
                // Pokeball mark — drawn in SwiftUI, no asset dependency.
                PokeballMark(size: 34, rotation: -8)

                VStack(alignment: .leading, spacing: 0) {
                    Text("CARDSHOW")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .tracking(4)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text("PRO · est. 2026")
                        .font(.system(size: 9, weight: .heavy, design: .serif))
                        .italic()
                        .tracking(2)
                        .foregroundStyle(Theme.Colors.amber)
                }
                Spacer()

                // Settings entry point — kebab gives a quick menu (Settings,
                // toggle active show), tap-and-hold opens settings directly.
                Menu {
                    Button {
                        showSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape.fill")
                    }
                    if !settings.activeShowName.isEmpty {
                        Button(role: .destructive) {
                            settings.activeShowName = ""
                        } label: {
                            Label("Stop \"\(settings.activeShowName)\"", systemImage: "stop.circle")
                        }
                    }
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(width: 36, height: 36)
                        .background(
                            Circle()
                                .fill(Theme.Colors.surface)
                                .overlay(Circle().stroke(Theme.Colors.border, lineWidth: 1))
                        )
                }
                .menuOrder(.fixed)
            }
            if !settings.activeShowName.isEmpty {
                conventionBadge(settings.activeShowName)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.top, 32)
        .padding(.bottom, Theme.Spacing.md)
    }

    // Live "convention badge" — looks like a name tag on a lanyard
    private func conventionBadge(_ name: String) -> some View {
        HStack(spacing: 8) {
            // Pulsing red "LIVE" dot
            ZStack {
                Circle().fill(Theme.Colors.red).frame(width: 8, height: 8)
                Circle().stroke(Theme.Colors.red.opacity(0.4), lineWidth: 4)
                    .frame(width: 8, height: 8).scaleEffect(2).opacity(0.3)
            }
            Text("LIVE AT")
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .tracking(2)
                .foregroundStyle(Theme.Colors.red)
            Text(name.uppercased())
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(1.5)
                .foregroundStyle(Theme.Colors.textPrimary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Theme.Colors.parchment)
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(Color.black.opacity(0.8),
                                style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                        .padding(3)
                )
        )
        .overlay(alignment: .top) {
            // tiny lanyard punch-hole
            Circle()
                .fill(Theme.Colors.bg)
                .frame(width: 6, height: 6)
                .offset(y: -3)
        }
        .foregroundStyle(.black)
        .rotationEffect(.degrees(-1.5))
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(Theme.Colors.textTertiary)
            TextField("Search your inventory", text: $searchText)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textPrimary)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .onSubmit {
                    guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    navigateToSearch = true
                }
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(Theme.Colors.surface)
                .overlay(
                    Capsule().stroke(Theme.Colors.border, lineWidth: 1)
                )
        )
    }

    // MARK: - Daily target progress
    //
    // Horizontal progress bar driven by today's NET vs the configured
    // settings.dailyTarget. Tap to open Settings (target lives under
    // SCAN DEFAULTS).

    private var dailyTargetSection: some View {
        let net = todaySummary?.net ?? 0
        let target = settings.dailyTarget
        let progress = max(0, min(net / target, 1))
        let pct = Int((net / target * 100).rounded())
        let bgTint: Color = net >= target
            ? Theme.Colors.green
            : (net >= 0 ? Theme.Colors.amber : Theme.Colors.red)

        return Button {
            showSettings = true
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("DAILY TARGET")
                        .font(Theme.Typography.label)
                        .tracking(2)
                        .foregroundStyle(Theme.Colors.textTertiary)
                    Spacer()
                    Text("\(pct)%")
                        .font(Theme.Typography.priceSm)
                        .foregroundStyle(bgTint)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Theme.Colors.surfaceHi)
                        Capsule()
                            .fill(bgTint)
                            .frame(width: max(8, geo.size.width * progress))
                    }
                }
                .frame(height: 10)
                HStack(spacing: 4) {
                    Text(net >= 0
                         ? String(format: "+$%.0f", net)
                         : String(format: "−$%.0f", abs(net)))
                        .font(Theme.Typography.priceSm)
                        .foregroundStyle(bgTint)
                    Text("of")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                    Text(String(format: "$%.0f", target))
                        .font(Theme.Typography.priceSm)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Spacer()
                    if net >= target {
                        Text("✓ HIT")
                            .font(Theme.Typography.label)
                            .tracking(1.5)
                            .foregroundStyle(Theme.Colors.green)
                    }
                }
            }
            .padding(Theme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .fill(Theme.Colors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                            .stroke(Theme.Colors.border, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - TOP HOLDINGS — top 3 by market/purchase value

    private var topHoldingsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Text("TOP HOLDINGS")
                    .font(Theme.Typography.label)
                    .tracking(2)
                    .foregroundStyle(Theme.Colors.textTertiary)
                Spacer()
                NavigationLink(destination: TransactionsView()) {
                    Text("ALL ›")
                        .font(Theme.Typography.label)
                        .tracking(1.5)
                        .foregroundStyle(Theme.Colors.amber)
                }
                .buttonStyle(.plain)
            }
            VStack(spacing: 6) {
                ForEach(Array(topHoldings.enumerated()), id: \.element.id) { idx, item in
                    TopHoldingRow(rank: idx + 1, item: item)
                    if idx < topHoldings.count - 1 {
                        Divider().background(Theme.Colors.divider)
                    }
                }
            }
            .padding(Theme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .fill(Theme.Colors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                            .stroke(Theme.Colors.border, lineWidth: 1)
                    )
            )
        }
    }

    // MARK: - TODAY dashboard
    //
    // Always-visible stats strip. Shows the live day's BUYS / SELLS / NET in
    // monospaced numerics. With no activity yet, renders as dashes so the
    // section's shape is consistent across launches.

    private var todayDashboard: some View {
        let s = todaySummary
        return ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text("TODAY")
                        .font(Theme.Typography.label)
                        .tracking(2)
                        .foregroundStyle(Theme.Colors.textTertiary)
                    Text("·")
                        .font(Theme.Typography.label)
                        .foregroundStyle(Theme.Colors.textTertiary)
                    Text(Self.dateLabel())
                        .font(Theme.Typography.captionMono)
                        .foregroundStyle(Theme.Colors.textTertiary)
                    Spacer()
                    if let s, (s.cardsIn + s.cardsOut) > 0 {
                        Text("\(s.cardsIn + s.cardsOut) CARDS")
                            .font(Theme.Typography.label)
                            .tracking(1.2)
                            .foregroundStyle(Theme.Colors.amber)
                    }
                }

                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    dashStat("BUYS",
                             value: s?.buys ?? 0,
                             count: s?.cardsIn ?? 0,
                             tint: Theme.Colors.blue,
                             hasData: (s?.cardsIn ?? 0) > 0)
                    Rectangle().fill(Theme.Colors.divider).frame(width: 1, height: 36)
                    dashStat("SELLS",
                             value: s?.sells ?? 0,
                             count: s?.cardsOut ?? 0,
                             tint: Theme.Colors.green,
                             hasData: (s?.cardsOut ?? 0) > 0)
                    Rectangle().fill(Theme.Colors.divider).frame(width: 1, height: 36)
                    dashStat("NET",
                             value: s?.net ?? 0,
                             count: nil,
                             tint: ((s?.net ?? 0) >= 0) ? Theme.Colors.green : Theme.Colors.red,
                             hasData: s != nil && (s!.cardsIn + s!.cardsOut) > 0,
                             signed: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.lg)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .fill(Theme.Colors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                            .stroke(Theme.Colors.border, lineWidth: 1)
                    )
            )

            // Sticker price tag when the day has a meaningful net.
            if let s, s.net != 0 {
                PriceTag(amount: abs(s.net),
                         caption: s.net >= 0 ? "NET +" : "NET −",
                         size: 64,
                         rotation: -8)
                    .offset(x: 6, y: -16)
            }
        }
    }

    private func dashStat(_ label: String,
                          value: Double,
                          count: Int?,
                          tint: Color,
                          hasData: Bool,
                          signed: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(Theme.Typography.label).tracking(1)
                .foregroundStyle(Theme.Colors.textTertiary)
            Text(hasData
                 ? (signed
                    ? (value >= 0 ? "+" : "−") + String(format: "$%.0f", abs(value))
                    : String(format: "$%.0f", value))
                 : "—")
                .font(Theme.Typography.priceLg)
                .foregroundStyle(hasData ? tint : Theme.Colors.textTertiary)
            if let count {
                Text(hasData ? "\(count) card\(count == 1 ? "" : "s")" : "—")
                    .font(Theme.Typography.captionMono)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
    }

    // MARK: - LOG hero + HISTORY row

    private var logCardSection: some View {
        NavigationLink(destination: LogActionPickerView()) {
            LogHeroButton()
        }
        .buttonStyle(.plain)
    }

    private var historyRow: some View {
        NavigationLink(destination: TransactionsView()) {
            ActionRow(
                title: "HISTORY",
                subtitle: historySubtitle,
                icon: "list.bullet.rectangle.portrait.fill",
                tint: Theme.Colors.blue
            )
        }
        .buttonStyle(.plain)
    }

    private var historySubtitle: String {
        guard let s = todaySummary else { return "Tap to view all transactions" }
        if s.cardsIn == 0 && s.cardsOut == 0 { return "No activity yet" }
        return "\(s.cardsIn + s.cardsOut) today · " + (s.net >= 0
            ? String(format: "+$%.0f net", s.net)
            : String(format: "−$%.0f net", abs(s.net)))
    }

    // MARK: - RECENT SCANS — horizontal carousel of last 5 logged items

    private var recentScansSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Text("RECENT SCANS")
                    .font(Theme.Typography.label)
                    .tracking(2)
                    .foregroundStyle(Theme.Colors.textTertiary)
                Spacer()
                NavigationLink(destination: TransactionsView()) {
                    Text("ALL ›")
                        .font(Theme.Typography.label)
                        .tracking(1.5)
                        .foregroundStyle(Theme.Colors.amber)
                }
                .buttonStyle(.plain)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.sm) {
                    ForEach(recentItems) { item in
                        NavigationLink(destination: CardDetailView(item: item, vm: InventoryViewModel())) {
                            RecentScanTile(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - STOCK SNAPSHOT

    private var stockSnapshot: some View {
        HStack(spacing: Theme.Spacing.md) {
            statTile(
                label: "IN STOCK",
                value: "\(stockCount)",
                subLabel: stockCount == 1 ? "card" : "cards",
                tint: Theme.Colors.amber
            )
            statTile(
                label: "ALL-TIME NET",
                value: allTimeNetString,
                subLabel: allTimeNetSub,
                tint: (todaySummary?.allTimeNet ?? 0) >= 0 ? Theme.Colors.green : Theme.Colors.red
            )
        }
    }

    private var allTimeNetString: String {
        guard let s = todaySummary else { return "—" }
        return (s.allTimeNet >= 0 ? "+$" : "−$") + String(format: "%.0f", abs(s.allTimeNet))
    }

    private var allTimeNetSub: String {
        guard let s = todaySummary else { return "" }
        return s.allTimeNet >= 0 ? "lifetime up" : "lifetime down"
    }

    private func statTile(label: String, value: String, subLabel: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(Theme.Typography.label)
                .tracking(1.2)
                .foregroundStyle(Theme.Colors.textTertiary)
            Text(value)
                .font(Theme.Typography.priceLg)
                .foregroundStyle(tint)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(subLabel)
                .font(Theme.Typography.captionMono)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .fill(Theme.Colors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .stroke(Theme.Colors.border, lineWidth: 1)
                )
        )
    }

    // MARK: - Data

    private func refresh() async {
        // Single fetchAll round-trip — partition in Swift instead of paying
        // two SwiftData queries. Items are already sorted by acquiredAt desc.
        let all = InventoryService.shared.fetchAll()
        todaySummary = InventoryService.shared.summary()
        recentItems = Array(all.prefix(5))
        let stock = all.filter { $0.status == "bought" }
        stockCount = stock.count
        // Top holdings by best-known value: prefer marketPrice (from API),
        // fall back to purchasePrice (what the vendor paid).
        topHoldings = Array(
            stock.sorted { lhs, rhs in
                let l = lhs.marketPrice ?? lhs.purchasePrice ?? 0
                let r = rhs.marketPrice ?? rhs.purchasePrice ?? 0
                return l > r
            }
            .prefix(3)
        )
    }

    /// Static DateFormatter — building one per render was unnecessarily
    /// expensive. DateFormatters are heavyweight to construct.
    private static let dashboardDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    private static func dateLabel() -> String {
        dashboardDateFormatter.string(from: Date()).uppercased()
    }
}

// MARK: - TopHoldingRow — one row in the "top holdings" list

private struct TopHoldingRow: View {
    let rank: Int
    let item: LocalInventoryItem

    private var value: Double {
        item.marketPrice ?? item.purchasePrice ?? 0
    }

    var body: some View {
        NavigationLink(destination: CardDetailView(item: item, vm: InventoryViewModel())) {
            HStack(spacing: Theme.Spacing.sm) {
                Text("#\(rank)")
                    .font(.system(size: 12, weight: .black, design: .monospaced))
                    .foregroundStyle(Theme.Colors.amber)
                    .frame(width: 22, alignment: .leading)

                thumbnail
                    .frame(width: 30, height: 42)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                VStack(alignment: .leading, spacing: 1) {
                    Text(item.cardName ?? "Card")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .tracking(0.3)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)
                    Text(item.condition.replacingOccurrences(of: "_", with: " ").uppercased())
                        .font(.system(size: 9, weight: .heavy, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }

                Spacer(minLength: 0)

                Text(String(format: "$%.0f", value))
                    .font(Theme.Typography.priceMd)
                    .foregroundStyle(Theme.Colors.green)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let local = CardImageStore.load(item.capturedImagePath) {
            Image(uiImage: local).resizable().aspectRatio(contentMode: .fill)
        } else if let urlStr = item.cardImageUrl, let url = URL(string: urlStr) {
            CachedAsyncImage(url: url) { phase in
                switch phase {
                case .success(let img): img.resizable().aspectRatio(contentMode: .fill)
                default: Theme.Colors.surface
                }
            }
        } else {
            Theme.Colors.surface
        }
    }
}

// MARK: - RecentScanTile — mini card for the recent-scans carousel

private struct RecentScanTile: View {
    let item: LocalInventoryItem

    private var tint: Color {
        switch item.status {
        case "sold":   return Theme.Colors.green
        case "traded": return Theme.Colors.amber
        default:       return Theme.Colors.blue
        }
    }

    private var displayPrice: Double? {
        item.status == "sold" ? (item.salePrice ?? item.purchasePrice) : item.purchasePrice
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            tileImage
                .frame(width: 96, height: 134)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.sm)
                        .stroke(tint.opacity(0.5), lineWidth: 1.5)
                )

            Text(item.cardName ?? "Card")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(0.5)
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)

            HStack(spacing: 4) {
                StatusPill(status: item.status)
                Spacer(minLength: 0)
                if let price = displayPrice {
                    Text(String(format: "$%.0f", price))
                        .font(Theme.Typography.priceSm)
                        .foregroundStyle(tint)
                }
            }
        }
        .frame(width: 96)
    }

    @ViewBuilder
    private var tileImage: some View {
        if let local = CardImageStore.load(item.capturedImagePath) {
            Image(uiImage: local)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else if let urlStr = item.cardImageUrl, let url = URL(string: urlStr) {
            CachedAsyncImage(url: url) { phase in
                switch phase {
                case .success(let img): img.resizable().aspectRatio(contentMode: .fill)
                default: Theme.Colors.surface
                }
            }
        } else {
            Theme.Colors.surface
        }
    }
}

// MARK: - LogHeroButton — Pokemon HOLO RARE card
//
// Whole button is styled as a vintage Pokemon TCG card laid flat on the
// table: yellow border, cream face, illustration window with foil shimmer,
// attack-list-style footer.

struct LogHeroButton: View {
    var body: some View {
        PokemonCardFrame(
            title: "SCAN A CARD",
            rarity: "★ HOLO RARE",
            isHolo: true,
            rotation: -1.8
        ) {
            // Illustration window — viewfinder over rainbow holo gradient.
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.18))
                    .frame(width: 90, height: 90)
                Image(systemName: "viewfinder")
                    .font(.system(size: 48, weight: .heavy))
                    .foregroundStyle(Color.white)
                    .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
            }
        } footer: {
            HStack(spacing: 6) {
                Text("ATTACK")
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .tracking(1.5)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(Color.black)
                    .foregroundStyle(Theme.Colors.amber)
                Text("BUY · SELL · TRADE")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(Color.black.opacity(0.8))
                Spacer()
                Text("∞")
                    .font(.system(size: 14, weight: .black, design: .monospaced))
                    .foregroundStyle(Color.black.opacity(0.7))
            }
        }
    }
}

// MARK: - ActionRow — Pokemon BASIC card
//
// Same card framing, no holo shimmer. Used for HISTORY (and any future
// non-primary entry point).

struct ActionRow: View {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color

    var body: some View {
        PokemonCardFrame(
            title: title,
            rarity: "☆ BASIC",
            isHolo: false,
            rotation: 1.2
        ) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.25))
                    .frame(width: 76, height: 76)
                Image(systemName: icon)
                    .font(.system(size: 36, weight: .heavy))
                    .foregroundStyle(Color.white)
                    .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
            }
        } footer: {
            HStack(spacing: 6) {
                Text("INFO")
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .tracking(1.5)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(Color.black)
                    .foregroundStyle(tint)
                Text(subtitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.7))
                    .lineLimit(1)
                Spacer()
            }
        }
    }
}

// Keep the old ActionButton name compiling (used elsewhere if referenced).
// Forwards to ActionRow as a compatibility shim.
struct ActionButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let background: Color
    let foreground: Color
    let isPrimary: Bool

    var body: some View {
        ActionRow(title: title, subtitle: subtitle, icon: icon,
                  tint: isPrimary ? Theme.Colors.amber : Theme.Colors.blue)
    }
}
