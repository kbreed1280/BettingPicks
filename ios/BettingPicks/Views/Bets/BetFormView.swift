import SwiftData
import SwiftUI

/// Editable copy of a bet, so Cancel discards changes.
struct BetDraft {
    var placedAt = Date.now
    var sport = "NFL"
    var event = ""
    var betType = BetType.moneyline
    var selection = ""
    var oddsText = "-110"
    var stake = UserDefaults.standard.double(SettingsKey.defaultStake, default: Defaults.defaultStake)
    var sportsbook = UserDefaults.standard.string(forKey: SettingsKey.lastSportsbook) ?? Defaults.sportsbooks[0]
    var status = BetStatus.pending
    var notes = ""
    var isAIPick = false
    var aiPickID: String?
    var legs: [ParlayLeg] = []

    init() {}

    init(bet: Bet) {
        placedAt = bet.placedAt
        sport = bet.sport
        event = bet.event
        betType = bet.betType
        selection = bet.selection
        oddsText = Format.odds(bet.odds)
        stake = bet.stake
        sportsbook = bet.sportsbook
        status = bet.status
        notes = bet.notes
        isAIPick = bet.isAIPick
        aiPickID = bet.aiPickID
        legs = bet.legs
    }

    init(pick: AIPick, stake: Double?) {
        sport = Self.trackerLeague(for: pick.sportKey)
        event = pick.event
        betType = pick.betType
        selection = pick.selectionLabel
        oddsText = Format.odds(pick.bestOdds)
        if let stake, stake > 0 { self.stake = stake }
        if Defaults.sportsbooks.contains(pick.bookmaker) { sportsbook = pick.bookmaker }
        isAIPick = true
        aiPickID = pick.pickID
        notes = "AI pick · edge \(Format.percent(pick.edge, signed: true)) · confidence \(pick.confidence)/5"
    }

    static func trackerLeague(for sportKey: String) -> String {
        switch sportKey {
        case "americanfootball_nfl": "NFL"
        case "americanfootball_ncaaf": "NCAAF"
        case "basketball_nba": "NBA"
        case "basketball_wnba": "WNBA"
        case "basketball_ncaab": "NCAAB"
        case "baseball_mlb": "MLB"
        case "icehockey_nhl": "NHL"
        case "mma_mixed_martial_arts": "MMA"
        case let k where k.hasPrefix("soccer"): "Soccer"
        default: "Other"
        }
    }

    /// Final American odds: parlays derive from legs when any are entered.
    var odds: Int? {
        if betType == .parlay, !legs.isEmpty {
            let prices = legs.map(\.odds)
            return prices.allSatisfy({ abs($0) >= 100 }) ? BettingMath.parlayOdds(legs: prices) : nil
        }
        return BettingMath.parseAmerican(oddsText)
    }

    var isValid: Bool {
        odds != nil && stake > 0 && !event.trimmingCharacters(in: .whitespaces).isEmpty
            && !(betType != .parlay && selection.trimmingCharacters(in: .whitespaces).isEmpty)
    }
}

struct BetFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var allBets: [Bet]
    @AppStorage(SettingsKey.dailyLossLimit) private var dailyLimit = 0.0
    @AppStorage(SettingsKey.weeklyLossLimit) private var weeklyLimit = 0.0

    @State var draft: BetDraft
    var editing: Bet?
    /// Called after a new bet is saved (used to mark AI picks as tracked).
    var onSave: ((Bet) -> Void)?

    var body: some View {
        NavigationStack {
            Form {
                if editing == nil, let warning = LossLimit.warning(bets: allBets, daily: dailyLimit, weekly: weeklyLimit) {
                    Section { LossLimitBanner(message: warning) }
                        .listRowInsets(EdgeInsets())
                }
                Section("Bet") {
                    Picker("Sport", selection: $draft.sport) {
                        ForEach(SportOption.trackerLeagues, id: \.self) { Text($0) }
                    }
                    TextField("Event (e.g. Chiefs vs Bills)", text: $draft.event)
                    Picker("Bet type", selection: $draft.betType) {
                        ForEach(BetType.allCases) { Text($0.displayName).tag($0) }
                    }
                    TextField(draft.betType == .parlay ? "Description (optional)" : "Your pick (e.g. Chiefs -3.5)",
                              text: $draft.selection)
                    DatePicker("Placed", selection: $draft.placedAt, displayedComponents: [.date, .hourAndMinute])
                }

                if draft.betType == .parlay { ParlayLegsSection(legs: $draft.legs) }

                Section("Wager") {
                    if draft.betType == .parlay && !draft.legs.isEmpty {
                        LabeledContent("Parlay odds", value: draft.odds.map(Format.odds) ?? "—")
                    } else {
                        LabeledContent("Odds") {
                            TextField("-110", text: $draft.oddsText)
                                .keyboardType(.numbersAndPunctuation)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    LabeledContent("Stake") {
                        TextField("Stake", value: $draft.stake, format: .currency(code: "USD"))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    if let odds = draft.odds {
                        LabeledContent("To win", value: Format.money(BettingMath.profit(stake: draft.stake, americanOdds: odds)))
                        LabeledContent("Payout", value: Format.money(draft.stake + BettingMath.profit(stake: draft.stake, americanOdds: odds)))
                    } else {
                        Text("Enter American odds like -110 or +150.").font(.caption).foregroundStyle(.red)
                    }
                    Picker("Sportsbook", selection: $draft.sportsbook) {
                        ForEach(Defaults.sportsbooks, id: \.self) { Text($0) }
                    }
                }

                Section("Result") {
                    Picker("Status", selection: $draft.status) {
                        ForEach(BetStatus.allCases) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Notes") {
                    TextField("Notes", text: $draft.notes, axis: .vertical).lineLimit(2...5)
                    if draft.isAIPick {
                        Label("From an AI pick", systemImage: "sparkles").foregroundStyle(.tint)
                    }
                }
            }
            .navigationTitle(editing == nil ? "New Bet" : "Edit Bet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!draft.isValid)
                }
            }
        }
    }

    private func save() {
        guard let odds = draft.odds else { return }
        let selection = draft.selection.isEmpty && draft.betType == .parlay
            ? "\(draft.legs.count)-leg parlay" : draft.selection
        if let bet = editing {
            bet.placedAt = draft.placedAt
            bet.sport = draft.sport
            bet.event = draft.event
            bet.betType = draft.betType
            bet.selection = selection
            bet.odds = odds
            bet.stake = draft.stake
            bet.sportsbook = draft.sportsbook
            bet.status = draft.status
            bet.notes = draft.notes
            bet.legs = draft.legs
        } else {
            let bet = Bet(placedAt: draft.placedAt, sport: draft.sport, event: draft.event, betType: draft.betType,
                          selection: selection, odds: odds, stake: draft.stake, sportsbook: draft.sportsbook,
                          status: draft.status, notes: draft.notes, isAIPick: draft.isAIPick,
                          aiPickID: draft.aiPickID, legs: draft.legs)
            context.insert(bet)
            onSave?(bet)
        }
        UserDefaults.standard.set(draft.sportsbook, forKey: SettingsKey.lastSportsbook)
        dismiss()
    }
}

private struct ParlayLegsSection: View {
    @Binding var legs: [ParlayLeg]
    @State private var newSelection = ""
    @State private var newOdds = ""

    var body: some View {
        Section {
            ForEach(legs) { leg in
                LabeledContent(leg.selection, value: Format.odds(leg.odds))
            }
            .onDelete { legs.remove(atOffsets: $0) }
            HStack {
                TextField("Leg (e.g. Bills ML)", text: $newSelection)
                TextField("Odds", text: $newOdds)
                    .keyboardType(.numbersAndPunctuation)
                    .frame(width: 70)
                Button {
                    if let odds = BettingMath.parseAmerican(newOdds), !newSelection.isEmpty {
                        legs.append(ParlayLeg(selection: newSelection, odds: odds))
                        newSelection = ""
                        newOdds = ""
                    }
                } label: { Image(systemName: "plus.circle.fill") }
                .disabled(BettingMath.parseAmerican(newOdds) == nil || newSelection.isEmpty)
            }
        } header: {
            Text("Parlay legs")
        } footer: {
            Text("Odds are combined automatically. Or skip legs and type the parlay price in Odds.")
        }
    }
}
