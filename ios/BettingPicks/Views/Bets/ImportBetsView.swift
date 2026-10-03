import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct ImportedBetDTO: Decodable, Hashable {
    struct Leg: Decodable, Hashable {
        let selection: String
        let odds: Int?
    }

    let ticketId: String?
    let placedAt: String?
    let sport: String
    let event: String
    let betType: String
    let selection: String
    let odds: Int
    let stake: Double
    let status: String
    let payout: Double?
    let legs: [Leg]
}

struct ImportResponse: Decodable {
    let sportsbook: String
    let bets: [ImportedBetDTO]
}

/// How an imported bet relates to what's already in the tracker.
enum ImportAction: Equatable {
    case new
    case updateResult(Bet)
    case duplicate(Bet)

    static func == (a: ImportAction, b: ImportAction) -> Bool {
        switch (a, b) {
        case (.new, .new): true
        case let (.updateResult(x), .updateResult(y)), let (.duplicate(x), .duplicate(y)): x.id == y.id
        default: false
        }
    }
}

enum ImportMatcher {
    /// Finds an existing bet for an imported one: by ticket ID, else by event + pick + stake + odds.
    static func match(_ dto: ImportedBetDTO, in bets: [Bet]) -> Bet? {
        if let ticket = dto.ticketId, !ticket.isEmpty, let hit = bets.first(where: { $0.externalID == ticket }) {
            return hit
        }
        let norm = { (s: String) in s.lowercased().filter { $0.isLetter || $0.isNumber } }
        return bets.first {
            norm($0.event) == norm(dto.event) && norm($0.selection) == norm(dto.selection)
                && abs($0.stake - dto.stake) < 0.01 && $0.odds == dto.odds
        }
    }

    static func action(for dto: ImportedBetDTO, in bets: [Bet]) -> ImportAction {
        guard let existing = match(dto, in: bets) else { return .new }
        let status = BetStatus(rawValue: dto.status) ?? .pending
        return existing.status != status && status != .pending ? .updateResult(existing) : .duplicate(existing)
    }

    static func league(_ sport: String) -> String {
        SportOption.trackerLeagues.first { $0.caseInsensitiveCompare(sport) == .orderedSame } ?? "Other"
    }

    static func date(_ text: String?) -> Date {
        guard let text else { return .now }
        let full = ISO8601DateFormatter()
        if let d = full.date(from: text) { return d }
        let dayOnly = DateFormatter()
        dayOnly.dateFormat = "yyyy-MM-dd"
        return dayOnly.date(from: String(text.prefix(10))) ?? .now
    }
}

/// Pick FanDuel (or any sportsbook) "My Bets" screenshots; Claude reads them and you confirm.
struct ImportBetsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var bets: [Bet]

    @State private var photoItems: [PhotosPickerItem] = []
    @State private var candidates: [Candidate] = []
    @State private var sportsbook = ""
    @State private var progress: String?
    @State private var error: String?
    @State private var fromInbox = false

    struct Candidate: Identifiable {
        let id = UUID()
        let dto: ImportedBetDTO
        var action: ImportAction
        var include: Bool
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        Task { await loadInbox() }
                    } label: {
                        Label("Get bets from Claude Code", systemImage: "laptopcomputer.and.arrow.down")
                    }
                    .disabled(progress != nil)
                } header: {
                    Text("Free (your Claude plan)")
                } footer: {
                    Text("AirDrop your FanDuel My Bets screenshots to your Mac, tell Claude Code \"import my bets\", then tap this.")
                }

                Section {
                    PhotosPicker(selection: $photoItems, maxSelectionCount: 10, matching: .images) {
                        Label(candidates.isEmpty ? "Choose screenshots" : "Add more screenshots", systemImage: "photo.on.rectangle.angled")
                    }
                    .disabled(progress != nil)
                } header: {
                    Text("Read on phone (uses API credits)")
                } footer: {
                    Text("About 1–2¢ per screenshot from your Anthropic API credit. Bets you already logged are skipped, and settled ones update your results.")
                }

                if let progress {
                    Section { HStack { ProgressView(); Text(progress) } }
                }
                if let error {
                    Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
                }

                if !candidates.isEmpty {
                    Section("Found \(candidates.count) bet\(candidates.count == 1 ? "" : "s")\(sportsbook.isEmpty ? "" : " · \(sportsbook)")") {
                        ForEach($candidates) { $c in
                            Toggle(isOn: $c.include) { row(c) }
                        }
                    }
                }
            }
            .navigationTitle("Import Bets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import \(candidates.filter(\.include).count)") { save() }
                        .disabled(candidates.allSatisfy { !$0.include })
                }
            }
            .onChange(of: photoItems) { _, items in
                guard !items.isEmpty else { return }
                Task { await read(items) }
            }
        }
    }

    private func row(_ c: Candidate) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(c.dto.selection).font(.subheadline.weight(.semibold))
                Spacer()
                StatusBadge(status: BetStatus(rawValue: c.dto.status) ?? .pending)
            }
            Text(c.dto.event).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Text("\(c.dto.sport) · \(c.dto.betType.capitalized) · \(Format.odds(c.dto.odds)) · \(Format.money(c.dto.stake))")
                .font(.caption).foregroundStyle(.secondary)
            switch c.action {
            case .new: EmptyView()
            case .updateResult: Text("Already logged. Will update the result.").font(.caption2).foregroundStyle(.orange)
            case .duplicate: Text("Already logged").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func loadInbox() async {
        error = nil
        progress = "Checking Claude Code inbox…"
        defer { progress = nil }
        do {
            let result: ImportResponse = try await APIClient().get("/bets/inbox", query: [])
            if result.bets.isEmpty {
                error = "No bets waiting. Tell Claude Code \"import my bets\" first."
                return
            }
            fromInbox = true
            add(result)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func add(_ result: ImportResponse) {
        if !result.sportsbook.isEmpty { sportsbook = result.sportsbook }
        for dto in result.bets where !candidates.contains(where: { $0.dto == dto }) {
            let action = ImportMatcher.action(for: dto, in: bets)
            var include = true
            if case .duplicate = action { include = false }
            candidates.append(Candidate(dto: dto, action: action, include: include))
        }
    }

    private func read(_ items: [PhotosPickerItem]) async {
        error = nil
        defer { progress = nil; photoItems = [] }
        for (i, item) in items.enumerated() {
            progress = "Reading screenshot \(i + 1) of \(items.count)…"
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let jpeg = Self.prepare(data) else { continue }
                struct Body: Encodable { let image: String; let mediaType: String }
                let result: ImportResponse = try await APIClient().post(
                    "/import/screenshot", body: Body(image: jpeg.base64EncodedString(), mediaType: "image/jpeg"))
                add(result)
            } catch {
                self.error = "Couldn't read screenshot \(i + 1): \(error.localizedDescription)"
            }
        }
    }

    /// Downscales to keep uploads small (and Claude image tokens low).
    static func prepare(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let maxSide: CGFloat = 1600
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let resized = UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        return resized.jpegData(compressionQuality: 0.8)
    }

    private func save() {
        for c in candidates where c.include {
            let status = BetStatus(rawValue: c.dto.status) ?? .pending
            switch c.action {
            case let .updateResult(bet), let .duplicate(bet):
                bet.status = status
                if bet.externalID == nil { bet.externalID = c.dto.ticketId }
            case .new:
                let legs = c.dto.legs.compactMap { leg in leg.odds.map { ParlayLeg(selection: leg.selection, odds: $0) } }
                let bet = Bet(placedAt: ImportMatcher.date(c.dto.placedAt), sport: ImportMatcher.league(c.dto.sport),
                              event: c.dto.event, betType: BetType(rawValue: c.dto.betType) ?? .moneyline,
                              selection: c.dto.selection, odds: c.dto.odds, stake: c.dto.stake,
                              sportsbook: sportsbook.isEmpty ? "FanDuel" : sportsbook, status: status,
                              notes: "Imported from screenshot", legs: legs.count == c.dto.legs.count ? legs : [],
                              externalID: c.dto.ticketId)
                context.insert(bet)
            }
        }
        if fromInbox { Task { try? await APIClient().delete("/bets/inbox") } }
        dismiss()
    }
}
