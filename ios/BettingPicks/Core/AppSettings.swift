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
    /// Build-time defaults come from Config/Secrets.xcconfig via Info.plist.
    static let backendURL = infoString("BPDefaultBackendURL") ?? "http://localhost:8787"
    static let appToken = infoString("BPDefaultAppToken") ?? ""
    static let unitSize = 25.0
    static let defaultStake = 25.0
    static let sportsbooks = ["DraftKings", "FanDuel", "BetMGM", "Caesars", "ESPN BET", "BetRivers", "Fanatics", "Hard Rock", "bet365", "Other"]
}

private func infoString(_ key: String) -> String? {
    guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
          !value.isEmpty, !value.contains("$(") else { return nil }
    return value
}

extension UserDefaults {
    func double(_ key: String, default value: Double) -> Double {
        object(forKey: key) == nil ? value : double(forKey: key)
    }
}
