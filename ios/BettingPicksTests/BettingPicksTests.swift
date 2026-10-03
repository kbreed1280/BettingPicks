import XCTest
@testable import BettingPicks

final class BettingMathTests: XCTestCase {
    func testDecimalOdds() {
        XCTAssertEqual(BettingMath.decimalOdds(american: 150), 2.5, accuracy: 1e-9)
        XCTAssertEqual(BettingMath.decimalOdds(american: -110), 1.909090, accuracy: 1e-5)
        XCTAssertEqual(BettingMath.decimalOdds(american: 100), 2, accuracy: 1e-9)
        XCTAssertEqual(BettingMath.decimalOdds(american: -100), 2, accuracy: 1e-9)
    }

    func testAmericanFromDecimal() {
        XCTAssertEqual(BettingMath.americanOdds(decimal: 2.5), 150)
        XCTAssertEqual(BettingMath.americanOdds(decimal: 1.5), -200)
        XCTAssertEqual(BettingMath.americanOdds(decimal: 2.0), 100)
    }

    func testImpliedProbability() {
        XCTAssertEqual(BettingMath.impliedProbability(american: -110), 0.52381, accuracy: 1e-5)
        XCTAssertEqual(BettingMath.impliedProbability(american: 150), 0.4, accuracy: 1e-9)
    }

    func testProfitAndPayout() {
        XCTAssertEqual(BettingMath.profit(stake: 110, americanOdds: -110), 100, accuracy: 1e-9)
        XCTAssertEqual(BettingMath.profit(stake: 100, americanOdds: 150), 150, accuracy: 1e-9)
        XCTAssertEqual(BettingMath.realizedProfit(stake: 50, americanOdds: 150, status: .lost), -50)
        XCTAssertEqual(BettingMath.realizedProfit(stake: 50, americanOdds: 150, status: .push), 0)
        XCTAssertEqual(BettingMath.realizedProfit(stake: 50, americanOdds: 150, status: .pending), 0)
    }

    func testParlayOdds() {
        // Two -110 legs: 1.909^2 = 3.645 -> +264/+265
        let odds = BettingMath.parlayOdds(legs: [-110, -110])
        XCTAssertTrue((264...265).contains(odds), "got \(odds)")
        XCTAssertEqual(BettingMath.parlayOdds(legs: [100, 100]), 300)
    }

    func testROI() {
        XCTAssertEqual(BettingMath.roi(profit: 10, staked: 200), 0.05, accuracy: 1e-9)
        XCTAssertEqual(BettingMath.roi(profit: 10, staked: 0), 0)
    }

    func testParseAmerican() {
        XCTAssertEqual(BettingMath.parseAmerican("+150"), 150)
        XCTAssertEqual(BettingMath.parseAmerican(" -110 "), -110)
        XCTAssertNil(BettingMath.parseAmerican("50"))
        XCTAssertNil(BettingMath.parseAmerican("abc"))
    }
}

final class SettlementTests: XCTestCase {
    private func grade(_ market: String, _ selection: String, _ point: Double?, home: Int, away: Int) -> BetStatus {
        Settlement.grade(market: market, selection: selection, point: point,
                         homeTeam: "Chiefs", awayTeam: "Bills", homeScore: home, awayScore: away)
    }

    func testMoneyline() {
        XCTAssertEqual(grade("moneyline", "Chiefs", nil, home: 24, away: 20), .won)
        XCTAssertEqual(grade("moneyline", "Bills", nil, home: 24, away: 20), .lost)
        XCTAssertEqual(grade("moneyline", "Bills", nil, home: 20, away: 20), .push)
        XCTAssertEqual(grade("moneyline", "Draw", nil, home: 1, away: 1), .won)
    }

    func testSpread() {
        XCTAssertEqual(grade("spread", "Chiefs", -3.5, home: 24, away: 20), .won)
        XCTAssertEqual(grade("spread", "Chiefs", -3, home: 23, away: 20), .push)
        XCTAssertEqual(grade("spread", "Chiefs", -7, home: 24, away: 20), .lost)
        XCTAssertEqual(grade("spread", "Bills", 3.5, home: 23, away: 20), .won)
        XCTAssertEqual(grade("spread", "Bills", 3.5, home: 24, away: 20), .lost)
    }

    func testTotal() {
        XCTAssertEqual(grade("total", "Over", 44.5, home: 24, away: 21), .won)
        XCTAssertEqual(grade("total", "Under", 44.5, home: 24, away: 21), .lost)
        XCTAssertEqual(grade("total", "Under", 45, home: 24, away: 21), .push)
    }
}

final class StakeSizerTests: XCTestCase {
    func testKellyFraction() {
        // 60% at even money: full Kelly = 20%
        XCTAssertEqual(StakeSizer.kellyFraction(probability: 0.6, americanOdds: 100), 0.2, accuracy: 1e-9)
        XCTAssertEqual(StakeSizer.kellyFraction(probability: 0.4, americanOdds: 100), 0)
    }

    func testStakeUsesFractionalKellyAndPerBetCap() {
        // 55% at -110: full Kelly ≈ 5.5%; moderate = 1/4 ≈ 1.375% of $1000 → $13
        let s = StakeSizer.stakes(for: [(id: "a", probability: 0.55, odds: -110)], bankroll: 1000, risk: .moderate)
        XCTAssertEqual(s["a"], 13)
        // Huge edge gets capped at 4% for moderate
        let capped = StakeSizer.stakes(for: [(id: "b", probability: 0.9, odds: 100)], bankroll: 1000, risk: .moderate)
        XCTAssertEqual(capped["b"], 40)
    }

    func testDailyCapScalesEverythingDown() {
        let picks = (0..<10).map { (id: "p\($0)", probability: 0.9, odds: 100) }
        let s = StakeSizer.stakes(for: picks, bankroll: 1000, risk: .moderate) // 10 × $40 = $400 > $200 cap
        XCTAssertEqual(s.values.reduce(0, +), 200, accuracy: 1)
    }

    func testNoEdgeNoBetAndNoBankrollNoStakes() {
        XCTAssertEqual(StakeSizer.stakes(for: [(id: "x", probability: 0.4, odds: 100)], bankroll: 1000, risk: .moderate)["x"], 0)
        XCTAssertTrue(StakeSizer.stakes(for: [(id: "x", probability: 0.9, odds: 100)], bankroll: 0, risk: .moderate).isEmpty)
    }
}

final class StatsTests: XCTestCase {
    private func bet(_ status: BetStatus, odds: Int = -110, stake: Double = 110, daysAgo: Double = 0) -> Bet {
        let b = Bet(placedAt: Date.now.addingTimeInterval(-daysAgo * 86400), sport: "NFL", event: "A vs B",
                    betType: .spread, selection: "A -3", odds: odds, stake: stake, sportsbook: "DraftKings", status: status)
        b.settledAt = b.placedAt
        return b
    }

    func testRecordProfitROI() {
        let stats = BetStats(bets: [bet(.won, daysAgo: 3), bet(.lost, daysAgo: 2), bet(.won, daysAgo: 1), bet(.push), bet(.pending)])
        XCTAssertEqual(stats.record, "2-1-1")
        XCTAssertEqual(stats.profit, 90, accuracy: 1e-9) // +100 -110 +100 +0
        XCTAssertEqual(stats.staked, 440, accuracy: 1e-9)
        XCTAssertEqual(stats.roi, 90 / 440, accuracy: 1e-9)
        XCTAssertEqual(stats.winRate, 2.0 / 3.0, accuracy: 1e-9)
        XCTAssertEqual(stats.pending, 1)
        XCTAssertEqual(stats.units(unitSize: 100), 0.9, accuracy: 1e-9)
    }

    func testStreak() {
        XCTAssertEqual(BetStats.streak(of: [.lost, .won, .won]), "W2")
        XCTAssertEqual(BetStats.streak(of: [.won, .lost]), "L1")
        XCTAssertEqual(BetStats.streak(of: []), "")
    }

    func testProfitSeriesIsCumulative() {
        let series = BetStats.profitSeries([bet(.won, daysAgo: 2), bet(.lost, daysAgo: 1)])
        XCTAssertEqual(series.count, 2)
        XCTAssertEqual(series[0].profit, 100, accuracy: 1e-9)
        XCTAssertEqual(series[1].profit, -10, accuracy: 1e-9)
    }

    func testOddsRanges() {
        XCTAssertEqual(OddsRange(odds: -250), .heavyFavorite)
        XCTAssertEqual(OddsRange(odds: -150), .favorite)
        XCTAssertEqual(OddsRange(odds: -110), .coinFlip)
        XCTAssertEqual(OddsRange(odds: 150), .underdog)
        XCTAssertEqual(OddsRange(odds: 300), .longshot)
    }

    func testLossLimit() {
        let bets = [bet(.lost, stake: 100), bet(.lost, stake: 60)]
        XCTAssertNotNil(LossLimit.warning(bets: bets, daily: 150, weekly: 0))
        XCTAssertNil(LossLimit.warning(bets: bets, daily: 500, weekly: 0))
        XCTAssertNil(LossLimit.warning(bets: bets, daily: 0, weekly: 0))
    }

    func testCSVEscaping() {
        XCTAssertEqual(CSVExport.escape("plain"), "plain")
        XCTAssertEqual(CSVExport.escape("a, b"), "\"a, b\"")
        XCTAssertEqual(CSVExport.escape("say \"hi\""), "\"say \"\"hi\"\"\"")
        let csv = CSVExport.csv(for: [bet(.won)])
        XCTAssertTrue(csv.hasPrefix(CSVExport.header))
        XCTAssertTrue(csv.contains("Won,100.00"))
    }
}

final class ImportMatcherTests: XCTestCase {
    private func dto(ticket: String? = nil, status: String = "pending", stake: Double = 20) -> ImportedBetDTO {
        ImportedBetDTO(ticketId: ticket, placedAt: "2026-10-03", sport: "NCAAF", event: "Florida Gators @ Missouri Tigers",
                       betType: "spread", selection: "Missouri Tigers +5.5", odds: -110, stake: stake, status: status,
                       payout: nil, legs: [])
    }

    private func existing() -> Bet {
        Bet(sport: "NCAAF", event: "Florida Gators @ Missouri Tigers", betType: .spread, selection: "Missouri Tigers +5.5",
            odds: -110, stake: 20, sportsbook: "FanDuel", externalID: "T1")
    }

    func testNewWhenNoMatch() {
        XCTAssertEqual(ImportMatcher.action(for: dto(stake: 50), in: [existing()]), .new)
    }

    func testDuplicateBySameDetails() {
        let bet = existing()
        XCTAssertEqual(ImportMatcher.action(for: dto(), in: [bet]), .duplicate(bet))
    }

    func testUpdateResultByTicket() {
        let bet = existing()
        XCTAssertEqual(ImportMatcher.action(for: dto(ticket: "T1", status: "won", stake: 99), in: [bet]), .updateResult(bet))
    }

    func testLeagueAndDate() {
        XCTAssertEqual(ImportMatcher.league("nfl"), "NFL")
        XCTAssertEqual(ImportMatcher.league("Cricket"), "Other")
        XCTAssertEqual(Calendar.current.component(.day, from: ImportMatcher.date("2026-10-03")), 3)
    }
}
