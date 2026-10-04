import SwiftData
import SwiftUI

/// "AI vs You" scoreboard: every AI pick (graded at a flat 1 unit, whether you bet it or not)
/// next to your own settled bets.
struct AIvsYouCard: View {
    let picks: [AIPick]
    let bets: [Bet]

    var body: some View {
        let ai = BetStats(picks: picks)
        let you = BetStats(bets: bets)
        let followed = BetStats(bets: bets.filter(\.isAIPick))

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("AI vs You").font(.headline)
                Spacer()
                NavigationLink {
                    PickHistoryView()
                } label: {
                    Text("AI track record").font(.caption.weight(.semibold))
                }
            }

            HStack(alignment: .top, spacing: 12) {
                column(title: "AI picks", icon: "sparkles", tint: .accentColor, stats: ai,
                       roiNote: "1 unit each", leading: leader(ai, you) == .ai)
                column(title: "You", icon: "person.fill", tint: .blue, stats: you,
                       roiNote: Format.money(you.profit, signed: true), leading: leader(ai, you) == .you)
            }

            if followed.settledCount > 0 {
                Label("AI picks you bet: \(followed.record) · \(Format.money(followed.profit, signed: true))",
                      systemImage: "arrow.triangle.branch")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if ai.settledCount + you.settledCount == 0 {
                Text("Fills in as games finish. AI picks are graded automatically from final scores.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if ai.pending > 0 {
                Text("\(ai.pending) AI pick\(ai.pending == 1 ? "" : "s") still in play.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private enum Leader { case ai, you, tie }

    /// Ahead = better win rate (needs at least 3 settled each to call it).
    private func leader(_ ai: BetStats, _ you: BetStats) -> Leader {
        guard ai.wins + ai.losses >= 3, you.wins + you.losses >= 3 else { return .tie }
        if abs(ai.winRate - you.winRate) < 0.005 { return .tie }
        return ai.winRate > you.winRate ? .ai : .you
    }

    private func column(title: String, icon: String, tint: Color, stats: BetStats, roiNote: String, leading: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Label(title, systemImage: icon).font(.caption.weight(.semibold)).foregroundStyle(tint)
                if leading { Image(systemName: "crown.fill").font(.caption2).foregroundStyle(.yellow) }
            }
            Text(stats.wins + stats.losses > 0 ? Format.percent(stats.winRate, digits: 0) : "—")
                .font(.title.weight(.bold).monospacedDigit())
            Text("win rate").font(.caption2).foregroundStyle(.secondary)
            Divider()
            row("Record", stats.settledCount > 0 ? stats.record : "0-0")
            row("ROI", stats.staked > 0 ? Format.percent(stats.roi, signed: true) : "—", tint: stats.roi.profitColor)
            row(stats.staked > 0 && title == "AI picks" ? "Units" : "Profit",
                title == "AI picks" ? Format.units(stats.profit) : roiNote,
                tint: stats.profit.profitColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(leading ? Color.yellow.opacity(0.6) : .clear, lineWidth: 1.5))
    }

    private func row(_ label: String, _ value: String, tint: Color = .primary) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(tint)
        }
    }
}
