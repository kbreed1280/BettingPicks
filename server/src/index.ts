import express, { type NextFunction, type Request, type Response } from "express";
import { analyzeGames, ModelOutput, scorePicks, type Pick } from "./analyze.ts";
import { getCached, setCached } from "./cache.ts";
import { extractBets } from "./importer.ts";
import { fetchGames, fetchScores, SUPPORTED_SPORTS, type GameSummary } from "./odds.ts";

interface SportPicks {
  sport: string;
  league: string;
  date: string;
  generatedAt: string;
  gameCount: number;
  slateNotes: string;
  picks: Pick[];
  /** "running" while Claude is still analyzing; the app polls until "done". */
  status: "running" | "done" | "error" | "none";
  source?: "claude-code" | "api";
  costUSD?: number;
  error?: string;
}

/** Re-running a slate costs real money; ignore refreshes more often than this. */
const REFRESH_COOLDOWN_MS = Number(process.env.REFRESH_COOLDOWN_MIN ?? 120) * 60 * 1000;
/** How long a request waits for a running analysis before telling the app to poll. */
const WAIT_MS = 20_000;

const app = express();
app.use(express.json({ limit: "15mb" })); // screenshot uploads

// Shared secret so a stranger who finds the URL can't spend your API credits.
app.use((req: Request, res: Response, next: NextFunction) => {
  const token = process.env.APP_TOKEN;
  if (!token || req.path === "/health" || req.get("x-app-token") === token) return next();
  res.status(401).json({ error: "Missing or wrong x-app-token" });
});

app.get("/health", (_req, res) => {
  res.json({
    ok: true,
    spentTodayUSD: Number(spentToday().toFixed(2)),
    dailyBudgetUSD: DAILY_BUDGET_USD,
    anthropicKey: Boolean(process.env.ANTHROPIC_API_KEY),
    oddsKey: Boolean(process.env.ODDS_API_KEY),
  });
});

app.get("/sports", (_req, res) => {
  res.json(Object.entries(SUPPORTED_SPORTS).map(([key, name]) => ({ key, name })));
});

/** Odds fetches are cached for 10 minutes per sport+window to save Odds API quota. */
const gamesCache = new Map<string, { at: number; games: GameSummary[] }>();
const GAMES_TTL_MS = 10 * 60 * 1000;

async function getGames(sport: string, from: Date, to: Date): Promise<GameSummary[]> {
  const key = `${sport}:${from.toISOString()}:${to.toISOString()}`;
  const hit = gamesCache.get(key);
  if (hit && Date.now() - hit.at < GAMES_TTL_MS) return hit.games;
  const games = await fetchGames(sport, from, to);
  gamesCache.set(key, { at: Date.now(), games });
  return games;
}

/** Paid in-app analysis (API credits). Off by default: picks come from Claude Code uploads. */
const APP_ANALYSIS = process.env.ALLOW_APP_ANALYSIS === "true";

// Analyses run in the background: a slate can take 5-15 minutes, longer than
// Railway's proxy will hold a request open. Same day+sport shares one job.
const inFlight = new Map<string, Promise<SportPicks>>();

// Hard spending cap. Each analysis's cost is recorded; once today's total (UTC day)
// reaches DAILY_BUDGET_USD, no new analyses start until tomorrow.
const DAILY_BUDGET_USD = Number(process.env.DAILY_BUDGET_USD ?? 2);

function spentToday(): number {
  return getCached<number>(`${new Date().toISOString().slice(0, 10)}:spend`) ?? 0;
}

function recordSpend(usd: number): void {
  const key = `${new Date().toISOString().slice(0, 10)}:spend`;
  setCached(key, spentToday() + usd);
}

function startAnalysis(key: string, sport: string, date: string, from: Date, to: Date): Promise<SportPicks> {
  const running = inFlight.get(key);
  if (running) return running;
  if (spentToday() >= DAILY_BUDGET_USD) {
    return Promise.resolve({
      sport, league: SUPPORTED_SPORTS[sport], date, generatedAt: new Date().toISOString(), gameCount: 0,
      slateNotes: "", picks: [], status: "error",
      error: `Daily AI budget of $${DAILY_BUDGET_USD.toFixed(2)} reached ($${spentToday().toFixed(2)} spent). Resets tomorrow; change DAILY_BUDGET_USD in Railway to adjust.`,
    });
  }
  const job = (async (): Promise<SportPicks> => {
    const league = SUPPORTED_SPORTS[sport];
    const games = (await getGames(sport, from, to)).filter((g) => new Date(g.startTime) > new Date());
    const base = { sport, league, date, generatedAt: new Date().toISOString(), gameCount: games.length, status: "done" as const };
    if (games.length === 0) {
      const empty = { ...base, slateNotes: "No upcoming games with odds.", picks: [] };
      setCached(key, empty);
      return empty;
    }
    const result = await analyzeGames(sport, date, games);
    recordSpend(result.usage.costUSD);
    const value = { ...base, slateNotes: result.slateNotes, picks: result.picks, costUSD: result.usage.costUSD };
    setCached(key, value);
    return value;
  })()
    .catch((err: Error): SportPicks => {
      console.error(`[picks] ${sport} failed:`, err);
      return {
        sport, league: SUPPORTED_SPORTS[sport], date, generatedAt: new Date().toISOString(),
        gameCount: 0, slateNotes: "", picks: [], status: "error", error: err.message,
      };
    })
    .finally(() => setTimeout(() => inFlight.delete(key), 60_000)); // let pollers see the result

  inFlight.set(key, job);
  return job;
}

async function picksForSport(sport: string, date: string, from: Date, to: Date, refresh: boolean, window: string): Promise<SportPicks> {
  const key = `${date}:${sport}:${window}`;
  const cached = getCached<SportPicks>(key);
  const fresh = cached && Date.now() - new Date(cached.generatedAt).getTime() < REFRESH_COOLDOWN_MS;
  if (!APP_ANALYSIS && !inFlight.get(key)) {
    if (cached) return { ...cached, status: "done" };
    return {
      sport, league: SUPPORTED_SPORTS[sport], date, generatedAt: new Date().toISOString(), gameCount: 0,
      slateNotes: "", picks: [], status: "none",
    };
  }
  const job = inFlight.get(key) ?? (cached && (!refresh || fresh) ? undefined : startAnalysis(key, sport, date, from, to));
  if (!job) return { ...cached!, status: "done" };

  const timeout = new Promise<null>((r) => setTimeout(() => r(null), WAIT_MS));
  const result = await Promise.race([job, timeout]);
  if (result) return result;
  return {
    sport, league: SUPPORTED_SPORTS[sport], date, generatedAt: new Date().toISOString(), gameCount: 0,
    slateNotes: "", picks: cached?.picks ?? [], status: "running",
  };
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
      return picksForSport(sport, date, from, end, refresh, window);
    }),
  );

  const picks = results.flatMap((r) => r.picks).sort((a, b) => b.edge - a.edge);
  res.json({ date, sports: results.map(({ picks: _p, ...rest }) => rest), picks });
});

// GET /games?sports=...&from=<ISO>&to=<ISO>&window=week
// The schedule with best available lines, for browsing games in the app.
// Cached for 10 minutes per request shape to save Odds API quota.
app.get("/games", async (req, res) => {
  const sports = parseSports(req.query.sports);
  const from = req.query.from ? new Date(String(req.query.from)) : new Date();
  const to = req.query.to ? new Date(String(req.query.to)) : new Date(from.getTime() + 864e5);
  const weekWindow = req.query.window === "week";
  try {
    const all = await Promise.all(sports.map(async (sport) => {
      const end = weekWindow && sport.startsWith("americanfootball_") ? new Date(from.getTime() + 7 * 864e5) : to;
      return getGames(sport, from, end);
    }));
    res.json(all.flat().sort((a, b) => a.startTime.localeCompare(b.startTime)));
  } catch (err) {
    res.status(502).json({ error: (err as Error).message });
  }
});

// POST /picks/upload  - picks researched in Claude Code (on the user's Claude plan).
// Body: { sport, date, from, to, slate_notes, picks: [...] } using the same pick fields
// as the in-app analysis. Prices are re-checked against live odds before saving.
app.post("/picks/upload", async (req, res) => {
  const { sport, date, from, to } = req.body ?? {};
  if (!(sport in SUPPORTED_SPORTS) || typeof date !== "string" || !from || !to) {
    res.status(400).json({ error: "Need sport, date (YYYY-MM-DD), from, to (ISO) and picks" });
    return;
  }
  const parsed = ModelOutput.safeParse({ slate_notes: req.body.slate_notes ?? "", picks: req.body.picks ?? [] });
  if (!parsed.success) {
    res.status(400).json({ error: "Invalid picks", details: parsed.error.issues.slice(0, 5) });
    return;
  }
  try {
    const games = await getGames(sport, new Date(from), new Date(to));
    const picks = scorePicks(sport, games, parsed.data);
    const value: SportPicks = {
      sport, league: SUPPORTED_SPORTS[sport], date, generatedAt: new Date().toISOString(),
      gameCount: games.length, slateNotes: parsed.data.slate_notes, picks, status: "done", source: "claude-code",
    };
    setCached(`${date}:${sport}:day`, value);
    const dropped = parsed.data.picks.length - picks.length;
    console.log(`[upload] ${sport} ${date}: ${picks.length} picks saved, ${dropped} dropped`);
    res.json({ saved: picks.length, dropped, picks: picks.map((p) => `${p.event}: ${p.selection} ${p.point ?? ""} ${p.best_odds} (${p.bookmaker}) edge ${(p.edge * 100).toFixed(1)}%`) });
  } catch (err) {
    res.status(502).json({ error: (err as Error).message });
  }
});

// POST /import/screenshot  {"image": "<base64>", "mediaType": "image/jpeg"}
// Reads a sportsbook "My Bets" screenshot and returns the bets on it.
app.post("/import/screenshot", async (req, res) => {
  const { image, mediaType } = req.body ?? {};
  if (typeof image !== "string" || !["image/jpeg", "image/png", "image/webp"].includes(mediaType)) {
    res.status(400).json({ error: "Send {image: base64, mediaType: image/jpeg|image/png|image/webp}" });
    return;
  }
  try {
    res.json(await extractBets(image, mediaType));
  } catch (err) {
    console.error("[import] failed:", err);
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
