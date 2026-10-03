import SwiftData
import SwiftUI

struct BetListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Bet.placedAt, order: .reverse) private var bets: [Bet]
    @State private var editing: Bet?
    @State private var showingAdd = false
    @State private var search = ""

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
            .navigationTitle("Bets")
            .toolbar {
                Button { showingAdd = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add bet")
            }
            .sheet(isPresented: $showingAdd) { BetFormView(draft: BetDraft()) }
            .sheet(item: $editing) { bet in BetFormView(draft: BetDraft(bet: bet), editing: bet) }
        }
    }

    private func rows(_ list: [Bet]) -> some View {
        ForEach(list) { bet in
            Button { editing = bet } label: { BetRow(bet: bet) }
                .buttonStyle(.plain)
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button("Won") { set(bet, .won) }.tint(.green)
                    Button("Lost") { set(bet, .lost) }.tint(.red)
                }
                .swipeActions(edge: .trailing) {
                    Button("Delete", role: .destructive) { context.delete(bet) }
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
