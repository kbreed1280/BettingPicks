import Foundation
import Observation

struct LiveGameDTO: Decodable, Hashable {
    let sportKey: String
    let homeTeam: String
    let awayTeam: String
    let homeScore: Int?
    let awayScore: Int?
    /// "pre", "in" or "post"
    let state: String
    /// e.g. "Q3 5:21", "Halftime", "Final"
    let detail: String
    let startTime: Date
    let possession: String?

    var isLive: Bool { state == "in" }
    var isFinal: Bool { state == "post" }
}

enum TeamName {
    /// "Miami (OH) RedHawks" -> "miamiohredhawks"
    static func normalize(_ name: String) -> String {
        name.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// Odds API and ESPN names usually match exactly; fall back to one containing the other.
    static func same(_ a: String, _ b: String) -> Bool {
        let x = normalize(a), y = normalize(b)
        return x == y || (min(x.count, y.count) >= 5 && (x.contains(y) || y.contains(x)))
    }
}

/// Live/final scores (ESPN via the backend). Free: doesn't use Odds API quota.
@MainActor
@Observable
final class LiveScores {
    private(set) var games: [LiveGameDTO] = []
    private(set) var updatedAt: Date?

    func game(home: String, away: String) -> LiveGameDTO? {
        games.first { TeamName.same($0.homeTeam, home) && TeamName.same($0.awayTeam, away) }
            ?? games.first { TeamName.same($0.homeTeam, away) && TeamName.same($0.awayTeam, home) } // neutral-site flips
    }

    func refresh(sports: [String], days: [Date]) async {
        guard !sports.isEmpty, !days.isEmpty else { return }
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        // ESPN keys games by US Eastern date.
        f.timeZone = TimeZone(identifier: "America/New_York")
        let dates = Array(Set(days.map { f.string(from: $0.addingTimeInterval(12 * 3600)) })).sorted().prefix(7)
        if let fresh: [LiveGameDTO] = try? await APIClient().get("/live", query: [
            .init(name: "sports", value: sports.joined(separator: ",")),
            .init(name: "dates", value: dates.joined(separator: ",")),
        ]) {
            games = fresh
            updatedAt = .now
        }
    }

    /// Refreshes every 30s while the calling view is on screen (cancelled with the view's task).
    func poll(sports: [String], days: [Date]) async {
        while !Task.isCancelled {
            await refresh(sports: sports, days: days)
            let anyLive = games.contains { $0.isLive }
            try? await Task.sleep(for: .seconds(anyLive ? 30 : 120))
        }
    }
}
