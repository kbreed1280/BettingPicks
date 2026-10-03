import SwiftUI

struct StatTile: View {
    let title: String
    let value: String
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct StatusBadge: View {
    let status: BetStatus

    var body: some View {
        Text(status.displayName)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(color)
            .background(color.opacity(0.15), in: Capsule())
    }

    private var color: Color {
        switch status {
        case .won: .green
        case .lost: .red
        case .push, .void: .gray
        case .pending: .orange
        }
    }
}

struct LossLimitBanner: View {
    let message: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text("Loss limit reached").font(.subheadline.weight(.semibold))
                Text(message).font(.caption)
            }
        } icon: {
            Image(systemName: "exclamationmark.octagon.fill")
        }
        .foregroundStyle(.red)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// "LIVE  Q3 5:21   Memphis 14 – Charlotte 7"
struct LiveScoreBar: View {
    let live: LiveGameDTO
    let awayTeam: String
    let homeTeam: String

    var body: some View {
        HStack(spacing: 8) {
            if live.isLive {
                Text("LIVE").font(.caption2.weight(.heavy)).foregroundStyle(.white)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(.red, in: Capsule())
            }
            Text(live.detail).font(.caption.weight(.semibold)).foregroundStyle(live.isLive ? .red : .secondary)
            Spacer()
            if let a = live.awayScore, let h = live.homeScore {
                Text("\(short(awayTeam)) \(a) – \(short(homeTeam)) \(h)")
                    .font(.subheadline.weight(.bold).monospacedDigit())
            }
        }
    }

    /// "Florida Gators" -> "Florida"
    private func short(_ team: String) -> String {
        let words = team.split(separator: " ")
        return words.count > 1 ? words.dropLast().joined(separator: " ") : team
    }
}

/// "WINNING" / "LOSING" / "PUSH" while a bet's game is in progress.
struct LiveStatusBadge: View {
    let status: BetStatus

    var body: some View {
        let (text, color): (String, Color) = switch status {
        case .won: ("WINNING", .green)
        case .lost: ("LOSING", .red)
        case .push: ("PUSH", .gray)
        default: ("LIVE", .orange)
        }
        Text(text)
            .font(.caption2.weight(.heavy))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .foregroundStyle(.white)
            .background(color, in: Capsule())
    }
}

/// Live score lines under a bet: one for a straight bet, one per leg for a parlay.
struct LiveBetView: View {
    let info: LiveBetInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if info.isParlay {
                Text("\(info.winningLegs) of \(info.totalLegs) legs winning")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(info.current == .lost ? .red : .green)
            }
            ForEach(Array(info.legs.enumerated()), id: \.offset) { _, leg in
                HStack(spacing: 4) {
                    Image(systemName: icon(leg.status))
                        .foregroundStyle(color(leg.status))
                    if info.isParlay {
                        Text(leg.text.components(separatedBy: " (").first ?? leg.text).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Text(scoreText(leg.game)).monospacedDigit()
                        .foregroundStyle(leg.game.isLive ? .red : .secondary)
                }
                .font(.caption2)
            }
        }
        .padding(6)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 6))
    }

    private func scoreText(_ g: LiveGameDTO) -> String {
        guard g.state != "pre", let a = g.awayScore, let h = g.homeScore else {
            return g.startTime.formatted(date: .omitted, time: .shortened)
        }
        let short = { (t: String) in t.split(separator: " ").dropLast().joined(separator: " ") }
        return "\(short(g.awayTeam)) \(a)–\(h) \(short(g.homeTeam)) · \(g.detail)"
    }

    private func icon(_ s: BetStatus) -> String {
        switch s {
        case .won: "checkmark.circle.fill"
        case .lost: "xmark.circle.fill"
        case .push: "equal.circle.fill"
        default: "clock"
        }
    }

    private func color(_ s: BetStatus) -> Color {
        switch s {
        case .won: .green
        case .lost: .red
        default: .secondary
        }
    }
}

extension Double {
    var profitColor: Color { self > 0 ? .green : self < 0 ? .red : .primary }
}
