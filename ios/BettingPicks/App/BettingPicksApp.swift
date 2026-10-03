import SwiftData
import SwiftUI

@main
struct BettingPicksApp: App {
    @State private var pickStore = PickStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(pickStore)
        }
        .modelContainer(for: [Bet.self, AIPick.self])
    }
}

struct RootView: View {
    /// Remembers the last tab you were on.
    @AppStorage("selectedTab") private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView()
                .tabItem { Label("Dashboard", systemImage: "chart.line.uptrend.xyaxis") }.tag(0)
            BetListView()
                .tabItem { Label("Bets", systemImage: "list.bullet.rectangle") }.tag(1)
            PicksView()
                .tabItem { Label("AI Picks", systemImage: "sparkles") }.tag(2)
            BreakdownView()
                .tabItem { Label("Breakdown", systemImage: "chart.bar.xaxis") }.tag(3)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }.tag(4)
        }
    }
}
