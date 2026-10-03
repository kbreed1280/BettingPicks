import CoreTransferable
import Foundation
import UniformTypeIdentifiers

enum CSVExport {
    static let header = "Date Placed,Date Settled,Sport,Event,Bet Type,Selection,Odds,Stake,Sportsbook,Status,Profit,AI Pick,Notes"

    static func csv(for bets: [Bet]) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withFullDate]
        let rows = bets.sorted { $0.placedAt < $1.placedAt }.map { bet in
            [
                iso.string(from: bet.placedAt),
                bet.settledAt.map { iso.string(from: $0) } ?? "",
                bet.sport,
                bet.event,
                bet.betType.displayName,
                bet.selection,
                Format.odds(bet.odds),
                String(format: "%.2f", bet.stake),
                bet.sportsbook,
                bet.status.displayName,
                String(format: "%.2f", bet.profit),
                bet.isAIPick ? "Yes" : "No",
                bet.notes,
            ].map(escape).joined(separator: ",")
        }
        return ([header] + rows).joined(separator: "\n") + "\n"
    }

    static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

/// Lets ShareLink hand a CSV file to Files, Mail, AirDrop, etc.
struct CSVFile: Transferable {
    let text: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { Data($0.text.utf8) }
            .suggestedFileName("BettingPicks-bets.csv")
    }
}
