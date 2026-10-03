// Reads a sportsbook "My Bets" screenshot with Claude vision and returns the bets on it.
import Anthropic from "@anthropic-ai/sdk";
import { z } from "zod";

const client = new Anthropic({
  defaultHeaders: process.env.ANTHROPIC_WORKSPACE_ID
    ? { "anthropic-workspace-id": process.env.ANTHROPIC_WORKSPACE_ID }
    : undefined,
});

const BET_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["sportsbook", "bets"],
  properties: {
    sportsbook: { type: "string", description: "e.g. FanDuel, DraftKings; empty if unknown" },
    bets: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["ticket_id", "placed_at", "sport", "event", "bet_type", "selection", "odds", "stake", "status", "payout", "legs"],
        properties: {
          ticket_id: { type: ["string", "null"], description: "Bet ID / ticket number if visible" },
          placed_at: { type: ["string", "null"], description: "ISO date (YYYY-MM-DD) or date-time if visible" },
          sport: { type: "string", description: "NFL, NCAAF, NBA, NCAAB, MLB, NHL, Soccer, MMA, Golf, Tennis, or Other" },
          event: { type: "string", description: "Matchup, e.g. 'Florida Gators @ Missouri Tigers'" },
          bet_type: { type: "string", enum: ["moneyline", "spread", "total", "prop", "parlay"] },
          selection: { type: "string", description: "The pick as shown, e.g. 'Missouri Tigers +5.5', 'Over 47.5', 'Chiefs ML'" },
          odds: { type: "integer", description: "American odds, e.g. -110 or 250" },
          stake: { type: "number", description: "Wager amount in dollars" },
          status: { type: "string", enum: ["pending", "won", "lost", "push", "void"] },
          payout: { type: ["number", "null"], description: "Total return shown, if visible" },
          legs: {
            type: "array",
            items: {
              type: "object",
              additionalProperties: false,
              required: ["selection", "odds"],
              properties: { selection: { type: "string" }, odds: { type: ["integer", "null"] } },
            },
          },
        },
      },
    },
  },
} as const;

const Output = z.object({
  sportsbook: z.string(),
  bets: z.array(z.object({
    ticket_id: z.string().nullable(),
    placed_at: z.string().nullable(),
    sport: z.string(),
    event: z.string(),
    bet_type: z.enum(["moneyline", "spread", "total", "prop", "parlay"]),
    selection: z.string(),
    odds: z.number().int(),
    stake: z.number(),
    status: z.enum(["pending", "won", "lost", "push", "void"]),
    payout: z.number().nullable(),
    legs: z.array(z.object({ selection: z.string(), odds: z.number().int().nullable() })),
  })),
});

export type ImportedBets = z.infer<typeof Output>;

const PROMPT = `This is a screenshot of a sportsbook app's bet history ("My Bets"). Extract every bet that is fully or mostly visible.

- Open/active bets are "pending". Settled bets: "won", "lost", "push" (tie/refunded), or "void" (cancelled).
- Odds must be American. Convert decimal or fractional odds if that's what is shown.
- For parlays/same-game parlays: bet_type "parlay", list each leg in legs (with its odds if shown), odds = the combined price, selection = a short summary like "3-leg parlay".
- For straight bets, legs is an empty array.
- Use the stake (wager) amount, not the payout, for stake.
- Write the event as "Away @ Home" when you can tell which team is home, otherwise as shown.
- Skip bets cut off so badly that you can't read the stake or odds. Never guess numbers you can't see.
- If the image is not a bet history screen, return an empty bets array.`;

export async function extractBets(imageBase64: string, mediaType: "image/jpeg" | "image/png" | "image/webp"): Promise<ImportedBets> {
  if (!process.env.ANTHROPIC_API_KEY) throw new Error("ANTHROPIC_API_KEY is not set");
  const message = await client.beta.messages.create({
    model: "claude-opus-5-5",
    max_tokens: 16000,
    betas: ["server-side-fallback-2026-07-01"],
    fallbacks: "default",
    output_config: {
      effort: "medium",
      format: { type: "json_schema", schema: BET_SCHEMA as unknown as Record<string, unknown> },
    },
    messages: [{
      role: "user",
      content: [
        { type: "image", source: { type: "base64", media_type: mediaType, data: imageBase64 } },
        { type: "text", text: PROMPT },
      ],
    }],
  });
  if (message.stop_reason === "refusal") throw new Error("The model declined to read this image");
  if (message.stop_reason === "max_tokens") throw new Error("Too many bets in one screenshot; try a smaller one");
  const text = message.content
    .filter((b): b is Anthropic.Beta.BetaTextBlock => b.type === "text")
    .map((b) => b.text)
    .join("");
  const parsed = Output.parse(JSON.parse(text));
  console.log(`[import] ${parsed.bets.length} bets from ${parsed.sportsbook || "unknown book"} ` +
    `(${message.usage.input_tokens} in / ${message.usage.output_tokens} out tokens)`);
  return parsed;
}
