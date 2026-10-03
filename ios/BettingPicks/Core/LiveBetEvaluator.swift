import Foundation

/// How one bet (or parlay leg) stands right now against a live/final score.
struct LegStatus: Equatable {
    let text: String
    let game: LiveGameDTO
    /// .won = currently winning, .lost = currently losing, .push = on the number
    let status: BetStatus
}

struct LiveBetInfo: Equatable {
    /// Straight bet: one leg. Parlay: one entry per leg we could match.
    let legs: [LegStatus]
    let totalLegs: Int

    var isParlay: Bool { totalLegs > 1 }
    var winningLegs: Int { legs.filter { $0.status == .won }.count }
    var anyStarted: Bool { legs.contains { $0.game.state != "pre" } }

    /// Final result if it's decided, nil while still in play.
    var finalResult: BetStatus? {
        if legs.contains(where: { $0.game.isFinal && $0.status == .lost }) { return .lost }
        guard legs.count == totalLegs, legs.allSatisfy({ $0.game.isFinal }) else { return nil }
        if !isParlay { return legs[0].status }
        // A pushed parlay leg changes the payout, so leave that one for you to settle.
        return legs.allSatisfy { $0.status == .won } ? .won : nil
    }

    /// Status right now (for live display).
    var current: BetStatus {
        let started = legs.filter { $0.status != .pending }
        if started.isEmpty { return .pending }
        if started.contains(where: { $0.status == .lost }) { return .lost }
        if started.allSatisfy({ $0.status == .push }) { return .push }
        return .won
    }
}

/// Reads bets like "Alabama -5.5", "Navy Midshipmen +2.5", "Over 62.5 (Alabama @ Mississippi State)"
/// or "Chiefs ML" and grades them against live scores.
enum LiveBetEvaluator {
    static func evaluate(_ bet: Bet, games: [LiveGameDTO]) -> LiveBetInfo? {
        if bet.betType == .parlay, !bet.legs.isEmpty {
            let legs = bet.legs.compactMap { leg in
                evaluateLine(leg.selection, context: "", type: nil, games: games)
            }
            return legs.isEmpty ? nil : LiveBetInfo(legs: legs, totalLegs: bet.legs.count)
        }
        guard bet.betType != .prop, bet.betType != .parlay,
              let leg = evaluateLine(bet.selection, context: bet.event, type: bet.betType, games: games) else { return nil }
        return LiveBetInfo(legs: [leg], totalLegs: 1)
    }

    static func evaluateLine(_ text: String, context: String, type: BetType?, games: [LiveGameDTO]) -> LegStatus? {
        let lower = text.lowercased()

        // Totals: "Over 62.5", "U 43.5"
        if let m = lower.firstMatch(of: /\b(over|under|o|u)\s*(\d+(?:\.\d+)?)/),
           let line = Double(m.2) {
            let side = m.1.hasPrefix("o") ? "Over" : "Under"
            guard let game = bestGame(for: text + " " + context, games: games)?.game else { return nil }
            return grade(text, game: game, market: "total", selection: side, point: line)
        }

        guard let (game, team, range) = bestGame(for: text, context: context, games: games) else { return nil }
        // Spread: the first signed number after the team name ("-5.5", "+2.5"); "PK" = 0.
        let after = String(text[range.upperBound...])
        if type != .moneyline, !after.lowercased().contains(" ml"),
           let m = after.firstMatch(of: /([+-]\d+(?:\.\d+)?)(?!\d)/), let point = Double(m.1),
           abs(point) < 100 { // +150 style numbers are moneyline odds, not spreads
            return grade(text, game: game, market: "spread", selection: team, point: point)
        }
        if after.lowercased().contains("pk") {
            return grade(text, game: game, market: "spread", selection: team, point: 0)
        }
        return grade(text, game: game, market: "moneyline", selection: team, point: nil)
    }

    private static func grade(_ text: String, game: LiveGameDTO, market: String, selection: String, point: Double?) -> LegStatus? {
        guard game.state != "pre", let h = game.homeScore, let a = game.awayScore else {
            return LegStatus(text: text, game: game, status: .pending)
        }
        let status = Settlement.grade(market: market, selection: selection, point: point,
                                      homeTeam: game.homeTeam, awayTeam: game.awayTeam, homeScore: h, awayScore: a)
        return LegStatus(text: text, game: game, status: status)
    }

    /// Name variants from most to least specific: "Alabama Crimson Tide", "Alabama Crimson", "Alabama".
    static func nameVariants(_ team: String) -> [String] {
        let words = team.split(separator: " ")
        return (1...max(1, words.count)).reversed().map { words.prefix($0).joined(separator: " ") }
            .filter { $0.count >= 3 }
    }

    /// Where a team is mentioned in the text (earliest, longest name variant).
    private static func mention(of team: String, in text: String) -> Range<String.Index>? {
        for name in nameVariants(team) {
            if let r = text.range(of: name, options: [.caseInsensitive]) {
                // Whole-word match only ("Miami" shouldn't match "MiamiOH"-style run-ons).
                let endOK = r.upperBound == text.endIndex || !text[r.upperBound].isLetter
                let startOK = r.lowerBound == text.startIndex || !text[text.index(before: r.lowerBound)].isLetter
                if endOK && startOK { return r }
            }
        }
        return nil
    }

    /// Picks the game and team the text is about. Scores each game by how much of a team
    /// name matched, plus a bonus when the opponent is mentioned too (text or event).
    private static func bestGame(for text: String, context: String = "", games: [LiveGameDTO])
        -> (game: LiveGameDTO, team: String, range: Range<String.Index>)? {
        var best: (score: Int, game: LiveGameDTO, team: String, range: Range<String.Index>)?
        let all = text + " " + context
        for game in games {
            for (team, opponent) in [(game.homeTeam, game.awayTeam), (game.awayTeam, game.homeTeam)] {
                guard let r = mention(of: team, in: text) else { continue }
                var score = text[r].count * 10
                if mention(of: opponent, in: all) != nil { score += 500 }
                score -= text.distance(from: text.startIndex, to: r.lowerBound) // earlier mention wins
                if best == nil || score > best!.score { best = (score, game, team, r) }
            }
        }
        return best.map { ($0.game, $0.team, $0.range) }
    }

    /// Tracker league -> backend sport keys for live scores.
    static func sportKeys(for league: String) -> [String] {
        switch league {
        case "NFL": ["americanfootball_nfl"]
        case "NCAAF": ["americanfootball_ncaaf"]
        case "NBA": ["basketball_nba"]
        case "WNBA": ["basketball_wnba"]
        case "NCAAB": ["basketball_ncaab"]
        case "MLB": ["baseball_mlb"]
        case "NHL": ["icehockey_nhl"]
        case "Soccer": ["soccer_epl", "soccer_usa_mls"]
        default: []
        }
    }
}
