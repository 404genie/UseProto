import fs from "node:fs";

const BPS = 10_000n;
const ceilDiv = (a, b) => a === 0n ? 0n : (a - 1n) / b + 1n;

export function buy(s, quoteIn) {
  const fee = quoteIn * s.feeBps / BPS;
  const net = quoteIn - fee;
  const x = s.virtualQuote + s.realQuote;
  const y = s.virtualToken + s.realToken;
  const out = y - ceilDiv(x * y, x + net);
  if (out <= 0n || out > s.realToken) throw new Error("insufficient token inventory");
  return [{...s, realQuote: s.realQuote + net, realToken: s.realToken - out, fees: s.fees + fee}, out];
}

export function sell(s, tokenIn) {
  const x = s.virtualQuote + s.realQuote;
  const y = s.virtualToken + s.realToken;
  const gross = x - ceilDiv(x * y, y + tokenIn);
  if (gross <= 0n || gross > s.realQuote) throw new Error("insufficient quote reserve");
  const fee = gross * s.feeBps / BPS;
  return [{...s, realQuote: s.realQuote - gross, realToken: s.realToken + tokenIn, fees: s.fees + fee}, gross - fee];
}

export function simulate(config) {
  let state = {...config, fees: 0n};
  const rows = [];
  for (let i = 1; i <= config.steps; i++) {
    const [next, out] = buy(state, config.buySize);
    state = next;
    rows.push({step: i, quoteIn: config.buySize.toString(), tokenOut: out.toString(), realQuote: state.realQuote.toString(), realToken: state.realToken.toString()});
  }
  return {state, rows};
}

if (import.meta.url === `file://${process.argv[1]}`) {
  // Provisional example only; production parameters require a quote/USD reference and scenario sweep.
  const E = 10n ** 18n;
  const result = simulate({realQuote: 0n, realToken: 1_000_000_000n * E, virtualQuote: 10n * E, virtualToken: 200_000_000n * E, feeBps: 100n, steps: 20, buySize: E});
  fs.mkdirSync("simulation/output", {recursive: true});
  fs.writeFileSync("simulation/output/provisional.json", JSON.stringify(result, (_, v) => typeof v === "bigint" ? v.toString() : v, 2));
  console.log(`simulated ${result.rows.length} buys; real quote=${result.state.realQuote}`);
}
