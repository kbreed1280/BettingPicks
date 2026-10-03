import Foundation

/// UserDefaults keys used with @AppStorage throughout the app.
enum SettingsKey {
    static let backendURL = "backendURL"
    static let appToken = "appToken"
    static let selectedSports = "selectedSports"
    static let footballWeekWindow = "footballWeekWindow"
    static let unitSize = "unitSize"
    static let defaultStake = "defaultStake"
    static let lastSportsbook = "lastSportsbook"
    static let dailyLossLimit = "dailyLossLimit"
    static let weeklyLossLimit = "weeklyLossLimit"
}

enum Defaults {
    static let backendURL = "http://localhost:8787"
    static let unitSize = 25.0
    static let defaultStake = 25.0
    static let sportsbooks = ["DraftKings", "FanDuel", "BetMGM", "Caesars", "ESPN BET", "BetRivers", "Fanatics", "Hard Rock", "bet365", "Other"]
}

extension UserDefaults {
    func double(_ key: String, default value: Double) -> Double {
        object(forKey: key) == nil ? value : double(forKey: key)
    }
}
