// Odds math shared by the odds summarizer and pick scoring.
// All odds are American (e.g. -110, +150).

export function americanToDecimal(american: number): number {
  if (american === 0) throw new Error("American odds cannot be 0");
  return american > 0 ? 1 + american / 100 : 1 + 100 / Math.abs(american);
}

/** Break-even probability implied by a price (includes the book's vig). */
export function impliedProbability(american: number): number {
  return 1 / americanToDecimal(american);
}

/** Expected profit per 1 unit staked, given a true win probability. */
export function expectedValue(winProbability: number, american: number): number {
  const profitIfWin = americanToDecimal(american) - 1;
  return winProbability * profitIfWin - (1 - winProbability);
}

/** Removes the vig from a set of mutually exclusive outcome probabilities. */
export function noVig(probabilities: number[]): number[] {
  const total = probabilities.reduce((a, b) => a + b, 0);
  return total > 0 ? probabilities.map((p) => p / total) : probabilities;
}

/** Full-Kelly stake as a fraction of bankroll (0 when there is no edge). */
export function kellyFraction(winProbability: number, american: number): number {
  const b = americanToDecimal(american) - 1;
  const f = (b * winProbability - (1 - winProbability)) / b;
  return Math.max(0, f);
}

export function round(value: number, places = 4): number {
  const m = 10 ** places;
  return Math.round(value * m) / m;
}
