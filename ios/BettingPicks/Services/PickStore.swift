import Foundation
import Observation
import SwiftData

/// Loads AI picks from the backend into SwiftData and settles finished ones.
@MainActor
@Observable
final class PickStore {
    /// Day key ("2026-10-03") currently being analyzed, if any.
    var loadingDay: String?
    var progress: String?
    var isSettling = false
    var errors: [String: String] = [:]
    var summaries: [String: [SportSummary]] = [:]
    /// Backwards-compatible single error used by other screens.
    var errorMessage: String?

    func load(day: Date, context: ModelContext, refresh: Bool) async {
        let key = APIClient.dayKey(day)
        let sports = (UserDefaults.standard.string(forKey: SettingsKey.selectedSports) ?? SportOption.defaultKeys)
            .split(separator: ",").map(String.init)
        guard !sports.isEmpty else {
            errors[key] = "Pick at least one sport in Settings."
            return
        }
        loadingDay = key
        errors[key] = nil
        progress = "Starting analysis…"
        defer { loadingDay = nil; progress = nil }

        var shouldRefresh = refresh
        // Poll every 15s for up to ~25 minutes while the backend analyzes.
        for attempt in 0..<100 {
            do {
                let response = try await APIClient().picks(sports: sports, day: day, refresh: shouldRefresh)
                shouldRefresh = false // only the first request may start a re-analysis
                summaries[key] = response.sports
                try upsert(response, context: context)

                let running = response.sports.filter { $0.status == "running" }
                if running.isEmpty {
                    let errs = response.sports.compactMap(\.error)
                    if errs.contains(where: { $0.contains("API_KEY is not set") }) {
                        errors[key] = "The backend is missing its API keys. Add them in Railway (see README)."
                    } else if !errs.isEmpty {
                        errors[key] = "Some sports failed: " + errs.joined(separator: " · ")
                    }
                    return
                }
                let names = running.map { SportOption.displayName(league: $0.league) }.joined(separator: " & ")
                let minutes = attempt / 4
                progress = "Analyzing \(names)… \(minutes > 0 ? "\(minutes) min" : "")"
            } catch {
                // A dropped connection doesn't stop the server-side analysis; keep polling a few times.
                if attempt > 3 { errors[key] = error.localizedDescription; return }
            }
            try? await Task.sleep(for: .seconds(15))
        }
        errors[key] = "Still analyzing. Check back in a few minutes."
    }

    private func upsert(_ response: PicksResponse, context: ModelContext) throws {
        let date = response.date
        let existing = try context.fetch(FetchDescriptor<AIPick>(predicate: #Predicate { $0.slateDate == date }))
        var byID = Dictionary(uniqueKeysWithValues: existing.map { ($0.pickID, $0) })
        let finished = Set(response.sports.filter { $0.status != "running" && $0.error == nil }.map(\.sport))

        for dto in response.picks where finished.contains(dto.sport) {
            if let pick = byID.removeValue(forKey: dto.id) {
                pick.update(from: dto)
            } else {
                context.insert(AIPick(dto: dto, slateDate: date))
            }
        }
        // A re-run that no longer recommends a pick withdraws it, unless you already bet it.
        for leftover in byID.values where finished.contains(leftover.sportKey)
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
            // Final scores come from the free ESPN feed, so settling doesn't use Odds API quota.
            let scores = LiveScores()
            await scores.refresh(sports: Array(Set(pending.map(\.sportKey))),
                                 days: Array(Set(pending.map { Calendar.current.startOfDay(for: $0.startTime) })))
            let bets = try context.fetch(FetchDescriptor<Bet>(predicate: #Predicate { $0.statusRaw == pendingRaw }))

            for pick in pending {
                guard let s = scores.game(home: pick.homeTeam, away: pick.awayTeam), s.isFinal,
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
