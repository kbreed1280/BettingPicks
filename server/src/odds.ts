// Client for The Odds API (https://the-odds-api.com), plus helpers that boil
// each game's bookmaker lines down to the best price per outcome.
import { impliedProbability, noVig, round } from "./math.ts";

const BASE = "https://api.the-odds-api.com/v4";

export const SUPPORTED_SPORTS: Record<string, string> = {
  americanfootball_nfl: "NFL",
  americanfootball_ncaaf: "NCAAF",
  basketball_nba: "NBA",
  basketball_wnba: "WNBA",
  basketball_ncaab: "NCAAB",
  baseball_mlb: "MLB",
  icehockey_nhl: "NHL",
  soccer_epl: "EPL",
  soccer_usa_mls: "MLS",
  mma_mixed_martial_arts: "MMA",
};

export type MarketKey = "h2h" | "spreads" | "totals";

interface RawOutcome { name: string; price: number; point?: number }
interface RawMarket { key: MarketKey; outcomes: RawOutcome[] }
interface RawBookmaker { key: string; title: string; markets: RawMarket[] }
interface RawGame {
  id: string;
  sport_key: string;
  commence_time: string;
  home_team: string;
  away_team: string;
  bookmakers: RawBookmaker[];
}

export interface PriceQuote {
  /** Team name, or "Over" / "Under" for totals. */
  name: string;
  point: number | null;
  bestOdds: number;
  bookmaker: string;
  /** Market consensus win probability with the vig removed. */
  fairProbability: number;
  booksOffering: number;
}

export interface GameSummary {
  eventId: string;
  sportKey: string;
  league: string;
  startTime: string;
  homeTeam: string;
  awayTeam: string;
  markets: Partial<Record<MarketKey, PriceQuote[]>>;
}

export interface ScoreResult {
  eventId: string;
  sportKey: string;
  completed: boolean;
  homeTeam: string;
  awayTeam: string;
  homeScore: number | null;
  awayScore: number | null;
}

function apiKey(): string {
  const key = process.env.ODDS_API_KEY;
  if (!key) throw new Error("ODDS_API_KEY is not set");
  return key;
}

/** The Odds API rejects milliseconds in timestamps. */
function isoNoMillis(d: Date): string {
  return d.toISOString().replace(/\.\d{3}Z$/, "Z");
}

async function getJSON<T>(url: URL): Promise<T> {
  const res = await fetch(url);
  const remaining = res.headers.get("x-requests-remaining");
  if (remaining) console.log(`[odds] requests remaining this month: ${remaining}`);
  if (!res.ok) {
    throw new Error(`Odds API ${res.status}: ${await res.text()}`);
  }
  return (await res.json()) as T;
}

export async function fetchGames(sportKey: string, from: Date, to: Date): Promise<GameSummary[]> {
  const url = new URL(`${BASE}/sports/${sportKey}/odds`);
  url.searchParams.set("apiKey", apiKey());
  url.searchParams.set("regions", "us");
  url.searchParams.set("markets", "h2h,spreads,totals");
  url.searchParams.set("oddsFormat", "american");
  url.searchParams.set("commenceTimeFrom", isoNoMillis(from));
  url.searchParams.set("commenceTimeTo", isoNoMillis(to));
  const games = await getJSON<RawGame[]>(url);
  return games.map(summarizeGame);
}

export async function fetchScores(sportKey: string, daysFrom = 3): Promise<ScoreResult[]> {
  const url = new URL(`${BASE}/sports/${sportKey}/scores`);
  url.searchParams.set("apiKey", apiKey());
  url.searchParams.set("daysFrom", String(daysFrom));
  const raw = await getJSON<Array<{
    id: string; sport_key: string; completed: boolean; home_team: string; away_team: string;
    scores: Array<{ name: string; score: string }> | null;
  }>>(url);
  return raw.map((g) => {
    const scoreFor = (team: string) => {
      const s = g.scores?.find((x) => x.name === team)?.score;
      return s === undefined ? null : Number(s);
    };
    return {
      eventId: g.id,
      sportKey: g.sport_key,
      completed: g.completed,
      homeTeam: g.home_team,
      awayTeam: g.away_team,
      homeScore: scoreFor(g.home_team),
      awayScore: scoreFor(g.away_team),
    };
  });
}

/**
 * Collapses every bookmaker's lines into one quote per outcome:
 * the most widely offered line (spread/total point), at the best price any book has for it.
 */
export function summarizeGame(game: RawGame): GameSummary {
  const markets: GameSummary["markets"] = {};
  for (const marketKey of ["h2h", "spreads", "totals"] as const) {
    // name -> point -> list of { price, book }
    const byOutcome = new Map<string, Map<number | null, Array<{ price: number; book: string }>>>();
    for (const book of game.bookmakers) {
      const market = book.markets.find((m) => m.key === marketKey);
      if (!market) continue;
      for (const o of market.outcomes) {
        const point = o.point ?? null;
        const lines = byOutcome.get(o.name) ?? new Map();
        const offers = lines.get(point) ?? [];
        offers.push({ price: o.price, book: book.title });
        lines.set(point, offers);
        byOutcome.set(o.name, lines);
      }
    }
    if (byOutcome.size === 0) continue;

    const quotes: PriceQuote[] = [];
    for (const [name, lines] of byOutcome) {
      // Consensus line = offered by the most books.
      const [point, offers] = [...lines.entries()].sort((a, b) => b[1].length - a[1].length)[0];
      const best = offers.reduce((a, b) => (b.price > a.price ? b : a));
      const avgImplied = offers.reduce((s, o) => s + impliedProbability(o.price), 0) / offers.length;
      quotes.push({
        name,
        point,
        bestOdds: best.price,
        bookmaker: best.book,
        fairProbability: avgImplied, // normalized below
        booksOffering: offers.length,
      });
    }
    const fair = noVig(quotes.map((q) => q.fairProbability));
    quotes.forEach((q, i) => (q.fairProbability = round(fair[i])));
    markets[marketKey] = quotes;
  }

  return {
    eventId: game.id,
    sportKey: game.sport_key,
    league: SUPPORTED_SPORTS[game.sport_key] ?? game.sport_key,
    startTime: game.commence_time,
    homeTeam: game.home_team,
    awayTeam: game.away_team,
    markets,
  };
}

/** Finds the quote matching a pick's market/selection/point, if the game offers it. */
export function findQuote(
  game: GameSummary,
  market: MarketKey,
  selection: string,
  point: number | null,
): PriceQuote | undefined {
  const quotes = game.markets[market] ?? [];
  const norm = (s: string) => s.trim().toLowerCase();
  return quotes.find(
    (q) => norm(q.name) === norm(selection) && (market === "h2h" || q.point === point),
  );
}
