import SwiftUI

/// Root view. Three big action buttons — Log, History, Profile.
/// Replaces the previous Scan / Stock / Today tab bar.
struct HomeView: View {
    @Environment(AppState.self) private var appState
    @State private var todaySummary: InventoryService.TodaySummary?
    @State private var stockCount: Int = 0

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.bg.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: Theme.Spacing.lg) {
                        header
                        actionButtons
                        Spacer(minLength: 24)
                    }
                    .padding(Theme.Spacing.lg)
                }
            }
            .navigationBarHidden(true)
        }
        .preferredColorScheme(.dark)
        .task { await refresh() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: Theme.Spacing.sm) {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.dashed.badge.record")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.Colors.amber)
                Text("CARDSHOW PRO")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .tracking(3)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
            }
            if !appState.activeShowName.isEmpty {
                HStack(spacing: 6) {
                    Circle().fill(Theme.Colors.green).frame(width: 6, height: 6)
                    Text("LIVE · \(appState.activeShowName.uppercased())")
                        .font(Theme.Typography.label)
                        .tracking(1.5)
                        .foregroundStyle(Theme.Colors.green)
                    Spacer()
                }
            }
        }
        .padding(.top, 32)
        .padding(.bottom, Theme.Spacing.md)
    }

    // MARK: - Buttons

    private var actionButtons: some View {
        VStack(spacing: Theme.Spacing.md) {
            // LOG — primary amber, largest
            NavigationLink(destination: LogActionPickerView()) {
                ActionButton(
                    title: "LOG",
                    subtitle: "Scan a card to buy, sell, or trade",
                    icon: "viewfinder",
                    background: Theme.Colors.amber,
                    foreground: .black,
                    isPrimary: true
                )
            }

            // HISTORY — secondary
            NavigationLink(destination: TransactionsView()) {
                ActionButton(
                    title: "HISTORY",
                    subtitle: historySubtitle,
                    icon: "list.bullet.rectangle.fill",
                    background: Theme.Colors.surface,
                    foreground: Theme.Colors.textPrimary,
                    isPrimary: false
                )
            }

            // PROFILE — secondary
            NavigationLink(destination: ProfileView()) {
                ActionButton(
                    title: "PROFILE",
                    subtitle: profileSubtitle,
                    icon: "person.crop.circle.fill",
                    background: Theme.Colors.surface,
                    foreground: Theme.Colors.textPrimary,
                    isPrimary: false
                )
            }
        }
    }

    private var historySubtitle: String {
        guard let s = todaySummary else { return "Loading…" }
        if s.cardsIn == 0 && s.cardsOut == 0 { return "No activity yet" }
        return "\(s.cardsIn + s.cardsOut) today · " + (s.net >= 0
            ? String(format: "+$%.0f net", s.net)
            : String(format: "-$%.0f net", abs(s.net)))
    }

    private var profileSubtitle: String {
        if appState.activeShowName.isEmpty {
            return "Set your show name + view stats"
        }
        return "\(stockCount) in stock"
    }

    private func refresh() async {
        todaySummary = await MainActor.run { InventoryService.shared.summary() }
        stockCount = await MainActor.run {
            InventoryService.shared.fetchAll(status: "bought").count
        }
    }
}

// MARK: - Reusable action button

struct ActionButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let background: Color
    let foreground: Color
    let isPrimary: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: isPrimary ? 36 : 28, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: isPrimary ? 28 : 20, weight: .heavy, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(foreground)
                Text(subtitle)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(foreground.opacity(0.75))
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(foreground.opacity(0.5))
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, isPrimary ? 28 : 22)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .fill(background)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                        .stroke(isPrimary ? .clear : Theme.Colors.border, lineWidth: 1)
                )
        )
    }
}
