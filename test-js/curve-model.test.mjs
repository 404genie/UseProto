import test from "node:test";
import assert from "node:assert/strict";
import {buy, sell} from "../simulation/curve-model.mjs";

const E = 10n ** 18n;
const initial = () => ({realQuote: 0n, realToken: 1_000_000_000n * E, virtualQuote: E, virtualToken: 200_000_000n * E, feeBps: 100n, fees: 0n});

test("buy then full sell cannot return more quote", () => {
  const input = E / 10n;
  const [afterBuy, tokens] = buy(initial(), input);
  const [afterSell, output] = sell(afterBuy, tokens);
  assert.ok(output < input);
  assert.ok(afterSell.realQuote >= 0n);
  assert.equal(afterSell.realToken, initial().realToken);
});

test("buy raises spot price and sell lowers it", () => {
  const spot = (s) => (s.virtualQuote + s.realQuote) * E / (s.virtualToken + s.realToken);
  const start = initial();
  const [afterBuy, tokens] = buy(start, E);
  const [afterSell] = sell(afterBuy, tokens / 2n);
  assert.ok(spot(afterBuy) > spot(start));
  assert.ok(spot(afterSell) < spot(afterBuy));
});
