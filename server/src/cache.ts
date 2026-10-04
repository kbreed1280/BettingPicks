// Tiny JSON-file cache so each day/sport is analyzed once unless the user
// asks for a refresh. On Railway, attach a volume at DATA_DIR to keep it
// across deploys; without one it simply resets on redeploy.
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import path from "node:path";

const DATA_DIR = process.env.DATA_DIR ?? "./data";
const FILE = path.join(DATA_DIR, "cache.json");

let store: Record<string, unknown> = {};
try {
  store = JSON.parse(readFileSync(FILE, "utf8"));
} catch {
  store = {};
}

/** "2026-10-03:americanfootball_ncaaf:day": one day's picks for one sport. */
export const PICK_KEY = /^\d{4}-\d{2}-\d{2}:[a-z_]+:day$/;

/** All cached entries whose key matches. */
export function entries<T>(pattern: RegExp): Array<[string, T]> {
  return Object.entries(store).filter(([k]) => pattern.test(k)) as Array<[string, T]>;
}

export function getCached<T>(key: string): T | undefined {
  return store[key] as T | undefined;
}

export function setCached(key: string, value: unknown): void {
  store[key] = value;
  // Keys start with YYYY-MM-DD. Uploaded picks ("…:day") are the AI's permanent track
  // record, kept for a year; everything else (odds, spend) only ~2 weeks.
  const dayAgo = (n: number) => new Date(Date.now() - n * 864e5).toISOString().slice(0, 10);
  const shortCutoff = dayAgo(14), longCutoff = dayAgo(400);
  for (const k of Object.keys(store)) {
    const cutoff = PICK_KEY.test(k) ? longCutoff : shortCutoff;
    if (k.slice(0, 10) < cutoff) delete store[k];
  }
  mkdirSync(DATA_DIR, { recursive: true });
  writeFileSync(FILE, JSON.stringify(store));
}
