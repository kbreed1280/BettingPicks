import SwiftData
import SwiftUI

/// Every AI pick ever made, with its graded result: the AI's own track record.
struct PickHistoryView: View {
    @Environment(\.modelContext) private var context
    @Environment(PickStore.self) private var store
    @Query(sort: \AIPick.startTime, order: .reverse) private var picks: [AIPick]

    var body: some View {
        List {
            let stats = BetStats(picks: picks)
            Section {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]) {
                    StatTile(title: "Record", value: stats.record)
                    StatTile(title: "Units (1u flat)", value: Format.units(stats.profit), tint: stats.profit.profitColor)
                    StatTile(title: "ROI", value: stats.staked > 0 ? Format.percent(stats.roi, signed: true) : "—",
                             tint: stats.roi.profitColor)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            } footer: {
                Text("Every AI pick is graded at 1 unit, whether or not you bet it. \(stats.pending) still pending.")
            }

            let grouped = Dictionary(grouping: picks, by: \.slateDate)
            ForEach(grouped.keys.sorted(by: >), id: \.self) { day in
                Section(day) {
                    ForEach(grouped[day] ?? []) { pick in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(pick.selectionLabel).font(.subheadline.weight(.semibold))
                                Text("\(pick.league) · \(pick.event)").font(.caption).foregroundStyle(.secondary)
                                Text("\(Format.odds(pick.bestOdds)) · edge \(Format.percent(pick.edge, signed: true)) · \(pick.tier)")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            StatusBadge(status: pick.result)
                        }
                    }
                }
            }
        }
        .overlay {
            if picks.isEmpty {
                ContentUnavailableView("No AI picks yet", systemImage: "clock",
                                       description: Text("Every pick Claude makes is logged here automatically and graded when the game ends."))
            }
        }
        .navigationTitle("AI Track Record")
        .task { await store.syncHistory(context: context) }
        .refreshable { await store.syncHistory(context: context) }
        .toolbar {
            Button {
                Task { await store.settle(context: context) }
            } label: {
                if store.isSettling { ProgressView() } else { Label("Check results", systemImage: "checkmark.seal") }
            }
        }
    }
}
