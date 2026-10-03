import Foundation

/// Grades a moneyline/spread/total pick from a final score.
enum Settlement {
    static func grade(
        market: String,
        selection: String,
        point: Double?,
        homeTeam: String,
        awayTeam: String,
        homeScore: Int,
        awayScore: Int
    ) -> BetStatus {
        let home = Double(homeScore), away = Double(awayScore)

        switch market {
        case "total":
            guard let line = point else { return .void }
            let total = home + away
            if total == line { return .push }
            let overHit = total > line
            return (selection.lowercased() == "over") == overHit ? .won : .lost

        case "spread":
            guard let line = point else { return .void }
            let (mine, theirs): (Double, Double)
            if selection == homeTeam { (mine, theirs) = (home, away) }
            else if selection == awayTeam { (mine, theirs) = (away, home) }
            else { return .void }
            let margin = mine + line - theirs
            return margin > 0 ? .won : margin < 0 ? .lost : .push

        default: // moneyline
            if selection.lowercased() == "draw" { return home == away ? .won : .lost }
            if home == away { return .push }
            let winner = home > away ? homeTeam : awayTeam
            if selection != homeTeam && selection != awayTeam { return .void }
            return selection == winner ? .won : .lost
        }
    }
}
