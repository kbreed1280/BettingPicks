# BettingPicks

An iPhone app that tracks your bets, plus a backend that uses Claude (`claude-opus-5-5`) to analyze each day's games. Claude researches odds, injuries, news, and expert picks to find value bets. NFL and college football are the defaults; other major sports are available in Settings.

```
iPhone app (SwiftUI + SwiftData)  ──x-app-token──▶  server/ (Node, on Railway)
                                                     ├─ The Odds API  (schedule, odds, scores)
                                                     └─ Claude API    (analysis + web search)
```

API keys live only on the server. The app talks to your backend and never calls Anthropic or The Odds API directly.

## What's in the app

- **Dashboard:** profit/loss, record, win %, ROI, units, streak, money at risk, and a profit chart. Filter by date range, sport, bet type, and AI picks vs. your own picks.
- **Bets:** log moneyline, spread, total, prop, and parlay bets. Swipe to mark won, lost, or push. Payouts are calculated from the odds.
- **AI Picks:** ranked by edge (AI win % minus the odds' implied %). Each pick shows its reasoning, risks, and what the experts are picking, with source links. "Add to tracker" pre-fills a bet with the suggested stake.
- **AI Track Record:** every AI pick is graded automatically from final scores at a flat 1 unit, so you can see whether the AI actually helps.
- **Breakdown:** results by sport, bet type, odds range, and sportsbook, plus AI vs. you.
- **Settings:** sports, a "whole week" toggle for football, unit size, loss limits, backend URL and token, and CSV export.

## Setup

### 1. Get API keys
- **Anthropic:** https://console.anthropic.com → API Keys. You pay per use. Each sport's slate costs roughly $0.50–$3 per analysis, depending on slate size and how many web searches Claude runs. Results are cached per day; you only pay again when you tap Refresh.
- **The Odds API:** https://the-odds-api.com. The free tier gives 500 requests a month. Each sport per analysis uses about 3 requests, and settling results uses about 2 per sport.

### 2. Backend (Railway)
The backend is deployed as the `bettingpicks` project at https://bettingpicks-production.up.railway.app, and `APP_TOKEN` is already set. To add your keys:

```bash
cd server
railway link            # pick the "bettingpicks" project
railway variable set ANTHROPIC_API_KEY=sk-ant-... ODDS_API_KEY=...
```

Setting variables triggers a redeploy. Check that it worked: `curl https://bettingpicks-production.up.railway.app/health` should show both keys as `true`.

To redeploy after code changes, run `railway up` from `server/`.

Run it locally instead:
```bash
cd server
cp .env.example .env    # fill in keys
npm install
npm run dev             # http://localhost:8787
npm test
```

### 3. iPhone app
Requires Xcode 16+ (iOS 17+).

```bash
cd ios
cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig   # fill in team, backend URL, APP_TOKEN
brew install xcodegen && xcodegen generate                   # only after changing project.yml
open BettingPicks.xcodeproj
```

Plug in your iPhone, select it as the run destination, and press ⌘R. The first time, iOS may ask you to trust the developer. Go to Settings → General → VPN & Device Management → your Apple ID → Trust. With a paid developer account, a dev build lasts a year before it needs reinstalling.

`Config/Secrets.xcconfig` is git-ignored, so your app token never lands in this public repo. You can also change the URL and token in the app's Settings tab.

## Notes
- AI picks are analysis, not guarantees. The model is told to rank by value and to return zero picks when it sees no edge.
- `server/railway.json` uses Railway's older config format. It works until 2026-12-01; migrate with `railway config migrate`.
- If gambling stops being fun: 1-800-GAMBLER.
