import SwiftData
import SwiftUI

struct BetListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Bet.placedAt, order: .reverse) private var bets: [Bet]
    @State private var editing: Bet?
    @State private var showingAdd = false
    @State private var showingImport = false
    @State private var deleting: Bet?
    @State private var search = ""
    @AppStorage("betsMode") private var mode = 0

    private var visible: [Bet] {
        guard !search.isEmpty else { return bets }
        return bets.filter {
            $0.event.localizedCaseInsensitiveContains(search)
                || $0.selection.localizedCaseInsensitiveContains(search)
                || $0.sport.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("View", selection: $mode) {
                    Text("My Bets").tag(0)
                    Text("Games").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)
                if mode == 1 { GamesView() } else { betsList }
            }
            .navigationTitle(mode == 1 ? "Games" : "Bets")
            .toolbar {
                Menu {
                    Button("New bet", systemImage: "square.and.pencil") { showingAdd = true }
                    Button("Import from screenshot", systemImage: "photo.on.rectangle") { showingImport = true }
                } label: { Image(systemName: "plus") }
                .accessibilityLabel("Add bet")
            }
            .sheet(isPresented: $showingAdd) { BetFormView(draft: BetDraft()) }
            .sheet(isPresented: $showingImport) { ImportBetsView() }
            .confirmationDialog("Delete this bet?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                                titleVisibility: .visible, presenting: deleting) { bet in
                Button("Delete \(bet.selection)", role: .destructive) { context.delete(bet) }
            } message: { bet in
                Text("\(bet.event) · \(Format.money(bet.stake))")
            }
            .sheet(item: $editing) { bet in BetFormView(draft: BetDraft(bet: bet), editing: bet) }
        }
    }

    private var betsList: some View {
            List {
                let pending = visible.filter { $0.status == .pending }
                let settled = visible.filter { $0.status != .pending }
                if !pending.isEmpty {
                    Section("Pending · \(pending.count)") { rows(pending) }
                }
                if !settled.isEmpty {
                    Section("Settled") { rows(settled) }
                }
            }
            .overlay {
                if bets.isEmpty {
                    ContentUnavailableView {
                        Label("No bets logged", systemImage: "ticket")
                    } description: {
                        Text("Tap + to log your first bet.")
                    } actions: {
                        Button("Add bet") { showingAdd = true }.buttonStyle(.borderedProminent)
                    }
                } else if visible.isEmpty {
                    ContentUnavailableView.search(text: search)
                }
            }
            .searchable(text: $search, prompt: "Team, event, or sport")
    }

    private func rows(_ list: [Bet]) -> some View {
        ForEach(list) { bet in
            Button { editing = bet } label: { BetRow(bet: bet) }
                .buttonStyle(.plain)
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button("Won") { set(bet, .won) }.tint(.green)
                    Button("Lost") { set(bet, .lost) }.tint(.red)
                }
                // No full-swipe here: deleting needs a deliberate tap and a confirmation.
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button("Delete", role: .destructive) { deleting = bet }
                    Button("Push") { set(bet, .push) }.tint(.gray)
                    if bet.status != .pending {
                        Button("Pending") { set(bet, .pending) }.tint(.orange)
                    }
                }
        }
    }

    private func set(_ bet: Bet, _ status: BetStatus) {
        withAnimation { bet.status = status }
    }
}

struct BetRow: View {
    let bet: Bet

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(bet.sport).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    if bet.isAIPick {
                        Image(systemName: "sparkles").font(.caption2).foregroundStyle(.tint)
                    }
                    Text(bet.placedAt, format: .dateTime.month(.abbreviated).day())
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text(bet.selection).font(.body.weight(.semibold))
                Text(bet.event).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                Text("\(bet.betType.displayName) · \(Format.odds(bet.odds)) · \(bet.sportsbook)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                StatusBadge(status: bet.status)
                if bet.status == .pending {
                    Text("\(Format.money(bet.stake)) to win \(Format.money(bet.potentialProfit))")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                } else {
                    Text(Format.money(bet.profit, signed: true))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(bet.profit.profitColor)
                }
            }
        }
        .contentShape(Rectangle())
    }
}
