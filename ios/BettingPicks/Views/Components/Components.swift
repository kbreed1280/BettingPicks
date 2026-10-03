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

extension Double {
    var profitColor: Color { self > 0 ? .green : self < 0 ? .red : .primary }
}
