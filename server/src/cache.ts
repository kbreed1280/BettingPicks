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

export function getCached<T>(key: string): T | undefined {
  return store[key] as T | undefined;
}

export function setCached(key: string, value: unknown): void {
  store[key] = value;
  // Drop entries older than ~2 weeks (keys start with YYYY-MM-DD).
  const cutoff = new Date(Date.now() - 14 * 864e5).toISOString().slice(0, 10);
  for (const k of Object.keys(store)) if (k.slice(0, 10) < cutoff) delete store[k];
  mkdirSync(DATA_DIR, { recursive: true });
  writeFileSync(FILE, JSON.stringify(store));
}
