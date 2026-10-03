import SwiftData
import SwiftUI

struct PicksView: View {
    @Environment(\.modelContext) private var context
    @Environment(PickStore.self) private var store
    @Query private var todaysPicks: [AIPick]
    @State private var addingFrom: AIPick?

    init() {
        let today = APIClient.dayKey(.now)
        _todaysPicks = Query(filter: #Predicate<AIPick> { $0.slateDate == today },
                             sort: [SortDescriptor(\.edge, order: .reverse)])
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("AI analysis, not a guarantee. Bet responsibly.", systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if store.isLoading {
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                            VStack(alignment: .leading) {
                                Text("Analyzing the slate…").font(.subheadline.weight(.semibold))
                                Text("Claude is checking odds, injuries, news and expert picks. A fresh slate can take a few minutes.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if let error = store.errorMessage {
                    Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
                }

                let best = todaysPicks.filter { $0.tier == "best" }
                let leans = todaysPicks.filter { $0.tier != "best" }
                if !best.isEmpty {
                    Section("Best picks") { cards(best) }
                }
                if !leans.isEmpty {
                    Section("Leans · smaller edges") { cards(leans) }
                }

                if !store.sportSummaries.isEmpty {
                    Section("Slate notes") {
                        ForEach(store.sportSummaries) { s in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(s.league) · \(s.gameCount) games").font(.subheadline.weight(.semibold))
                                if let err = s.error {
                                    Text(err).font(.caption).foregroundStyle(.red)
                                } else if !s.slateNotes.isEmpty {
                                    Text(s.slateNotes).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .overlay {
                if todaysPicks.isEmpty && !store.isLoading {
                    ContentUnavailableView {
                        Label("No picks yet", systemImage: "sparkles")
                    } description: {
                        Text(store.lastLoaded == nil
                             ? "Get today's AI picks for your sports."
                             : "No bets with a real edge today. Sitting out is a valid pick.")
                    } actions: {
                        Button("Get picks") { Task { await store.load(context: context, refresh: false) } }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle("AI Picks")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink { PickHistoryView() } label: { Label("History", systemImage: "clock.arrow.circlepath") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await store.load(context: context, refresh: true) } } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(store.isLoading)
                }
            }
            .task {
                if todaysPicks.isEmpty && store.lastLoaded == nil && !store.isLoading {
                    await store.load(context: context, refresh: false)
                }
                await store.settle(context: context)
            }
            .sheet(item: $addingFrom) { pick in
                BetFormView(draft: BetDraft(pick: pick)) { _ in pick.addedToTracker = true }
            }
        }
    }

    private func cards(_ picks: [AIPick]) -> some View {
        ForEach(picks) { pick in
            PickCard(pick: pick) { addingFrom = pick }
        }
    }
}

struct PickCard: View {
    let pick: AIPick
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

            HStack(spacing: 8) {
                metric("AI win %", Format.percent(pick.aiProbability, digits: 0))
                metric("Implied", Format.percent(pick.impliedProbability, digits: 0))
                metric("Edge", Format.percent(pick.edge, signed: true), tint: .green)
                metric("Units", Format.point(pick.suggestedUnits))
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
