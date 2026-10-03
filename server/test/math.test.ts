import assert from "node:assert/strict";
import { test } from "node:test";
import { americanToDecimal, expectedValue, impliedProbability, kellyFraction, noVig } from "../src/math.ts";
import { findQuote, summarizeGame } from "../src/odds.ts";

const close = (a: number, b: number, eps = 1e-4) => assert.ok(Math.abs(a - b) < eps, `${a} != ${b}`);

test("american to decimal", () => {
  close(americanToDecimal(150), 2.5);
  close(americanToDecimal(-110), 1.909090);
  close(americanToDecimal(100), 2);
  close(americanToDecimal(-100), 2);
});

test("implied probability", () => {
  close(impliedProbability(-110), 0.523809);
  close(impliedProbability(150), 0.4);
});

test("expected value and kelly", () => {
  close(expectedValue(0.5, 100), 0);
  close(expectedValue(0.55, -110), 0.55 * (100 / 110) - 0.45);
  close(kellyFraction(0.6, 100), 0.2);
  assert.equal(kellyFraction(0.4, 100), 0);
});

test("no-vig normalizes to 1", () => {
  const [a, b] = noVig([impliedProbability(-110), impliedProbability(-110)]);
  close(a, 0.5);
  close(b, 0.5);
});

test("summarizeGame picks best price on the consensus line", () => {
  const game = summarizeGame({
    id: "e1", sport_key: "basketball_nba", commence_time: "2026-10-03T23:00:00Z",
    home_team: "Lakers", away_team: "Celtics",
    bookmakers: [
      { key: "a", title: "BookA", markets: [
        { key: "h2h", outcomes: [{ name: "Lakers", price: -120 }, { name: "Celtics", price: 100 }] },
        { key: "spreads", outcomes: [{ name: "Lakers", price: -110, point: -2.5 }, { name: "Celtics", price: -110, point: 2.5 }] },
      ] },
      { key: "b", title: "BookB", markets: [
        { key: "h2h", outcomes: [{ name: "Lakers", price: -115 }, { name: "Celtics", price: -105 }] },
        { key: "spreads", outcomes: [{ name: "Lakers", price: -105, point: -2.5 }, { name: "Celtics", price: -115, point: 2.5 }] },
      ] },
      { key: "c", title: "BookC", markets: [
        { key: "spreads", outcomes: [{ name: "Lakers", price: 100, point: -3.5 }, { name: "Celtics", price: -120, point: 3.5 }] },
      ] },
    ],
  });
  const lakersML = findQuote(game, "h2h", "lakers", null)!;
  assert.equal(lakersML.bestOdds, -115);
  assert.equal(lakersML.bookmaker, "BookB");
  const lakersSpread = findQuote(game, "spreads", "Lakers", -2.5)!;
  assert.equal(lakersSpread.bestOdds, -105);
  assert.equal(findQuote(game, "spreads", "Lakers", -3.5), undefined); // not the consensus line
});
