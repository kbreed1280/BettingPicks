// Sends a day's games + odds to Claude, which researches news, injuries and
// expert picks on the web, then returns structured picks. Pricing math
// (implied probability, edge, EV) is recomputed here from real odds so the
// numbers shown in the app never depend on the model's arithmetic.
import Anthropic from "@anthropic-ai/sdk";
import { z } from "zod";
import { findQuote, type GameSummary, type MarketKey } from "./odds.ts";
import { expectedValue, impliedProbability, kellyFraction, round } from "./math.ts";

const MODEL = "claude-opus-5-5";

// Claude Opus 5.5 list prices (USD per million tokens) + web search ($10 / 1,000), for cost logging.
const PRICE = { input: 4, cacheWrite: 5, cacheRead: 0.2, output: 20, perSearch: 0.01 };
// Reads ANTHROPIC_API_KEY. Keys not scoped to a workspace (sk-ant-usr-...) must
// also name one, via ANTHROPIC_WORKSPACE_ID.
const client = new Anthropic({
  defaultHeaders: process.env.ANTHROPIC_WORKSPACE_ID
    ? { "anthropic-workspace-id": process.env.ANTHROPIC_WORKSPACE_ID }
    : undefined,
});

const SYSTEM_PROMPT = `You are a disciplined, data-driven sports betting analyst. Your job is to find bets where the true win probability is higher than the odds imply - positive expected value - not simply the teams most likely to win.

Process:
1. Scan every game you are given, then shortlist the 4-6 most promising ones to research. You have only about 8 searches, so search efficiently (one search can cover several games, e.g. "college football expert picks week 6") and skip games where the line looks efficient. Each market lists the best available price and a no-vig "fairProbability" from the market consensus.
2. Research with web search before deciding. For each game worth a closer look, check same-day injuries, confirmed lineups/starters, rest and travel, weather for outdoor games, and recent form.
3. Scour the web for expert analysis and picks for today's games (for example Action Network, Covers, ESPN, CBS Sports, The Athletic, VSiN, Pickswise, OddsShark, Dimers, and well-known handicappers). Note which side the experts favor, how lopsided the consensus is, and any public-betting vs. sharp-money splits you find. Fetch an article when a search snippet is not enough.
4. Form your own probability estimate. Expert consensus is evidence, not the answer: popular public sides are often overpriced, and disagreeing with the experts is fine when your reasoning supports it. Say so when you do.
5. Rank by edge (your probability minus the implied probability of the best price). A -500 favorite that wins 80% of the time is a bad bet; say why a line is mispriced.

Rules:
- Only return a pick when you see a real edge. Returning zero picks is acceptable.
- At most 8 picks with tier "best"; up to 5 more with tier "lean" for smaller edges.
- Use only games, markets, selections and points that appear in the provided data. Copy event_id exactly. For moneyline and spread picks, selection is the exact team name; for totals it is "Over" or "Under". point is the spread or total line (null for moneyline).
- Avoid correlated picks on the same game.
- Be honest about uncertainty. Never call anything a lock or a guarantee.
- confidence is 1 (thin edge) to 5 (strong edge with corroborating info). suggested_units is 0.5 to 3.
- Every reasoning bullet should be specific (names, numbers, news). Put source URLs for expert picks and news in sources.`;

// JSON schema for structured output. Kept to the subset structured outputs supports.
const PICK_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["picks", "slate_notes"],
  properties: {
    slate_notes: { type: "string", description: "1-3 sentences on the day's slate overall." },
    picks: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: [
          "event_id", "market", "selection", "point", "ai_estimated_probability",
          "confidence", "suggested_units", "tier", "reasoning", "key_risks",
          "expert_consensus", "sources",
        ],
        properties: {
          event_id: { type: "string" },
          market: { type: "string", enum: ["moneyline", "spread", "total"] },
          selection: { type: "string" },
          point: { type: ["number", "null"] },
          ai_estimated_probability: { type: "number", description: "Your true win probability, 0-1." },
          confidence: { type: "integer", enum: [1, 2, 3, 4, 5] },
          suggested_units: { type: "number" },
          tier: { type: "string", enum: ["best", "lean"] },
          reasoning: { type: "array", items: { type: "string" } },
          key_risks: { type: "array", items: { type: "string" } },
          expert_consensus: {
            type: "object",
            additionalProperties: false,
            required: ["summary", "experts_agreeing", "experts_disagreeing"],
            properties: {
              summary: { type: "string", description: "Who the experts are picking and how lopsided it is." },
              experts_agreeing: { type: "array", items: { type: "string" } },
              experts_disagreeing: { type: "array", items: { type: "string" } },
            },
          },
          sources: { type: "array", items: { type: "string", description: "URL" } },
        },
      },
    },
  },
} as const;

export const ModelOutput = z.object({
  slate_notes: z.string(),
  picks: z.array(z.object({
    event_id: z.string(),
    market: z.enum(["moneyline", "spread", "total"]),
    selection: z.string(),
    point: z.number().nullable(),
    ai_estimated_probability: z.number().min(0).max(1),
    confidence: z.number().int().min(1).max(5),
    suggested_units: z.number(),
    tier: z.enum(["best", "lean"]),
    reasoning: z.array(z.string()),
    key_risks: z.array(z.string()),
    expert_consensus: z.object({
      summary: z.string(),
      experts_agreeing: z.array(z.string()),
      experts_disagreeing: z.array(z.string()),
    }),
    sources: z.array(z.string()),
  })),
});

export interface Pick {
  id: string;
  event_id: string;
  sport: string;
  league: string;
  event: string;
  home_team: string;
  away_team: string;
  start_time: string;
  market: "moneyline" | "spread" | "total";
  selection: string;
  point: number | null;
  best_odds: number;
  bookmaker: string;
  implied_probability: number;
  market_fair_probability: number;
  ai_estimated_probability: number;
  edge: number;
  expected_value: number;
  kelly_fraction: number;
  confidence: number;
  suggested_units: number;
  tier: "best" | "lean";
  reasoning: string[];
  key_risks: string[];
  expert_consensus: { summary: string; experts_agreeing: string[]; experts_disagreeing: string[] };
  sources: string[];
}

export interface AnalysisResult {
  picks: Pick[];
  slateNotes: string;
  usage: { inputTokens: number; outputTokens: number; webSearches: number; model: string; costUSD: number };
}

const MARKET_KEY: Record<Pick["market"], MarketKey> = {
  moneyline: "h2h",
  spread: "spreads",
  total: "totals",
};

// Extra, sport-specific things to research. Football is the main use case.
const SPORT_NOTES: Record<string, string> = {
  americanfootball_nfl: `NFL notes: weigh QB and offensive-line injuries most heavily (check the final injury report and inactives). Respect key numbers 3, 7, 10 and 6 when judging spreads - half a point through 3 or 7 matters a lot. Check wind/rain/snow for outdoor stadiums (wind 15+ mph suppresses totals), short weeks (Thursday games), travel and rest, divisional familiarity, and EPA/success-rate matchups. Look for line movement vs. betting splits (reverse line movement suggests sharp action).`,
  americanfootball_ncaaf: `College football notes: the slate is large - prioritize games where you can find a concrete angle rather than researching every game equally. Check QB status, opt-outs/transfers, depth-chart news, motivation and lookahead spots, rivalry games, travel across time zones, weather, and tempo (pace drives totals). Big spreads between mismatched teams often have backdoor-cover risk. Use advanced stats (SP+, FPI, EPA per play, havoc rate) when you can find them, and compare against expert picks from college football analysts.`,
};

export async function analyzeGames(sportKey: string, date: string, games: GameSummary[]): Promise<AnalysisResult> {
  if (!process.env.ANTHROPIC_API_KEY) throw new Error("ANTHROPIC_API_KEY is not set");
  const isFootball = sportKey.startsWith("americanfootball_");
  const userPrompt = `Today is ${date}. Analyze this ${games[0]?.league ?? sportKey} slate and return your picks.
${SPORT_NOTES[sportKey] ?? ""}

Games and best available odds (American), with no-vig market probabilities:
${JSON.stringify(games)}`;

  const messages: Anthropic.Beta.BetaMessageParam[] = [{ role: "user", content: userPrompt }];
  const usage = { inputTokens: 0, outputTokens: 0, webSearches: 0, model: MODEL, costUSD: 0 };
  let cacheRead = 0;
  let cacheWrite = 0;
  let final: Anthropic.Beta.BetaMessage | undefined;

  // Web search runs server-side; a long research turn can come back as
  // pause_turn, in which case we append it and let Claude continue.
  for (let i = 0; i < 6; i++) {
    const stream = client.beta.messages.stream({
      model: MODEL,
      max_tokens: 64000,
      betas: ["server-side-fallback-2026-07-01"],
      fallbacks: "default",
      thinking: { type: "adaptive" },
      // Each research step re-reads the whole conversation (games + search results);
      // caching makes those re-reads ~20x cheaper.
      cache_control: { type: "ephemeral" },
      output_config: {
        effort: "high",
        format: { type: "json_schema", schema: PICK_SCHEMA as unknown as Record<string, unknown> },
      },
      system: SYSTEM_PROMPT,
      tools: [
        { type: "web_search_20260209", name: "web_search", max_uses: Number(process.env.MAX_SEARCHES ?? 8) },
        { type: "web_fetch_20260209", name: "web_fetch", max_uses: 2 },
      ],
      messages,
    });
    const message = await stream.finalMessage();
    usage.inputTokens += message.usage.input_tokens;
    cacheRead += message.usage.cache_read_input_tokens ?? 0;
    cacheWrite += message.usage.cache_creation_input_tokens ?? 0;
    usage.outputTokens += message.usage.output_tokens;
    usage.webSearches += message.usage.server_tool_use?.web_search_requests ?? 0;
    usage.model = message.model;

    if (message.stop_reason === "pause_turn") {
      messages.push({ role: "assistant", content: message.content });
      continue;
    }
    final = message;
    break;
  }

  if (!final) throw new Error("Analysis did not finish (too many pause_turn iterations)");
  if (final.stop_reason === "refusal") throw new Error("The model declined to analyze this slate");
  if (final.stop_reason === "max_tokens") throw new Error("Analysis was cut off (max_tokens)");

  const text = final.content
    .filter((b): b is Anthropic.Beta.BetaTextBlock => b.type === "text")
    .map((b) => b.text)
    .join("")
    .trim();
  const parsed = ModelOutput.parse(JSON.parse(text));

  usage.costUSD = round(
    (usage.inputTokens * PRICE.input + cacheWrite * PRICE.cacheWrite + cacheRead * PRICE.cacheRead +
      usage.outputTokens * PRICE.output) / 1e6 + usage.webSearches * PRICE.perSearch,
    2,
  );
  console.log(
    `[claude] ${sportKey} ${date}: ${usage.inputTokens} in (+${cacheRead} cached read, ${cacheWrite} cache write) / ` +
      `${usage.outputTokens} out tokens, ${usage.webSearches} web searches, model ${usage.model}, ~$${usage.costUSD}`,
  );

  return { picks: scorePicks(sportKey, games, parsed), slateNotes: parsed.slate_notes, usage };
}

/**
 * Turns picks (from the API analysis or uploaded from Claude Code) into app picks.
 * Prices come from the real odds data, never the model, and picks without an edge
 * at the real price are dropped.
 */
export function scorePicks(sportKey: string, games: GameSummary[], parsed: z.infer<typeof ModelOutput>): Pick[] {
  const gamesById = new Map(games.map((g) => [g.eventId, g]));
  const picks: Pick[] = [];
  for (const p of parsed.picks) {
    const game = gamesById.get(p.event_id);
    const quote = game && findQuote(game, MARKET_KEY[p.market], p.selection, p.point);
    if (!game || !quote) {
      console.warn(`[picks] dropped pick not found in odds data: ${p.event_id} ${p.market} ${p.selection} ${p.point}`);
      continue;
    }
    const implied = impliedProbability(quote.bestOdds);
    const edge = p.ai_estimated_probability - implied;
    if (edge <= 0) continue; // no value at the real price
    picks.push({
      id: `${p.event_id}:${p.market}:${quote.name}:${quote.point ?? ""}`,
      event_id: p.event_id,
      sport: sportKey,
      league: game.league,
      event: `${game.awayTeam} @ ${game.homeTeam}`,
      home_team: game.homeTeam,
      away_team: game.awayTeam,
      start_time: game.startTime,
      market: p.market,
      selection: quote.name,
      point: quote.point,
      best_odds: quote.bestOdds,
      bookmaker: quote.bookmaker,
      implied_probability: round(implied),
      market_fair_probability: quote.fairProbability,
      ai_estimated_probability: round(p.ai_estimated_probability),
      edge: round(edge),
      expected_value: round(expectedValue(p.ai_estimated_probability, quote.bestOdds)),
      kelly_fraction: round(kellyFraction(p.ai_estimated_probability, quote.bestOdds)),
      confidence: p.confidence,
      suggested_units: Math.min(3, Math.max(0.5, p.suggested_units)),
      tier: p.tier,
      reasoning: p.reasoning,
      key_risks: p.key_risks,
      expert_consensus: p.expert_consensus,
      sources: p.sources,
    });
  }
  return picks;
}
