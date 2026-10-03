import Foundation
import SwiftData

@Model
final class Bet {
    var id: UUID
    var placedAt: Date
    var settledAt: Date?
    var sport: String
    var event: String
    var betTypeRaw: String
    var selection: String
    /// American odds. For parlays this is the combined price (derived from legs when present).
    var odds: Int
    var stake: Double
    var sportsbook: String
    var statusRaw: String
    var notes: String
    var isAIPick: Bool
    var aiPickID: String?
    var legs: [ParlayLeg]

    init(
        placedAt: Date = .now,
        sport: String,
        event: String,
        betType: BetType,
        selection: String,
        odds: Int,
        stake: Double,
        sportsbook: String,
        status: BetStatus = .pending,
        notes: String = "",
        isAIPick: Bool = false,
        aiPickID: String? = nil,
        legs: [ParlayLeg] = []
    ) {
        self.id = UUID()
        self.placedAt = placedAt
        self.sport = sport
        self.event = event
        self.betTypeRaw = betType.rawValue
        self.selection = selection
        self.odds = odds
        self.stake = stake
        self.sportsbook = sportsbook
        self.statusRaw = status.rawValue
        self.notes = notes
        self.isAIPick = isAIPick
        self.aiPickID = aiPickID
        self.legs = legs
        if status.isSettled { settledAt = .now }
    }

    var betType: BetType {
        get { BetType(rawValue: betTypeRaw) ?? .moneyline }
        set { betTypeRaw = newValue.rawValue }
    }

    var status: BetStatus {
        get { BetStatus(rawValue: statusRaw) ?? .pending }
        set {
            statusRaw = newValue.rawValue
            settledAt = newValue.isSettled ? (settledAt ?? .now) : nil
        }
    }

    /// Profit if this bet wins.
    var potentialProfit: Double { BettingMath.profit(stake: stake, americanOdds: odds) }

    /// Realized profit/loss: 0 while pending or on a push/void.
    var profit: Double { BettingMath.realizedProfit(stake: stake, americanOdds: odds, status: status) }

    /// Total returned to you (stake + profit) once settled.
    var payout: Double { status == .lost ? 0 : stake + profit }

    /// Date used for charts and filters: when it settled, else when it was placed.
    var effectiveDate: Date { settledAt ?? placedAt }
}
