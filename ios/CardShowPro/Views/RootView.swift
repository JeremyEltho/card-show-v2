import SwiftUI
import UIKit

struct RootView: View {
    @State private var selectedTab = 0

    init() {
        Self.configureAppearance()
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            ScannerView()
                .tabItem { Label("Scan", systemImage: "viewfinder") }
                .tag(0)

            StockListView()
                .tabItem { Label("Stock", systemImage: "tray.full.fill") }
                .tag(1)

            TodayView()
                .tabItem { Label("Today", systemImage: "chart.bar.fill") }
                .tag(2)
        }
        .tint(Theme.Colors.amber)
    }

    /// Configure tab bar + nav bar for the premium-dark theme.
    private static func configureAppearance() {
        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = UIColor(Theme.Colors.bg)
        tab.shadowColor = UIColor(Theme.Colors.border)

        let item = UITabBarItemAppearance()
        item.normal.iconColor = UIColor(Theme.Colors.textTertiary)
        item.normal.titleTextAttributes = [
            .foregroundColor: UIColor(Theme.Colors.textTertiary),
            .font: UIFont.systemFont(ofSize: 10, weight: .semibold)
        ]
        item.selected.iconColor = UIColor(Theme.Colors.amber)
        item.selected.titleTextAttributes = [
            .foregroundColor: UIColor(Theme.Colors.amber),
            .font: UIFont.systemFont(ofSize: 10, weight: .heavy)
        ]
        tab.stackedLayoutAppearance = item
        tab.inlineLayoutAppearance = item
        tab.compactInlineLayoutAppearance = item
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab

        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = UIColor(Theme.Colors.bg)
        nav.titleTextAttributes = [.foregroundColor: UIColor.white]
        nav.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
        nav.shadowColor = .clear
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
    }
}
