# Build Prompt: BettingPicks iPhone App

Copy everything below the line into Claude Code (opened in this `BettingPicks` folder).

---

You are building **BettingPicks**, a native iPhone app, in this empty repository. Work in phases, commit after each phase, and stop to show me the result at the end of each one before you move on. Ask me before making any decision that isn't covered here.

## What the app does

1. **Bet tracker.** I log every bet I place and see my wins, losses, and profit over time.
2. **AI daily picks.** Each day the app pulls every game on the schedule with live odds, has Claude analyze them, and shows me a ranked list of the best picks, each with its reasoning. With one tap I can add a pick to my tracker.

## Tech stack

- **iOS app:** Swift + SwiftUI, iOS 17+, MVVM, SwiftData for local storage. No third-party UI libraries.
- **Backend proxy:** a small Node.js (TypeScript) or Python server that I'll deploy on Railway. API keys must **never** ship inside the iOS app. The app only talks to my backend, and the backend talks to the outside APIs.
- **Odds data:** [The Odds API](https://the-odds-api.com) for the schedule plus moneyline, spread, and totals odds across bookmakers. Read the key from the env var `ODDS_API_KEY`.
- **AI analysis:** Anthropic Claude API with the most capable model, `claude-opus-5-5`. Read the key from the env var `ANTHROPIC_API_KEY`. Turn on the Claude API's server-side **web search tool** so the model can look up same-day injuries, lineups, weather, and news before it picks. Use structured JSON output so the app can parse picks reliably. (If the `claude-api` skill is available, load it before you write this code.)

## Feature 1: Bet tracker

Store each bet with these fields:
- Date, sport/league, event (e.g. "Chiefs vs Bills")
- Bet type: moneyline, spread, total (over/under), prop, or parlay (a parlay holds its legs)
- My selection, American odds (e.g. -110 or +150), stake ($), sportsbook
- Status: pending / won / lost / push / void
- Payout, calculated automatically from the odds and stake
- Notes, plus a flag for whether the bet came from an AI pick (and which one)

Screens:
- **Dashboard:** total profit/loss, record (W-L-P), win %, ROI, units won, current streak, and a profit-over-time chart (Swift Charts). Add filters for date range, sport, bet type, and AI picks vs. my own picks.
- **Bet list:** pending bets at the top, swipe to mark won/lost/push, tap to edit.
- **Add bet:** a fast form with sensible defaults (today's date, the last-used sportsbook).
- **Breakdown:** performance by sport, by bet type, and by odds range, so I can see where I actually make money. Also include an "AI picks vs. my picks" comparison.
- Export to CSV.

## Feature 2: AI daily picks

Backend endpoint `GET /picks/today?sports=nfl,nba,...`:
1. Fetch today's games and odds from The Odds API for the sports I choose. Take the **best available price** for each market across bookmakers.
2. Send the games and odds to Claude with a strong system prompt (below). Claude should research with web search, then return JSON.
3. **Cache the results for each day and sport.** Re-run only when I tap "Refresh," because the API calls cost money. Log token usage so I can watch the cost.

Each pick in the JSON must include:
- `event`, `sport`, `start_time`, `market`, `selection`, `best_odds`, `bookmaker`
- `implied_probability` (from the odds) and `ai_estimated_probability`
- `edge` (estimated probability minus implied probability) and `expected_value`
- `confidence` (1–5), `suggested_units` (0.5–3, fractional-Kelly style and capped)
- `reasoning` (3–5 bullets: matchup, injuries/news, trends, why the line is mispriced)
- `key_risks` (what would make this pick lose)

System prompt guidance for Claude:
- Act as a disciplined, data-driven sports betting analyst.
- **Rank by value (positive expected value), not just likelihood of winning.** A -500 favorite usually wins but is often a bad bet, so the app should show both win probability and edge.
- Look at every game. Only return picks with a real edge; returning zero picks on a day is allowed. Return at most 5–8 "best picks," plus an optional "lean" list.
- Be honest about uncertainty and never claim a lock or a guarantee.
- Avoid same-game correlated picks unless I explicitly ask for a parlay.

iOS screens:
- **Today's Picks:** cards sorted by edge, each showing a confidence badge, odds, AI win % vs. implied %, and expandable reasoning. Buttons: "Add to tracker" (pre-fills the bet form) and "Refresh."
- **Settings:** which sports to analyze, unit size in $, default stake, backend URL.
- **Pick history:** save every AI pick and settle it automatically once the game ends (use The Odds API scores endpoint), so the app tracks the AI's own record and ROI separately from mine. This is how I'll learn whether the AI actually helps.

## Responsible gambling
- Add a one-line disclaimer on the picks screen: "AI analysis, not a guarantee. Bet responsibly."
- Add an optional daily/weekly loss-limit warning in Settings.

## Build phases
1. **Project setup:** Xcode project (SwiftUI, SwiftData), folder structure, `.gitignore` (Xcode + Node/Python + `.env`), README.
2. **Bet tracker:** models, add/edit/list, payout math (with unit tests for American odds math), dashboard, and charts.
3. **Backend:** odds fetch, Claude analysis with web search plus structured output, caching, and a `.env.example`. Include a local run script and Railway deploy instructions.
4. **Picks UI:** the Today's Picks screen, "Add to tracker," settings.
5. **AI track record:** pick history, auto-settling, AI vs. me comparison.
6. **Polish:** dark mode, empty states, error handling (no games, API down, out of credits), app icon placeholder.

Write unit tests for all odds, payout, implied-probability, and ROI math. Keep the code clean and commented where it isn't obvious. At the end, give me step-by-step instructions for: getting both API keys, deploying the backend to Railway, and running the app on my own iPhone from Xcode.
