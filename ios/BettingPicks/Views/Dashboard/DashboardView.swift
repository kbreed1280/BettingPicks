import Charts
import SwiftData
import SwiftUI

enum DateRangeFilter: String, CaseIterable, Identifiable {
    case week = "7 days", month = "30 days", quarter = "90 days", year = "This year", all = "All time"
    var id: String { rawValue }

    func includes(_ date: Date, now: Date = .now) -> Bool {
        let cal = Calendar.current
        switch self {
        case .week: return date >= cal.date(byAdding: .day, value: -7, to: now)!
        case .month: return date >= cal.date(byAdding: .day, value: -30, to: now)!
        case .quarter: return date >= cal.date(byAdding: .day, value: -90, to: now)!
        case .year: return cal.isDate(date, equalTo: now, toGranularity: .year)
        case .all: return true
        }
    }
}

enum SourceFilter: String, CaseIterable, Identifiable {
    case all = "All bets", ai = "AI picks", mine = "My picks"
    var id: String { rawValue }
}

struct DashboardView: View {
    @Query(sort: \Bet.placedAt, order: .reverse) private var bets: [Bet]
    @AppStorage(SettingsKey.bankroll) private var bankroll = 0.0
    @AppStorage(SettingsKey.bankrollSetAt) private var bankrollSetAt = 0.0
    @AppStorage(SettingsKey.adjustBankroll) private var adjustBankroll = true
    @AppStorage(SettingsKey.defaultStake) private var defaultStake = Defaults.defaultStake

    /// One unit = 1% of your bankroll (or your default stake if no bankroll is set).
    private var unitSize: Double { bankroll > 0 ? bankroll / 100 : defaultStake }
    private var currentBankroll: Double {
        Bankroll.current(starting: bankroll, setAt: Date(timeIntervalSince1970: bankrollSetAt),
                         adjustWithResults: adjustBankroll, bets: bets)
    }
    @AppStorage(SettingsKey.dailyLossLimit) private var dailyLimit = 0.0
    @AppStorage(SettingsKey.weeklyLossLimit) private var weeklyLimit = 0.0

    @State private var range = DateRangeFilter.all
    @State private var sport = "All"
    @State private var betType: BetType?
    @State private var source = SourceFilter.all

    private var filtered: [Bet] {
        bets.filter { bet in
            range.includes(bet.effectiveDate)
                && (sport == "All" || bet.sport == sport)
                && (betType == nil || bet.betType == betType)
                && (source == .all || (source == .ai) == bet.isAIPick)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let warning = LossLimit.warning(bets: bets, daily: dailyLimit, weekly: weeklyLimit) {
                        LossLimitBanner(message: warning)
                    }
                    filters
                    if bankroll > 0 {
                        StatTile(title: "Bankroll", value: Format.money(currentBankroll),
                                 tint: currentBankroll >= bankroll ? .green : .red)
                    }
                    if bets.isEmpty {
                        ContentUnavailableView(
                            "No bets yet",
                            systemImage: "ticket",
                            description: Text("Log a bet in the Bets tab, or add one from today's AI picks.")
                        )
                    } else {
                        let stats = BetStats(bets: filtered)
                        tiles(stats)
                        profitChart
                    }
                }
                .padding()
            }
            .navigationTitle("Dashboard")
        }
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                Picker("Range", selection: $range) {
                    ForEach(DateRangeFilter.allCases) { Text($0.rawValue).tag($0) }
                }
                Picker("Sport", selection: $sport) {
                    Text("All sports").tag("All")
                    ForEach(Array(Set(bets.map(\.sport))).sorted(), id: \.self) { Text($0).tag($0) }
                }
                Picker("Type", selection: $betType) {
                    Text("All types").tag(BetType?.none)
                    ForEach(BetType.allCases) { Text($0.displayName).tag(Optional($0)) }
                }
                Picker("Source", selection: $source) {
                    ForEach(SourceFilter.allCases) { Text($0.rawValue).tag($0) }
                }
            }
            .pickerStyle(.menu)
            .buttonStyle(.bordered)
        }
    }

    private func tiles(_ s: BetStats) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            StatTile(title: "Profit / Loss", value: Format.money(s.profit, signed: true), tint: s.profit.profitColor)
            StatTile(title: "Record (W-L-P)", value: s.record)
            StatTile(title: "Win %", value: s.wins + s.losses > 0 ? Format.percent(s.winRate) : "—")
            StatTile(title: "ROI", value: s.staked > 0 ? Format.percent(s.roi, signed: true) : "—", tint: s.roi.profitColor)
            StatTile(title: "Units", value: Format.units(s.units(unitSize: unitSize)), tint: s.profit.profitColor)
            StatTile(title: "Streak", value: s.streak.isEmpty ? "—" : s.streak,
                     tint: s.streak.hasPrefix("W") ? .green : s.streak.hasPrefix("L") ? .red : .primary)
            StatTile(title: "Pending", value: "\(s.pending)")
            StatTile(title: "At risk", value: Format.money(s.pendingExposure))
        }
    }

    @ViewBuilder private var profitChart: some View {
        let series = BetStats.profitSeries(filtered)
        VStack(alignment: .leading, spacing: 8) {
            Text("Profit over time").font(.headline)
            if series.count < 2 {
                Text("Settle a couple of bets to see your chart.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                Chart {
                    RuleMark(y: .value("Break even", 0))
                        .foregroundStyle(.secondary.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                    ForEach(Array(series.enumerated()), id: \.offset) { _, point in
                        LineMark(x: .value("Date", point.date), y: .value("Profit", point.profit))
                            .interpolationMethod(.monotone)
                        AreaMark(x: .value("Date", point.date), y: .value("Profit", point.profit))
                            .foregroundStyle(.tint.opacity(0.12))
                            .interpolationMethod(.monotone)
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel { if let v = value.as(Double.self) { Text(Format.money(v)) } }
                    }
                }
                .frame(height: 220)
            }
        }
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }
}
