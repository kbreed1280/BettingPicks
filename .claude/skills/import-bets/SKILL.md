---
name: import-bets
description: Read sportsbook "My Bets" screenshots (FanDuel, DraftKings, etc.) and send the bets to the BettingPicks iPhone app. Use when the user says "import my bets", "read my screenshots", "log my FanDuel bets", or shares bet-slip screenshots. Runs on the user's Claude plan, not API credits.
---

# BettingPicks: import bets from screenshots

1. **Find the screenshots.** In order:
   - images the user pasted or attached in this conversation
   - recent images in `~/Downloads` (AirDrop lands there): `ls -t ~/Downloads/*.{PNG,png,JPG,jpg,jpeg,HEIC,heic} 2>/dev/null | head -20`. Use ones from the last few hours unless the user names files.
   - HEIC files: convert first with `sips -s format jpeg <in.heic> --out /tmp/<name>.jpg`
   If none are found, ask the user to AirDrop the screenshots to the Mac or paste them here.

2. **Read each screenshot** with the Read tool and extract every fully visible bet:
   - `ticket_id`: the bet ID if shown, else null
   - `placed_at`: YYYY-MM-DD if shown, else null
   - `sport`: NFL, NCAAF, NBA, NCAAB, MLB, NHL, Soccer, MMA, Golf, Tennis, or Other
   - `event`: "Away @ Home" when you can tell, otherwise as shown
   - `bet_type`: moneyline | spread | total | prop | parlay
   - `selection`: as shown, e.g. "Missouri Tigers +5.5", "Under 43.5"; for parlays a summary like "3-leg parlay"
   - `odds`: American integer (convert decimal or fractional odds)
   - `stake`: the wager in dollars (not the payout)
   - `status`: pending (open) | won | lost | push | void
   - `payout`: total return if shown, else null
   - `legs`: for parlays `[{"selection": "...", "odds": -110 or null}]`, otherwise `[]`
   Skip bets too cut off to read the stake or odds. Never guess numbers. If the same bet appears in two screenshots, include it once.

3. **Write** `/tmp/bets-import.json`:
   ```json
   {"sportsbook": "FanDuel", "bets": [ ... ]}
   ```

4. **Send** to the app inbox:
   ```
   python3 ~/BettingPicks/scripts/picks.py bets /tmp/bets-import.json
   ```

5. **Report** a short table (pick, odds, stake, status). Tell the user: in the app go to Bets → + → Import from screenshot → **Get bets from Claude Code**, review, and tap Import. Bets they already logged are skipped automatically, and settled ones update the result.
