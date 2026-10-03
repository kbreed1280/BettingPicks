import Foundation

enum BetType: String, Codable, CaseIterable, Identifiable {
    case moneyline, spread, total, prop, parlay

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .moneyline: "Moneyline"
        case .spread: "Spread"
        case .total: "Total (O/U)"
        case .prop: "Prop"
        case .parlay: "Parlay"
        }
    }
}

enum BetStatus: String, Codable, CaseIterable, Identifiable {
    case pending, won, lost, push, void

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
    var isSettled: Bool { self != .pending }
}

struct ParlayLeg: Codable, Hashable, Identifiable {
    var id = UUID()
    var selection: String
    var odds: Int
}

/// Sports the backend can analyze. Keys match The Odds API.
struct SportOption: Identifiable, Hashable {
    let key: String
    let name: String
    var id: String { key }

    static let all: [SportOption] = [
        .init(key: "americanfootball_nfl", name: "NFL"),
        .init(key: "americanfootball_ncaaf", name: "College Football"),
        .init(key: "basketball_nba", name: "NBA"),
        .init(key: "basketball_wnba", name: "WNBA"),
        .init(key: "basketball_ncaab", name: "College Basketball"),
        .init(key: "baseball_mlb", name: "MLB"),
        .init(key: "icehockey_nhl", name: "NHL"),
        .init(key: "soccer_epl", name: "EPL"),
        .init(key: "soccer_usa_mls", name: "MLS"),
        .init(key: "mma_mixed_martial_arts", name: "MMA"),
    ]

    static let defaultKeys = "americanfootball_nfl,americanfootball_ncaaf"

    /// The backend's short league label ("NCAAF") as shown in the app ("College Football").
    static func displayName(league: String) -> String {
        switch league {
        case "NCAAF": "College Football"
        case "NCAAB": "College Basketball"
        default: league
        }
    }

    /// Short labels used when logging bets by hand.
    static let trackerLeagues = ["NFL", "NCAAF", "NBA", "WNBA", "NCAAB", "MLB", "NHL", "Soccer", "MMA", "Golf", "Tennis", "Other"]
}
