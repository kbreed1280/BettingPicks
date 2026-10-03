import Foundation

/// How aggressively to size bets from the bankroll.
enum RiskLevel: String, CaseIterable, Identifiable {
    case conservative, moderate, aggressive

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }

    /// Fraction of full Kelly to bet. Full Kelly is far too swingy, and AI
    /// probability estimates are noisy, so we only ever use a slice of it.
    var kellyMultiplier: Double {
        switch self {
        case .conservative: 0.125
        case .moderate: 0.25
        case .aggressive: 0.5
        }
    }

    /// Most of the bankroll any single bet can use.
    var maxPerBet: Double {
        switch self {
        case .conservative: 0.02
        case .moderate: 0.04
        case .aggressive: 0.06
        }
    }

    /// Most of the bankroll all of one day's picks can use together.
    var maxPerDay: Double {
        switch self {
        case .conservative: 0.10
        case .moderate: 0.20
        case .aggressive: 0.30
        }
    }

    var summary: String {
        "Up to \(Format.percent(maxPerBet, digits: 0)) per bet, \(Format.percent(maxPerDay, digits: 0)) per day"
    }
}

enum StakeSizer {
    /// Full-Kelly fraction of bankroll for a win probability at a price (0 when there's no edge).
    static func kellyFraction(probability: Double, americanOdds: Int) -> Double {
        let b = BettingMath.decimalOdds(american: americanOdds) - 1
        guard b > 0 else { return 0 }
        return max(0, (b * probability - (1 - probability)) / b)
    }

    /// Dollar stake for each pick, keyed by pickID. Uses fractional Kelly,
    /// caps each bet, then scales everything down if the day's total is over the daily cap.
    /// Amounts are whole dollars; a pick with an edge always gets at least $1.
    static func stakes(for picks: [AIPick], bankroll: Double, risk: RiskLevel) -> [String: Double] {
        stakes(for: picks.map { ($0.pickID, $0.aiProbability, $0.bestOdds) }, bankroll: bankroll, risk: risk)
    }

    static func stakes(for picks: [(id: String, probability: Double, odds: Int)], bankroll: Double, risk: RiskLevel) -> [String: Double] {
        guard bankroll > 0 else { return [:] }
        var raw: [String: Double] = [:]
        for p in picks {
            let fraction = min(kellyFraction(probability: p.probability, americanOdds: p.odds) * risk.kellyMultiplier,
                               risk.maxPerBet)
            raw[p.id] = fraction * bankroll
        }
        let total = raw.values.reduce(0, +)
        let dailyCap = bankroll * risk.maxPerDay
        let scale = total > dailyCap ? dailyCap / total : 1
        return raw.mapValues { amount in
            amount <= 0 ? 0 : max(1, (amount * scale).rounded(.down))
        }
    }
}

/// Your bankroll: what you entered, optionally plus/minus results since then.
enum Bankroll {
    static func current(starting: Double, setAt: Date, adjustWithResults: Bool, bets: [Bet]) -> Double {
        guard adjustWithResults else { return starting }
        let results = bets.filter { $0.status.isSettled && ($0.settledAt ?? $0.placedAt) >= setAt }
            .reduce(0) { $0 + $1.profit }
        return max(0, starting + results)
    }

    /// Money tied up in open bets (the sportsbook already took it).
    static func inPlay(_ bets: [Bet]) -> Double {
        bets.filter { $0.status == .pending }.reduce(0) { $0 + $1.stake }
    }

    /// What you can still bet: bankroll minus open bets.
    static func available(starting: Double, setAt: Date, adjustWithResults: Bool, bets: [Bet]) -> Double {
        max(0, current(starting: starting, setAt: setAt, adjustWithResults: adjustWithResults, bets: bets) - inPlay(bets))
    }
}
