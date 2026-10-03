import SwiftData
import SwiftUI

/// Today's or tomorrow's picks, grouped by league. Nothing is analyzed until you
/// tap "Get picks", because each new slate uses Claude credits.
struct PicksView: View {
    @State private var dayOffset = 0

    private var day: Date {
        Calendar.current.date(byAdding: .day, value: dayOffset, to: Calendar.current.startOfDay(for: .now))!
    }

    var body: some View {
        NavigationStack {
            PicksDayList(day: day, dayOffset: $dayOffset)
                .id(dayOffset)
                .navigationTitle("AI Picks")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        NavigationLink { PickHistoryView() } label: { Label("History", systemImage: "clock.arrow.circlepath") }
                    }
                }
        }
    }
}

private struct PicksDayList: View {
    let day: Date
    @Binding var dayOffset: Int

    @Environment(\.modelContext) private var context
    @Environment(PickStore.self) private var store
    @Query private var picks: [AIPick]
    @Query private var bets: [Bet]
    @State private var addingFrom: AIPick?

    @AppStorage(SettingsKey.selectedSports) private var selectedSports = SportOption.defaultKeys
    @AppStorage(SettingsKey.bankroll) private var bankroll = 0.0
    @AppStorage(SettingsKey.bankrollSetAt) private var bankrollSetAt = 0.0
    @AppStorage(SettingsKey.adjustBankroll) private var adjustBankroll = true
    @AppStorage(SettingsKey.riskLevel) private var riskRaw = RiskLevel.moderate.rawValue
    @State private var bankrollEntry: Double?

    init(day: Date, dayOffset: Binding<Int>) {
        self.day = day
        _dayOffset = dayOffset
        let start = day
        let end = Calendar.current.date(byAdding: .day, value: 1, to: day)!
        // Filter by kickoff time, so each day only shows games played that day.
        _picks = Query(filter: #Predicate<AIPick> { $0.startTime >= start && $0.startTime < end },
                       sort: [SortDescriptor(\.edge, order: .reverse)])
    }

    private var dayKey: String { APIClient.dayKey(day) }
    private var risk: RiskLevel { RiskLevel(rawValue: riskRaw) ?? .moderate }
    private var currentBankroll: Double {
        Bankroll.current(starting: bankroll, setAt: Date(timeIntervalSince1970: bankrollSetAt),
                         adjustWithResults: adjustBankroll, bets: bets)
    }
    private var stakes: [String: Double] {
        StakeSizer.stakes(for: picks, bankroll: currentBankroll, risk: risk)
    }
    private var summaries: [SportSummary] { store.summaries[dayKey] ?? [] }
    private var isLoading: Bool { store.loadingDay == dayKey }
    private var dayName: String { dayOffset == 0 ? "today" : "tomorrow" }

    /// Leagues in the order you picked them in Settings.
    private var leagues: [String] {
        let order = SportOption.all.map(\.name)
        return Array(Set(picks.map(\.league))).sorted {
            (order.firstIndex(of: SportOption.displayName(league: $0)) ?? 99) < (order.firstIndex(of: SportOption.displayName(league: $1)) ?? 99)
        }
    }

    var body: some View {
        List {
            Section {
                Picker("Day", selection: $dayOffset) {
                    Text("Today").tag(0)
                    Text("Tomorrow").tag(1)
                }
                .pickerStyle(.segmented)
                Label("AI analysis, not a guarantee. Bet responsibly.", systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            bankrollSection

            if isLoading {
                Section {
                    HStack(spacing: 12) {
                        ProgressView()
                        VStack(alignment: .leading) {
                            Text(store.progress ?? "Analyzing…").font(.subheadline.weight(.semibold))
                            Text("Claude is checking odds, injuries, news and expert picks. This can take 5–10 minutes. You can leave this screen; it keeps going.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if let error = store.errors[dayKey] {
                Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
            }

            ForEach(leagues, id: \.self) { league in
                let leaguePicks = picks.filter { $0.league == league }
                let best = leaguePicks.filter { $0.tier == "best" }
                let leans = leaguePicks.filter { $0.tier != "best" }
                Section {
                    cards(best)
                    if !leans.isEmpty {
                        Text("Leans · smaller edges").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        cards(leans)
                    }
                } header: {
                    Text("\(SportOption.displayName(league: league)) · \(leaguePicks.count) pick\(leaguePicks.count == 1 ? "" : "s")")
                }
            }

            if !summaries.isEmpty {
                Section("Slate notes") {
                    ForEach(summaries) { s in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("\(SportOption.displayName(league: s.league)) · \(s.gameCount) games").font(.subheadline.weight(.semibold))
                                Spacer()
                                if let cost = s.costUSD { Text("cost \(Format.money(cost))").font(.caption2).foregroundStyle(.secondary) }
                            }
                            if let err = s.error {
                                Text(err).font(.caption).foregroundStyle(.red)
                            } else if !s.slateNotes.isEmpty {
                                Text(s.slateNotes).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            if !isLoading {
                Section {
                    Button {
                        Task { await store.load(day: day, context: context, refresh: !picks.isEmpty || !summaries.isEmpty) }
                    } label: {
                        Label(picks.isEmpty && summaries.isEmpty ? "Get picks for \(dayName)" : "Re-analyze \(dayName)",
                              systemImage: picks.isEmpty && summaries.isEmpty ? "sparkles" : "arrow.clockwise")
                    }
                } footer: {
                    Text("Only analyzes games played \(dayName) for: \(sportNames). Sports with no games \(dayName) cost nothing. Each new analysis uses Claude credits; results are saved, and re-analyzing within 2 hours just returns the saved picks.")
                }
            }
        }
        .overlay {
            if picks.isEmpty && !isLoading && store.errors[dayKey] == nil && !summaries.isEmpty {
                ContentUnavailableView("No picks \(dayName)", systemImage: "hand.raised",
                                       description: Text("No bets with a real edge. Sitting out is a valid pick."))
            }
        }
        .task { await store.settle(context: context) }
        .sheet(item: $addingFrom) { pick in
            BetFormView(draft: BetDraft(pick: pick, stake: stakes[pick.pickID])) { _ in pick.addedToTracker = true }
        }
    }

    private var sportNames: String {
        let keys = Set(selectedSports.split(separator: ",").map(String.init))
        return SportOption.all.filter { keys.contains($0.key) }.map(\.name).joined(separator: ", ")
    }

    private func cards(_ picks: [AIPick]) -> some View {
        let stakes = stakes
        return ForEach(picks) { pick in
            PickCard(pick: pick, stake: stakes[pick.pickID]) { addingFrom = pick }
        }
    }

    @ViewBuilder private var bankrollSection: some View {
        if bankroll <= 0 {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("How much do you have to bet with?").font(.subheadline.weight(.semibold))
                    Text("Enter your bankroll and every pick will show exactly how much to bet.")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        TextField("e.g. $500", value: $bankrollEntry, format: .currency(code: "USD"))
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                        Button("Save") {
                            if let amount = bankrollEntry, amount > 0 {
                                bankroll = amount
                                bankrollSetAt = Date.now.timeIntervalSince1970
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled((bankrollEntry ?? 0) <= 0)
                    }
                }
                .padding(.vertical, 4)
            }
        } else {
            let total = stakes.values.reduce(0, +)
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Bankroll").font(.caption).foregroundStyle(.secondary)
                        Text(Format.money(currentBankroll)).font(.headline.monospacedDigit())
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(dayOffset == 0 ? "Today" : "Tomorrow")'s plan · \(risk.displayName)").font(.caption).foregroundStyle(.secondary)
                        Text(picks.isEmpty ? "—" : "\(Format.money(total)) on \(stakes.values.filter { $0 > 0 }.count) bets")
                            .font(.headline.monospacedDigit())
                    }
                }
            } footer: {
                Text("\(risk.summary). Change your bankroll or risk level in Settings.")
            }
        }
    }
}

struct PickCard: View {
    let pick: AIPick
    /// Dollar amount to bet from your bankroll; nil when no bankroll is set.
    var stake: Double?
    var onAdd: (() -> Void)?
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(pick.league).font(.caption.weight(.bold)).foregroundStyle(.tint)
                Text(pick.startTime, format: .dateTime.weekday(.abbreviated).hour().minute())
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                ConfidenceView(level: pick.confidence)
            }
            Text(pick.event).font(.subheadline).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline) {
                Text(pick.selectionLabel).font(.title3.weight(.bold))
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text(Format.odds(pick.bestOdds)).font(.title3.weight(.semibold).monospacedDigit())
                    Text(pick.bookmaker).font(.caption2).foregroundStyle(.secondary)
                }
            }

            if let stake, stake > 0 {
                HStack(alignment: .firstTextBaseline) {
                    Text("Bet \(Format.money(stake))")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.white)
                    Spacer()
                    Text("to win \(Format.money(BettingMath.profit(stake: stake, americanOdds: pick.bestOdds)))")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.9))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 10))
            }

            HStack(spacing: 8) {
                metric("AI win %", Format.percent(pick.aiProbability, digits: 0))
                metric("Implied", Format.percent(pick.impliedProbability, digits: 0))
                metric("Edge", Format.percent(pick.edge, signed: true), tint: .green)
            }

            if !pick.expertSummary.isEmpty {
                Label(pick.expertSummary, systemImage: "person.3")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(expanded ? nil : 2)
            }

            DisclosureGroup(isExpanded: $expanded) {
                PickDetail(pick: pick)
            } label: {
                Text("Why this pick").font(.subheadline.weight(.semibold))
            }

            HStack {
                if pick.result != .pending {
                    StatusBadge(status: pick.result)
                    if let h = pick.homeScore, let a = pick.awayScore {
                        Text("Final: \(pick.awayTeam) \(a) – \(pick.homeTeam) \(h)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if pick.addedToTracker {
                    Label("In tracker", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
                } else if let onAdd {
                    Button("Add to tracker", systemImage: "plus.circle", action: onAdd)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func metric(_ title: String, _ value: String, tint: Color = .primary) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(tint)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct PickDetail: View {
    let pick: AIPick

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            bullets("Reasoning", pick.reasoning, icon: "checkmark.circle")

            if !pick.expertsAgreeing.isEmpty || !pick.expertsDisagreeing.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Expert picks").font(.caption.weight(.bold))
                    if !pick.expertsAgreeing.isEmpty {
                        Text("Agree: " + pick.expertsAgreeing.joined(separator: ", ")).font(.caption)
                    }
                    if !pick.expertsDisagreeing.isEmpty {
                        Text("Disagree: " + pick.expertsDisagreeing.joined(separator: ", ")).font(.caption)
                    }
                }
            }

            bullets("Risks", pick.keyRisks, icon: "exclamationmark.triangle")

            Text("Market fair odds put this at \(Format.percent(pick.marketFairProbability, digits: 0)). Expected value: \(Format.percent(pick.expectedValue, signed: true)) per unit.")
                .font(.caption).foregroundStyle(.secondary)

            if !pick.sources.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sources").font(.caption.weight(.bold))
                    ForEach(pick.sources, id: \.self) { s in
                        if let url = URL(string: s) {
                            Link(url.host() ?? s, destination: url).font(.caption)
                        }
                    }
                }
            }
        }
        .padding(.top, 6)
    }

    @ViewBuilder
    private func bullets(_ title: String, _ items: [String], icon: String) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.caption.weight(.bold))
                ForEach(items, id: \.self) { item in
                    Label(item, systemImage: icon).font(.caption)
                }
            }
        }
    }
}

struct ConfidenceView: View {
    let level: Int
    var body: some View {
        HStack(spacing: 1) {
            ForEach(1...5, id: \.self) { i in
                Image(systemName: i <= level ? "star.fill" : "star")
                    .font(.caption2)
                    .foregroundStyle(i <= level ? .yellow : .secondary)
            }
        }
        .accessibilityLabel("Confidence \(level) of 5")
    }
}
