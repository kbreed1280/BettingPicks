import SwiftData
import SwiftUI

struct SettingsView: View {
    @Query(sort: \Bet.placedAt) private var bets: [Bet]

    @AppStorage(SettingsKey.backendURL) private var backendURL = Defaults.backendURL
    @AppStorage(SettingsKey.appToken) private var appToken = Defaults.appToken
    @AppStorage(SettingsKey.selectedSports) private var selectedSports = SportOption.defaultKeys
    @AppStorage(SettingsKey.footballWeekWindow) private var footballWeekWindow = true
    @AppStorage(SettingsKey.unitSize) private var unitSize = Defaults.unitSize
    @AppStorage(SettingsKey.defaultStake) private var defaultStake = Defaults.defaultStake
    @AppStorage(SettingsKey.dailyLossLimit) private var dailyLimit = 0.0
    @AppStorage(SettingsKey.weeklyLossLimit) private var weeklyLimit = 0.0

    @State private var connectionStatus: String?
    @State private var testing = false

    private var sportSet: Set<String> { Set(selectedSports.split(separator: ",").map(String.init)) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(SportOption.all) { sport in
                        Toggle(sport.name, isOn: Binding(
                            get: { sportSet.contains(sport.key) },
                            set: { on in
                                var set = sportSet
                                if on { set.insert(sport.key) } else { set.remove(sport.key) }
                                selectedSports = SportOption.all.map(\.key).filter(set.contains).joined(separator: ",")
                            }
                        ))
                    }
                    Toggle("Football: include the whole week", isOn: $footballWeekWindow)
                } header: {
                    Text("Sports to analyze")
                } footer: {
                    Text("NFL and college football are weekly, so this shows the next 7 days of football games instead of just today's. Each extra sport costs more API credits.")
                }

                Section {
                    LabeledContent("Unit size") {
                        TextField("Unit", value: $unitSize, format: .currency(code: "USD"))
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Default stake") {
                        TextField("Stake", value: $defaultStake, format: .currency(code: "USD"))
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                } header: {
                    Text("Bankroll")
                } footer: {
                    Text("AI picks suggest a stake in units; adding one to your tracker uses units × unit size.")
                }

                Section {
                    LabeledContent("Daily limit") {
                        TextField("Off", value: $dailyLimit, format: .currency(code: "USD"))
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Weekly limit") {
                        TextField("Off", value: $weeklyLimit, format: .currency(code: "USD"))
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                } header: {
                    Text("Loss limits")
                } footer: {
                    Text("Set to $0 to turn off. You'll see a warning when your losses reach a limit.")
                }

                Section {
                    TextField("Backend URL", text: $backendURL)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("App token", text: $appToken)
                    Button {
                        Task { await testConnection() }
                    } label: {
                        HStack {
                            Text("Test connection")
                            if testing { Spacer(); ProgressView() }
                        }
                    }
                    if let connectionStatus {
                        Text(connectionStatus).font(.caption).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Backend")
                } footer: {
                    Text("Your Railway URL (e.g. https://bettingpicks-production.up.railway.app) and the APP_TOKEN you set there.")
                }

                Section("Data") {
                    ShareLink(item: CSVFile(text: CSVExport.csv(for: bets)),
                              preview: SharePreview("BettingPicks bets.csv")) {
                        Label("Export bets to CSV", systemImage: "square.and.arrow.up")
                    }
                    .disabled(bets.isEmpty)
                }

                Section {
                    Text("AI picks are analysis, not guarantees. Never bet more than you can afford to lose. If gambling stops being fun, call 1-800-GAMBLER.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
    }

    private func testConnection() async {
        testing = true
        defer { testing = false }
        do {
            let h = try await APIClient().health()
            let ping: [ScoreDTO]? = try? await APIClient().scores(sports: [])
            let tokenOK = ping != nil
            connectionStatus = "Connected. Anthropic key: \(h.anthropicKey ? "✓" : "missing") · Odds key: \(h.oddsKey ? "✓" : "missing") · App token: \(tokenOK ? "✓" : "rejected")"
        } catch {
            connectionStatus = "Couldn't connect: \(error.localizedDescription)"
        }
    }
}
