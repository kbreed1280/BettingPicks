// Live scores from ESPN's public scoreboard feed. It's free and needs no key, so
// it doesn't use Odds API quota. Unofficial, so callers should treat it as best-effort.
const ESPN_PATHS: Record<string, string> = {
  americanfootball_nfl: "football/nfl",
  americanfootball_ncaaf: "football/college-football?groups=80",
  basketball_nba: "basketball/nba",
  basketball_wnba: "basketball/wnba",
  basketball_ncaab: "basketball/mens-college-basketball?groups=50",
  baseball_mlb: "baseball/mlb",
  icehockey_nhl: "hockey/nhl",
  soccer_epl: "soccer/eng.1",
  soccer_usa_mls: "soccer/usa.1",
};

export interface LiveGame {
  sportKey: string;
  homeTeam: string;
  awayTeam: string;
  homeScore: number | null;
  awayScore: number | null;
  /** "pre" | "in" | "post" */
  state: string;
  /** e.g. "Q3 5:21", "Halftime", "Final", "Final/OT" */
  detail: string;
  startTime: string;
  /** Team name with the ball (football), if known. */
  possession: string | null;
}

const cache = new Map<string, { at: number; games: LiveGame[] }>();
const TTL_MS = 30_000;

/** date: "YYYYMMDD" (ESPN accepts one day per request) */
export async function fetchLive(sportKey: string, dates: string): Promise<LiveGame[]> {
  const path = ESPN_PATHS[sportKey];
  if (!path) return [];
  const key = `${sportKey}:${dates}`;
  const hit = cache.get(key);
  if (hit && Date.now() - hit.at < TTL_MS) return hit.games;

  const [base, query] = path.split("?");
  const url = new URL(`https://site.api.espn.com/apis/site/v2/sports/${base}/scoreboard`);
  if (query) new URLSearchParams(query).forEach((v, k) => url.searchParams.set(k, v));
  url.searchParams.set("dates", dates);
  url.searchParams.set("limit", "300");
  const res = await fetch(url);
  if (!res.ok) throw new Error(`ESPN ${res.status}`);
  const data = (await res.json()) as { events?: any[] };

  const games: LiveGame[] = (data.events ?? []).map((e) => {
    const c = e.competitions?.[0] ?? {};
    const team = (side: string) => c.competitors?.find((t: any) => t.homeAway === side);
    const home = team("home"), away = team("away");
    const state = e.status?.type?.state ?? "pre";
    const score = (t: any) => (state === "pre" || t?.score === undefined ? null : Number(t.score));
    const possId = c.situation?.possession;
    const poss = possId ? c.competitors?.find((t: any) => t.team?.id === possId)?.team?.displayName ?? null : null;
    return {
      sportKey,
      homeTeam: home?.team?.displayName ?? "",
      awayTeam: away?.team?.displayName ?? "",
      homeScore: score(home),
      awayScore: score(away),
      state,
      detail: e.status?.type?.shortDetail ?? "",
      startTime: new Date(e.date).toISOString(),
      possession: poss,
    };
  });
  cache.set(key, { at: Date.now(), games });
  return games;
}
