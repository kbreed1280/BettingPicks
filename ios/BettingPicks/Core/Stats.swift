import Foundation

/// Performance summary for any group of bets.
struct BetStats: Equatable {
    var wins = 0
    var losses = 0
    var pushes = 0
    var pending = 0
    var profit = 0.0
    var staked = 0.0
    var pendingExposure = 0.0
    /// e.g. "W3" or "L2"; empty when nothing is settled.
    var streak = ""

    var settledCount: Int { wins + losses + pushes }
    var record: String { pushes > 0 ? "\(wins)-\(losses)-\(pushes)" : "\(wins)-\(losses)" }
    var winRate: Double { wins + losses > 0 ? Double(wins) / Double(wins + losses) : 0 }
    var roi: Double { BettingMath.roi(profit: profit, staked: staked) }

    func units(unitSize: Double) -> Double { unitSize > 0 ? profit / unitSize : 0 }

    init() {}

    init(bets: [Bet]) {
        for bet in bets {
            switch bet.status {
            case .won: wins += 1
            case .lost: losses += 1
            case .push: pushes += 1
            case .pending: pending += 1; pendingExposure += bet.stake
            case .void: break
            }
            if bet.status == .won || bet.status == .lost || bet.status == .push {
                profit += bet.profit
                staked += bet.stake
            }
        }
        streak = Self.streak(of: bets.filter { $0.status == .won || $0.status == .lost }
            .sorted { $0.effectiveDate < $1.effectiveDate }
            .map(\.status))
    }

    /// Flat 1-unit record for AI picks.
    init(picks: [AIPick]) {
        for pick in picks {
            switch pick.result {
            case .won: wins += 1
            case .lost: losses += 1
            case .push: pushes += 1
            case .pending: pending += 1
            case .void: break
            }
            if pick.result == .won || pick.result == .lost || pick.result == .push {
                profit += pick.unitProfit
                staked += 1
            }
        }
        streak = Self.streak(of: picks.filter { $0.result == .won || $0.result == .lost }
            .sorted { $0.startTime < $1.startTime }
            .map(\.result))
    }

    static func streak(of results: [BetStatus]) -> String {
        guard let last = results.last else { return "" }
        let count = results.reversed().prefix { $0 == last }.count
        return (last == .won ? "W" : "L") + "\(count)"
    }

    /// Cumulative profit after each settled bet, oldest first.
    static func profitSeries(_ bets: [Bet]) -> [(date: Date, profit: Double)] {
        var running = 0.0
        return bets.filter { $0.status.isSettled }
            .sorted { $0.effectiveDate < $1.effectiveDate }
            .map { running += $0.profit; return ($0.effectiveDate, running) }
    }
}

/// Buckets used by the "by odds range" breakdown.
enum OddsRange: String, CaseIterable {
    case heavyFavorite = "-200 or shorter"
    case favorite = "-199 to -121"
    case coinFlip = "-120 to +120"
    case underdog = "+121 to +199"
    case longshot = "+200 or longer"

    init(odds: Int) {
        switch odds {
        case ...(-200): self = .heavyFavorite
        case -199 ... -121: self = .favorite
        case -120 ... 120: self = .coinFlip
        case 121 ... 199: self = .underdog
        default: self = .longshot
        }
    }
}

/// Responsible-gambling loss limits. A limit of 0 means off.
enum LossLimit {
    static func warning(bets: [Bet], daily: Double, weekly: Double, now: Date = .now) -> String? {
        let cal = Calendar.current
        func loss(since start: Date) -> Double {
            -bets.filter { $0.status.isSettled && $0.effectiveDate >= start }.reduce(0) { $0 + $1.profit }
        }
        if daily > 0 {
            let today = loss(since: cal.startOfDay(for: now))
            if today >= daily { return "You've lost \(Format.money(today)) today, which hits your \(Format.money(daily)) daily limit." }
        }
        if weekly > 0, let weekStart = cal.dateInterval(of: .weekOfYear, for: now)?.start {
            let week = loss(since: weekStart)
            if week >= weekly { return "You've lost \(Format.money(week)) this week, which hits your \(Format.money(weekly)) weekly limit." }
        }
        return nil
    }
}
