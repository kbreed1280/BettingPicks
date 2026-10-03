import SwiftData
import SwiftUI

struct GameQuoteDTO: Decodable, Hashable {
    let name: String
    let point: Double?
    let bestOdds: Int
    let bookmaker: String
    let fairProbability: Double
}

struct GameDTO: Decodable, Identifiable, Hashable {
    struct Markets: Decodable, Hashable {
        let h2h: [GameQuoteDTO]?
        let spreads: [GameQuoteDTO]?
        let totals: [GameQuoteDTO]?
    }

    let eventId: String
    let sportKey: String
    let league: String
    let startTime: Date
    let homeTeam: String
    let awayTeam: String
    let markets: Markets
    var id: String { eventId }

    var matchup: String { "\(awayTeam) @ \(homeTeam)" }
    var hasStarted: Bool { startTime <= .now }
}

extension APIClient {
    /// The next 7 days of games (one Odds API call per sport; the app filters by day).
    func games(sports: [String]) async throws -> [GameDTO] {
        let start = Calendar.current.startOfDay(for: .now)
        let end = Calendar.current.date(byAdding: .day, value: 7, to: start)!
        let iso = ISO8601DateFormatter()
        return try await get("/games", query: [
            .init(name: "sports", value: sports.joined(separator: ",")),
            .init(name: "from", value: iso.string(from: start)),
            .init(name: "to", value: iso.string(from: end)),
            .init(name: "window", value: "week"),
        ])
    }
}

extension BetDraft {
    /// Pre-fills a bet from one line of a game.
    init(game: GameDTO, betType: BetType, quote: GameQuoteDTO) {
        self.init()
        sport = Self.trackerLeague(for: game.sportKey)
        event = game.matchup
        self.betType = betType
        switch betType {
        case .spread: selection = "\(quote.name) \(Format.signedPoint(quote.point ?? 0))"
        case .total: selection = "\(quote.name) \(Format.point(quote.point ?? 0))"
        default: selection = "\(quote.name) ML"
        }
        oddsText = Format.odds(quote.bestOdds)
        if Defaults.sportsbooks.contains(quote.bookmaker) { sportsbook = quote.bookmaker }
    }
}

/// Today's schedule (and the week's football) with the best line for each market.
struct GamesView: View {
    @AppStorage(SettingsKey.selectedSports) private var selectedSports = SportOption.defaultKeys
    @State private var selectedDay = Calendar.current.startOfDay(for: .now)
    @Query private var picks: [AIPick]
    @Environment(LiveScores.self) private var live

    @State private var games: [GameDTO] = []
    @State private var loading = false
    @State private var error: String?
    @State private var leagueFilter = "All"
    @State private var search = ""
    @State private var draft: BetDraft?

    private var aiPickEvents: Set<String> { Set(picks.map(\.eventID)) }

    private var visible: [GameDTO] {
        games.filter { g in
            Calendar.current.isDate(g.startTime, inSameDayAs: selectedDay)
                && (leagueFilter == "All" || g.league == leagueFilter)
                && (search.isEmpty || g.homeTeam.localizedCaseInsensitiveContains(search)
                    || g.awayTeam.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        List {
            if let error {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(days, id: \.self) { day in
                        let count = games.filter { Calendar.current.isDate($0.startTime, inSameDayAs: day) }.count
                        Button { selectedDay = day } label: {
                            VStack(spacing: 2) {
                                Text(dayTitle(day)).font(.caption.weight(.semibold))
                                Text("\(count) games").font(.caption2)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 6)
                        }
                        .buttonStyle(.bordered)
                        .tint(Calendar.current.isDate(day, inSameDayAs: selectedDay) ? .accentColor : .secondary)
                    }
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
            if Set(games.map(\.league)).count > 1 {
                Picker("League", selection: $leagueFilter) {
                    Text("All").tag("All")
                    ForEach(Array(Set(games.map(\.league))).sorted(), id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            let byLeague = Dictionary(grouping: visible, by: \.league)
            ForEach(byLeague.keys.sorted(), id: \.self) { league in
                Section(SportOption.displayName(league: league)) {
                    ForEach(byLeague[league] ?? []) { game in
                        GameRow(game: game, hasAIPick: aiPickEvents.contains(game.eventId),
                                live: live.game(home: game.homeTeam, away: game.awayTeam)) { type, quote in
                            draft = BetDraft(game: game, betType: type, quote: quote)
                        }
                    }
                }
            }
        }
        .searchable(text: $search, prompt: "Find a team")
        .overlay {
            if loading && games.isEmpty {
                ProgressView("Loading games…")
            } else if !loading && visible.isEmpty && error == nil {
                ContentUnavailableView("No games found", systemImage: "sportscourt",
                                       description: Text("No games with odds on this day for your sports."))
            }
        }
        .refreshable { await load() }
        .task { if games.isEmpty { await load() } }
        .task(id: selectedDay) {
            await live.poll(sports: selectedSports.split(separator: ",").map(String.init), days: [selectedDay])
        }
        .sheet(item: Binding(get: { draft.map(IdentifiedDraft.init) }, set: { draft = $0?.draft })) { item in
            BetFormView(draft: item.draft)
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            games = try await APIClient().games(sports: selectedSports.split(separator: ",").map(String.init))
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private var days: [Date] {
        let today = Calendar.current.startOfDay(for: .now)
        return (0..<7).map { Calendar.current.date(byAdding: .day, value: $0, to: today)! }
    }

    private func dayTitle(_ day: Date) -> String {
        if Calendar.current.isDateInToday(day) { return "Today" }
        if Calendar.current.isDateInTomorrow(day) { return "Tomorrow" }
        return day.formatted(.dateTime.weekday(.wide).month().day())
    }
}

private struct IdentifiedDraft: Identifiable {
    let id = UUID()
    let draft: BetDraft
}

private struct GameRow: View {
    let game: GameDTO
    let hasAIPick: Bool
    var live: LiveGameDTO?
    let onPick: (BetType, GameQuoteDTO) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(game.league).font(.caption.weight(.bold)).foregroundStyle(.tint)
                if game.hasStarted {
                    if live == nil { Text("STARTED").font(.caption2.weight(.bold)).foregroundStyle(.red) }
                } else {
                    Text(game.startTime, format: .dateTime.hour().minute()).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if hasAIPick {
                    Label("AI pick", systemImage: "sparkles").font(.caption2.weight(.semibold)).foregroundStyle(.tint)
                }
            }
            if let live, live.state != "pre" {
                LiveScoreBar(live: live, awayTeam: game.awayTeam, homeTeam: game.homeTeam)
            }

            Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 6) {
                GridRow {
                    Text("").gridColumnAlignment(.leading)
                    header("Spread"); header("Money"); header("Total")
                }
                teamRow(game.awayTeam, totalSide: "Over")
                teamRow(game.homeTeam, totalSide: "Under")
            }
        }
        .padding(.vertical, 4)
    }

    private func header(_ text: String) -> some View {
        Text(text).font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity)
    }

    private func teamRow(_ team: String, totalSide: String) -> some View {
        GridRow {
            Text(team).font(.subheadline.weight(.semibold)).lineLimit(2).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
            cell(.spread, game.markets.spreads?.first { $0.name == team }) { "\(Format.signedPoint($0.point ?? 0))" }
            cell(.moneyline, game.markets.h2h?.first { $0.name == team }) { _ in "" }
            cell(.total, game.markets.totals?.first { $0.name == totalSide }) { "\(totalSide.prefix(1)) \(Format.point($0.point ?? 0))" }
        }
    }

    private func cell(_ type: BetType, _ quote: GameQuoteDTO?, label: (GameQuoteDTO) -> String) -> some View {
        Group {
            if let quote {
                Button { onPick(type, quote) } label: {
                    VStack(spacing: 0) {
                        let top = label(quote)
                        if !top.isEmpty { Text(top).font(.caption.weight(.semibold)) }
                        Text(Format.odds(quote.bestOdds)).font(.caption.monospacedDigit())
                            .foregroundStyle(top.isEmpty ? .primary : .secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 34)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Bet \(quote.name) \(type.displayName) \(Format.odds(quote.bestOdds))")
            } else {
                Text("—").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 34)
            }
        }
    }
}
