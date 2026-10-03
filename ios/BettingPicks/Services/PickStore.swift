import Foundation
import Observation
import SwiftData

/// Loads AI picks from the backend into SwiftData and settles finished ones.
@MainActor
@Observable
final class PickStore {
    var isLoading = false
    var isSettling = false
    var errorMessage: String?
    var sportSummaries: [SportSummary] = []
    var lastLoaded: Date?

    func load(context: ModelContext, refresh: Bool) async {
        let defaults = UserDefaults.standard
        let sports = (defaults.string(forKey: SettingsKey.selectedSports) ?? SportOption.defaultKeys)
            .split(separator: ",").map(String.init)
        guard !sports.isEmpty else {
            errorMessage = "Pick at least one sport in Settings."
            return
        }
        let footballWeek = defaults.object(forKey: SettingsKey.footballWeekWindow) as? Bool ?? true

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let response = try await APIClient().picks(sports: sports, footballWeek: footballWeek, refresh: refresh)
            sportSummaries = response.sports
            let errors = response.sports.compactMap(\.error)
            if errors.contains(where: { $0.contains("API_KEY is not set") }) {
                errorMessage = "The backend is missing its API keys, so it can't analyze games yet. Add ANTHROPIC_API_KEY and ODDS_API_KEY in Railway (see README)."
            } else if !errors.isEmpty {
                errorMessage = "Some sports failed: " + errors.joined(separator: " · ")
            }
            try upsert(response, context: context)
            lastLoaded = .now
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func upsert(_ response: PicksResponse, context: ModelContext) throws {
        let date = response.date
        let existing = try context.fetch(FetchDescriptor<AIPick>(predicate: #Predicate { $0.slateDate == date }))
        var byID = Dictionary(uniqueKeysWithValues: existing.map { ($0.pickID, $0) })
        let loadedSports = Set(response.sports.filter { $0.error == nil }.map(\.sport))

        for dto in response.picks {
            if let pick = byID.removeValue(forKey: dto.id) {
                pick.update(from: dto)
            } else {
                context.insert(AIPick(dto: dto, slateDate: date))
            }
        }
        // A re-run that no longer recommends a pick withdraws it, unless you already bet it.
        for leftover in byID.values where loadedSports.contains(leftover.sportKey)
            && !leftover.addedToTracker && leftover.result == .pending {
            context.delete(leftover)
        }
        try context.save()
    }

    /// Grades pending AI picks (and tracker bets made from them) whose games have finished.
    func settle(context: ModelContext) async {
        let pendingRaw = BetStatus.pending.rawValue
        let cutoff = Date.now.addingTimeInterval(-2.5 * 3600)
        guard let pending = try? context.fetch(FetchDescriptor<AIPick>(
            predicate: #Predicate { $0.resultRaw == pendingRaw && $0.startTime < cutoff }
        )), !pending.isEmpty else { return }

        isSettling = true
        defer { isSettling = false }
        do {
            let sports = Array(Set(pending.map(\.sportKey)))
            let scores = try await APIClient().scores(sports: sports)
            let byEvent = Dictionary(scores.map { ($0.eventId, $0) }, uniquingKeysWith: { a, _ in a })
            let bets = try context.fetch(FetchDescriptor<Bet>(predicate: #Predicate { $0.statusRaw == pendingRaw }))

            for pick in pending {
                guard let s = byEvent[pick.eventID], s.completed,
                      let home = s.homeScore, let away = s.awayScore else { continue }
                pick.homeScore = home
                pick.awayScore = away
                pick.result = Settlement.grade(
                    market: pick.market, selection: pick.selection, point: pick.point,
                    homeTeam: pick.homeTeam, awayTeam: pick.awayTeam, homeScore: home, awayScore: away)
                // Only auto-grade your bet if you took the same line the AI did.
                for bet in bets where bet.aiPickID == pick.pickID && bet.betType != .parlay {
                    bet.status = pick.result
                }
            }
            try context.save()
        } catch {
            errorMessage = "Couldn't check results: \(error.localizedDescription)"
        }
    }
}
