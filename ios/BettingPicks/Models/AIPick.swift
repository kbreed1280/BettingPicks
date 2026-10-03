import Foundation
import SwiftData

/// A pick produced by the backend's Claude analysis. Every pick is kept so the
/// app can track the AI's own record separately from your bets.
@Model
final class AIPick {
    @Attribute(.unique) var pickID: String
    var slateDate: String
    var fetchedAt: Date
    var eventID: String
    var sportKey: String
    var league: String
    var event: String
    var homeTeam: String
    var awayTeam: String
    var startTime: Date
    /// "moneyline", "spread" or "total"
    var market: String
    var selection: String
    var point: Double?
    var bestOdds: Int
    var bookmaker: String
    var impliedProbability: Double
    var marketFairProbability: Double
    var aiProbability: Double
    var edge: Double
    var expectedValue: Double
    var confidence: Int
    var suggestedUnits: Double
    var tier: String
    var reasoning: [String]
    var keyRisks: [String]
    var expertSummary: String
    var expertsAgreeing: [String]
    var expertsDisagreeing: [String]
    var sources: [String]
    var resultRaw: String
    var homeScore: Int?
    var awayScore: Int?
    var addedToTracker: Bool

    init(dto: PickDTO, slateDate: String) {
        pickID = dto.id
        self.slateDate = slateDate
        fetchedAt = .now
        eventID = dto.eventId
        sportKey = dto.sport
        league = dto.league
        event = dto.event
        homeTeam = dto.homeTeam
        awayTeam = dto.awayTeam
        startTime = dto.startTime
        market = dto.market
        selection = dto.selection
        point = dto.point
        bestOdds = dto.bestOdds
        bookmaker = dto.bookmaker
        impliedProbability = dto.impliedProbability
        marketFairProbability = dto.marketFairProbability
        aiProbability = dto.aiEstimatedProbability
        edge = dto.edge
        expectedValue = dto.expectedValue
        confidence = dto.confidence
        suggestedUnits = dto.suggestedUnits
        tier = dto.tier
        reasoning = dto.reasoning
        keyRisks = dto.keyRisks
        expertSummary = dto.expertConsensus.summary
        expertsAgreeing = dto.expertConsensus.expertsAgreeing
        expertsDisagreeing = dto.expertConsensus.expertsDisagreeing
        sources = dto.sources
        resultRaw = BetStatus.pending.rawValue
        addedToTracker = false
    }

    /// Refreshes the analysis fields after a re-run, keeping result/tracker state.
    func update(from dto: PickDTO) {
        fetchedAt = .now
        bestOdds = dto.bestOdds
        bookmaker = dto.bookmaker
        impliedProbability = dto.impliedProbability
        marketFairProbability = dto.marketFairProbability
        aiProbability = dto.aiEstimatedProbability
        edge = dto.edge
        expectedValue = dto.expectedValue
        confidence = dto.confidence
        suggestedUnits = dto.suggestedUnits
        tier = dto.tier
        reasoning = dto.reasoning
        keyRisks = dto.keyRisks
        expertSummary = dto.expertConsensus.summary
        expertsAgreeing = dto.expertConsensus.expertsAgreeing
        expertsDisagreeing = dto.expertConsensus.expertsDisagreeing
        sources = dto.sources
    }

    var result: BetStatus {
        get { BetStatus(rawValue: resultRaw) ?? .pending }
        set { resultRaw = newValue.rawValue }
    }

    var betType: BetType {
        switch market {
        case "spread": .spread
        case "total": .total
        default: .moneyline
        }
    }

    /// e.g. "Chiefs -3.5", "Over 47.5", "Chiefs ML"
    var selectionLabel: String {
        switch market {
        case "spread": "\(selection) \(Format.signedPoint(point ?? 0))"
        case "total": "\(selection) \(Format.point(point ?? 0))"
        default: "\(selection) ML"
        }
    }

    /// Flat 1-unit profit for the AI's own record.
    var unitProfit: Double { BettingMath.realizedProfit(stake: 1, americanOdds: bestOdds, status: result) }
}
