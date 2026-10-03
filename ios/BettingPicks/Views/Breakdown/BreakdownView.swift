import SwiftData
import SwiftUI

/// Where you actually make (or lose) money.
struct BreakdownView: View {
    @Query private var bets: [Bet]
    @Query private var picks: [AIPick]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    row("Your own picks", BetStats(bets: bets.filter { !$0.isAIPick }))
                    row("AI picks you bet", BetStats(bets: bets.filter(\.isAIPick)))
                    row("All AI picks (1u flat)", BetStats(picks: picks), unitsOnly: true)
                } header: {
                    Text("AI vs. you")
                } footer: {
                    Text("The last row grades every AI pick at 1 unit, even ones you skipped, so you can tell whether the AI is helping.")
                }

                group("By sport", key: \.sport)
                group("By bet type") { $0.betType.displayName }
                Section("By odds range") {
                    ForEach(OddsRange.allCases, id: \.self) { range in
                        let subset = bets.filter { OddsRange(odds: $0.odds) == range }
                        if !subset.isEmpty { row(range.rawValue, BetStats(bets: subset)) }
                    }
                }
                group("By sportsbook", key: \.sportsbook)
            }
            .overlay {
                if bets.isEmpty && picks.isEmpty {
                    ContentUnavailableView("Nothing to break down yet", systemImage: "chart.bar",
                                           description: Text("Settle some bets to see where you win."))
                }
            }
            .navigationTitle("Breakdown")
        }
    }

    @ViewBuilder
    private func group(_ title: String, key: @escaping (Bet) -> String) -> some View {
        let grouped = Dictionary(grouping: bets, by: key)
        if !grouped.isEmpty {
            Section(title) {
                ForEach(grouped.keys.sorted(), id: \.self) { name in
                    row(name, BetStats(bets: grouped[name] ?? []))
                }
            }
        }
    }

    private func row(_ title: String, _ s: BetStats, unitsOnly: Bool = false) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text("\(s.record)  ·  \(s.wins + s.losses > 0 ? Format.percent(s.winRate, digits: 0) : "—") win")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(unitsOnly ? Format.units(s.profit) : Format.money(s.profit, signed: true))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(s.profit.profitColor)
                Text("ROI \(s.staked > 0 ? Format.percent(s.roi, signed: true) : "—")")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
    }
}
