import Foundation

/// Odds and payout math. All odds are American (e.g. -110, +150).
enum BettingMath {
    static func decimalOdds(american: Int) -> Double {
        guard american != 0 else { return 1 }
        return american > 0 ? 1 + Double(american) / 100 : 1 + 100 / Double(abs(american))
    }

    static func americanOdds(decimal: Double) -> Int {
        guard decimal > 1 else { return 0 }
        return decimal >= 2
            ? Int(((decimal - 1) * 100).rounded())
            : Int((-100 / (decimal - 1)).rounded())
    }

    /// Break-even win probability for a price.
    static func impliedProbability(american: Int) -> Double {
        1 / decimalOdds(american: american)
    }

    /// Profit (not including stake) if the bet wins.
    static func profit(stake: Double, americanOdds: Int) -> Double {
        stake * (decimalOdds(american: americanOdds) - 1)
    }

    static func realizedProfit(stake: Double, americanOdds: Int, status: BetStatus) -> Double {
        switch status {
        case .won: profit(stake: stake, americanOdds: americanOdds)
        case .lost: -stake
        case .pending, .push, .void: 0
        }
    }

    /// Combined American price of a parlay from its legs' prices.
    static func parlayOdds(legs: [Int]) -> Int {
        guard !legs.isEmpty else { return 0 }
        return americanOdds(decimal: legs.reduce(1) { $0 * decimalOdds(american: $1) })
    }

    /// Return on investment as a fraction (0.05 == 5%).
    static func roi(profit: Double, staked: Double) -> Double {
        staked > 0 ? profit / staked : 0
    }

    /// Parses "+150", "-110" or "150" into an Int; nil for 0 or values between -100 and +100.
    static func parseAmerican(_ text: String) -> Int? {
        let cleaned = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "+", with: "")
        guard let value = Int(cleaned), abs(value) >= 100 else { return nil }
        return value
    }
}

enum Format {
    static func odds(_ american: Int) -> String { american > 0 ? "+\(american)" : "\(american)" }

    static func money(_ value: Double, signed: Bool = false) -> String {
        let s = value.formatted(.currency(code: "USD").precision(.fractionLength(2)))
        return signed && value > 0 ? "+" + s : s
    }

    static func percent(_ value: Double, digits: Int = 1, signed: Bool = false) -> String {
        let s = value.formatted(.percent.precision(.fractionLength(digits)))
        return signed && value > 0 ? "+" + s : s
    }

    static func units(_ value: Double) -> String {
        let s = value.formatted(.number.precision(.fractionLength(1)))
        return (value > 0 ? "+" : "") + s + "u"
    }

    static func point(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }

    static func signedPoint(_ value: Double) -> String {
        value > 0 ? "+" + point(value) : point(value)
    }
}
