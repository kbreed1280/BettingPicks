import express, { type NextFunction, type Request, type Response } from "express";
import { analyzeGames, type Pick } from "./analyze.ts";
import { getCached, setCached } from "./cache.ts";
import { fetchGames, fetchScores, SUPPORTED_SPORTS, type GameSummary } from "./odds.ts";

interface SportPicks {
  sport: string;
  league: string;
  date: string;
  generatedAt: string;
  gameCount: number;
  slateNotes: string;
  picks: Pick[];
  error?: string;
}

const app = express();

// Shared secret so a stranger who finds the URL can't spend your API credits.
app.use((req: Request, res: Response, next: NextFunction) => {
  const token = process.env.APP_TOKEN;
  if (!token || req.path === "/health" || req.get("x-app-token") === token) return next();
  res.status(401).json({ error: "Missing or wrong x-app-token" });
});

app.get("/health", (_req, res) => {
  res.json({
    ok: true,
    anthropicKey: Boolean(process.env.ANTHROPIC_API_KEY),
    oddsKey: Boolean(process.env.ODDS_API_KEY),
  });
});

app.get("/sports", (_req, res) => {
  res.json(Object.entries(SUPPORTED_SPORTS).map(([key, name]) => ({ key, name })));
});

// Same day+sport requested twice at once shares one analysis.
const inFlight = new Map<string, Promise<SportPicks>>();

async function picksForSport(sport: string, date: string, from: Date, to: Date, refresh: boolean, window: string): Promise<SportPicks> {
  const key = `${date}:${sport}:${window}`;
  const cached = getCached<SportPicks>(key);
  if (cached && !refresh) return cached;
  const running = inFlight.get(key);
  if (running) return running;

  const job = (async () => {
    const league = SUPPORTED_SPORTS[sport];
    const games = (await fetchGames(sport, from, to)).filter((g) => new Date(g.startTime) > new Date());
    const base = { sport, league, date, generatedAt: new Date().toISOString(), gameCount: games.length };
    if (games.length === 0) {
      const empty = { ...base, slateNotes: "No upcoming games with odds.", picks: [] };
      setCached(key, empty);
      return empty;
    }
    const result = await analyzeGames(sport, date, games);
    const value = { ...base, slateNotes: result.slateNotes, picks: result.picks };
    setCached(key, value);
    return value;
  })().finally(() => inFlight.delete(key));

  inFlight.set(key, job);
  return job;
}

function parseSports(raw: unknown): string[] {
  const list = String(raw ?? "").split(",").map((s) => s.trim()).filter(Boolean);
  return list.filter((s) => s in SUPPORTED_SPORTS);
}

// GET /picks/today?sports=americanfootball_nfl,americanfootball_ncaaf&date=2026-10-03&from=<ISO>&to=<ISO>&window=week&refresh=1
// date/from/to describe the user's local day; they default to the next 24h in UTC.
// window=week widens football (played weekly) to the next 7 days so Sunday's NFL
// games show up on any day of the week; other sports always use the day window.
app.get("/picks/today", async (req, res) => {
  const sports = parseSports(req.query.sports);
  if (sports.length === 0) {
    res.status(400).json({ error: `Pass sports=<comma list>. Supported: ${Object.keys(SUPPORTED_SPORTS).join(", ")}` });
    return;
  }
  const from = req.query.from ? new Date(String(req.query.from)) : new Date();
  const to = req.query.to ? new Date(String(req.query.to)) : new Date(from.getTime() + 864e5);
  const date = String(req.query.date ?? from.toISOString().slice(0, 10));
  const refresh = req.query.refresh === "1" || req.query.refresh === "true";
  const weekWindow = req.query.window === "week";

  const results = await Promise.all(
    sports.map((sport) => {
      const football = sport.startsWith("americanfootball_");
      const window = weekWindow && football ? "week" : "day";
      const end = window === "week" ? new Date(from.getTime() + 7 * 864e5) : to;
      return picksForSport(sport, date, from, end, refresh, window).catch((err: Error): SportPicks => {
        console.error(`[picks] ${sport} failed:`, err);
        return {
          sport, league: SUPPORTED_SPORTS[sport], date, generatedAt: new Date().toISOString(),
          gameCount: 0, slateNotes: "", picks: [], error: err.message,
        };
      });
    }),
  );

  const picks = results.flatMap((r) => r.picks).sort((a, b) => b.edge - a.edge);
  res.json({ date, sports: results.map(({ picks: _p, ...rest }) => rest), picks });
});

// GET /games?sports=...&from=<ISO>&to=<ISO>&window=week
// The schedule with best available lines, for browsing games in the app.
// Cached for 10 minutes per request shape to save Odds API quota.
const gamesCache = new Map<string, { at: number; games: GameSummary[] }>();
const GAMES_TTL_MS = 10 * 60 * 1000;

app.get("/games", async (req, res) => {
  const sports = parseSports(req.query.sports);
  const from = req.query.from ? new Date(String(req.query.from)) : new Date();
  const to = req.query.to ? new Date(String(req.query.to)) : new Date(from.getTime() + 864e5);
  const weekWindow = req.query.window === "week";
  try {
    const all = await Promise.all(sports.map(async (sport) => {
      const end = weekWindow && sport.startsWith("americanfootball_") ? new Date(from.getTime() + 7 * 864e5) : to;
      const key = `${sport}:${from.toISOString()}:${end.toISOString()}`;
      const hit = gamesCache.get(key);
      if (hit && Date.now() - hit.at < GAMES_TTL_MS) return hit.games;
      const games = await fetchGames(sport, from, end);
      gamesCache.set(key, { at: Date.now(), games });
      return games;
    }));
    res.json(all.flat().sort((a, b) => a.startTime.localeCompare(b.startTime)));
  } catch (err) {
    res.status(502).json({ error: (err as Error).message });
  }
});

// GET /scores?sports=basketball_nba,icehockey_nhl  - recent final scores for settling picks.
app.get("/scores", async (req, res) => {
  const sports = parseSports(req.query.sports);
  try {
    const all = await Promise.all(sports.map((s) => fetchScores(s, 3)));
    res.json(all.flat().filter((s) => s.completed));
  } catch (err) {
    res.status(502).json({ error: (err as Error).message });
  }
});

const port = Number(process.env.PORT ?? 8787);
app.listen(port, () => console.log(`BettingPicks server listening on :${port}`));
