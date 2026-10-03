import Foundation

struct PicksResponse: Decodable {
    let date: String
    let sports: [SportSummary]
    let picks: [PickDTO]
}

struct SportSummary: Decodable, Identifiable {
    let sport: String
    let league: String
    let gameCount: Int
    let slateNotes: String
    let generatedAt: String
    let error: String?
    var id: String { sport }
}

struct PickDTO: Decodable {
    struct ExpertConsensus: Decodable {
        let summary: String
        let expertsAgreeing: [String]
        let expertsDisagreeing: [String]
    }

    let id: String
    let eventId: String
    let sport: String
    let league: String
    let event: String
    let homeTeam: String
    let awayTeam: String
    let startTime: Date
    let market: String
    let selection: String
    let point: Double?
    let bestOdds: Int
    let bookmaker: String
    let impliedProbability: Double
    let marketFairProbability: Double
    let aiEstimatedProbability: Double
    let edge: Double
    let expectedValue: Double
    let confidence: Int
    let suggestedUnits: Double
    let tier: String
    let reasoning: [String]
    let keyRisks: [String]
    let expertConsensus: ExpertConsensus
    let sources: [String]
}

struct ScoreDTO: Decodable {
    let eventId: String
    let completed: Bool
    let homeTeam: String
    let awayTeam: String
    let homeScore: Int?
    let awayScore: Int?
}

enum APIError: LocalizedError {
    case badURL
    case server(Int, String)

    var errorDescription: String? {
        switch self {
        case .badURL: "The backend URL in Settings isn't valid."
        case .server(401, _): "The backend rejected the app token. Check Settings → App token."
        case let .server(code, body): "Backend error \(code): \(body)"
        }
    }
}

/// Talks to the BettingPicks backend (never directly to Anthropic or The Odds API).
struct APIClient {
    var baseURL: String
    var token: String

    init(defaults: UserDefaults = .standard) {
        baseURL = defaults.string(forKey: SettingsKey.backendURL) ?? Defaults.backendURL
        token = defaults.string(forKey: SettingsKey.appToken) ?? Defaults.appToken
    }

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        let plain = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        d.dateDecodingStrategy = .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            if let date = plain.date(from: s) ?? fractional.date(from: s) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad date \(s)"))
        }
        return d
    }()

    func health() async throws -> (anthropicKey: Bool, oddsKey: Bool) {
        struct Health: Decodable { let anthropicKey: Bool; let oddsKey: Bool }
        let h: Health = try await get("/health", query: [])
        return (h.anthropicKey, h.oddsKey)
    }

    /// Picks for the user's local day. Analysis can take a few minutes on a fresh slate.
    func picks(sports: [String], day: Date = .now, footballWeek: Bool, refresh: Bool) async throws -> PicksResponse {
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        let end = cal.date(byAdding: .day, value: 1, to: start)!
        let iso = ISO8601DateFormatter()
        return try await get("/picks/today", query: [
            .init(name: "sports", value: sports.joined(separator: ",")),
            .init(name: "date", value: Self.dayKey(day)),
            .init(name: "from", value: iso.string(from: start)),
            .init(name: "to", value: iso.string(from: end)),
            .init(name: "window", value: footballWeek ? "week" : "day"),
            .init(name: "refresh", value: refresh ? "1" : "0"),
        ], timeout: 900)
    }

    func scores(sports: [String]) async throws -> [ScoreDTO] {
        try await get("/scores", query: [.init(name: "sports", value: sports.joined(separator: ","))])
    }

    static func dayKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    func get<T: Decodable>(_ path: String, query: [URLQueryItem], timeout: TimeInterval = 30) async throws -> T {
        let trimmed = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: " /"))
        guard var components = URLComponents(string: trimmed + path), components.host != nil else { throw APIError.badURL }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw APIError.badURL }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        if !token.isEmpty { request.setValue(token, forHTTPHeaderField: "x-app-token") }
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw APIError.server(code, String(data: data, encoding: .utf8) ?? "")
        }
        return try Self.decoder.decode(T.self, from: data)
    }
}
