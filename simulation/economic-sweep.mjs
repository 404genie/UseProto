import fs from "node:fs";
import config from "./economics.config.json" with {type: "json"};
import {buy, sell} from "./curve-model.mjs";

const WAD = 10n ** 18n;
const BPS = 10_000n;
const units = (n) => BigInt(Math.round(n * 1e6)) * 10n ** 12n;
const decimal = (n, scale = WAD) => Number(n) / Number(scale);
const ceilDiv = (a, b) => a === 0n ? 0n : (a - 1n) / b + 1n;

function initialVirtualQuote(targetMarketCapUsd, quoteUsd, totalSupply, virtualToken) {
  // MC = quote/token * quoteUSD * total supply.
  // Initial effective token reserve includes both virtual and real inventory.
  return ceilDiv(units(targetMarketCapUsd) * (totalSupply + virtualToken), units(quoteUsd) * totalSupply / WAD);
}

function marketCapUsd(state, quoteUsd, totalSupply) {
  const effectiveQuote = state.virtualQuote + state.realQuote;
  const effectiveToken = state.virtualToken + state.realToken;
  return decimal(effectiveQuote * totalSupply * units(quoteUsd) / effectiveToken, WAD * WAD);
}

function priceImpactBps(state, quoteIn) {
  const before = state.virtualQuote * WAD / (state.virtualToken + state.realToken);
  const [afterState, out] = buy(state, quoteIn);
  const execution = (quoteIn - quoteIn * state.feeBps / BPS) * WAD / out;
  const after = (afterState.virtualQuote + afterState.realQuote) * WAD /
    (afterState.virtualToken + afterState.realToken);
  return {
    executionBps: Number((execution - before) * BPS / before),
    postTradeBps: Number((after - before) * BPS / before),
  };
}

function safePriceImpactBps(state, quoteIn) {
  try {
    return priceImpactBps(state, quoteIn);
  } catch {
    return {executionBps: null, postTradeBps: null};
  }
}

function graduationSnapshot(initial, threshold, buySize) {
  let state = initial;
  let trades = 0;
  let purchased = 0n;
  while (state.realQuote < threshold && trades < 1_000_000) {
    const remaining = threshold - state.realQuote;
    const gross = remaining * BPS / (BPS - state.feeBps) + 1n;
    const input = gross < buySize ? gross : buySize;
    try {
      const [next, out] = buy(state, input);
      state = next;
      purchased += out;
      trades++;
    } catch {
      break;
    }
  }
  return {state, trades, purchased, reached: state.realQuote >= threshold};
}

function rng(seed) {
  let x = seed >>> 0;
  return () => ((x = (1664525 * x + 1013904223) >>> 0) / 2 ** 32);
}

function randomSolvencyRun(initial, count, seed) {
  const random = rng(seed);
  let state = initial;
  let userTokens = 0n;
  let userQuoteSpent = 0n;
  let buys = 0;
  let sells = 0;
  for (let i = 0; i < count; i++) {
    const shouldBuy = userTokens === 0n || random() < 0.58;
    if (shouldBuy) {
      const input = units(0.0001 + random() * 0.25);
      try {
        const [next, out] = buy(state, input);
        state = next;
        userTokens += out;
        userQuoteSpent += input;
        buys++;
      } catch {}
    } else {
      const fraction = BigInt(1 + Math.floor(random() * 5000));
      const input = userTokens * fraction / BPS;
      if (input === 0n) continue;
      try {
        const [next, out] = sell(state, input);
        state = next;
        userTokens -= input;
        userQuoteSpent = userQuoteSpent > out ? userQuoteSpent - out : 0n;
        sells++;
      } catch {}
    }
    if (state.realQuote < 0n || state.realToken < 0n || state.fees < 0n) {
      throw new Error(`insolvency at trade ${i}`);
    }
  }
  return {buys, sells, finalRealQuote: decimal(state.realQuote), finalRealTokens: decimal(state.realToken), fees: decimal(state.fees)};
}

const totalSupply = BigInt(config.totalSupplyTokens) * WAD;
const rows = [];
for (const quoteUsd of config.quoteUsdScenarios) {
  for (const ratioBps of config.virtualTokenRatiosBps) {
    const virtualToken = totalSupply * BigInt(ratioBps) / BPS;
    const virtualQuote = initialVirtualQuote(config.targetInitialMarketCapUsd, quoteUsd, totalSupply, virtualToken);
    for (const feeBps of config.feeBpsCandidates) {
      const initial = {realQuote: 0n, realToken: totalSupply, virtualQuote, virtualToken, feeBps: BigInt(feeBps), fees: 0n};
      for (const graduationNative of config.graduationReserveCandidatesNative) {
        const graduation = graduationSnapshot(initial, units(graduationNative), units(0.25));
        rows.push({
          quoteUsd,
          virtualTokenRatioBps: ratioBps,
          virtualQuoteNative: decimal(virtualQuote),
          feeBps,
          graduationReserveNative: graduationNative,
          startingMarketCapUsd: marketCapUsd(initial, quoteUsd, totalSupply),
          graduationMarketCapUsd: marketCapUsd(graduation.state, quoteUsd, totalSupply),
          tokensSoldPct: decimal(graduation.purchased, totalSupply) * 100,
          tradesAt025Native: graduation.trades,
          feeAccruedNative: decimal(graduation.state.fees),
          thresholdReached: graduation.reached,
        });
      }
    }
  }
}

const referenceRatioBps = 250;
const referenceFeeBps = 100;
const referenceVirtualToken = totalSupply * BigInt(referenceRatioBps) / BPS;
const referenceVirtualQuote = initialVirtualQuote(
  config.targetInitialMarketCapUsd,
  config.referenceQuoteUsd,
  totalSupply,
  referenceVirtualToken,
);
const reference = {
  realQuote: 0n,
  realToken: totalSupply,
  virtualQuote: referenceVirtualQuote,
  virtualToken: referenceVirtualToken,
  feeBps: BigInt(referenceFeeBps),
  fees: 0n,
};
const impacts = config.tradeSizesNative.map((size) => ({sizeNative: size, ...safePriceImpactBps(reference, units(size))}));
const stress = randomSolvencyRun(reference, config.randomTradeCount, config.simulationSeed);

fs.mkdirSync("simulation/output", {recursive: true});
fs.writeFileSync("simulation/output/economic-sweep.json", JSON.stringify({config, rows, reference: {
  virtualTokenRatioBps: referenceRatioBps,
  virtualQuoteNative: decimal(referenceVirtualQuote),
  feeBps: referenceFeeBps,
  impacts,
  stress,
}}, null, 2));

const selected = rows.filter((r) => r.quoteUsd === config.referenceQuoteUsd && r.virtualTokenRatioBps === referenceRatioBps && r.feeBps === referenceFeeBps);
const md = `# Proto economic sweep — frozen V1 parameters\n\n` +
`This report evaluates ${rows.length} parameter combinations and runs ${config.randomTradeCount.toLocaleString()} deterministic mixed trades. The selected V1 reference below remains subject to independent security and economic review before mainnet deployment.\n\n` +
`## Selected V1 reference\n\n- Quote/USD reference: $${config.referenceQuoteUsd.toLocaleString()}\n- Initial target market cap: $${config.targetInitialMarketCapUsd.toLocaleString()}\n- Virtual token reserve: ${referenceRatioBps / 100}% of real inventory\n- Derived virtual quote reserve: ${decimal(referenceVirtualQuote).toFixed(6)} native\n- Trading fee: ${referenceFeeBps / 100}%\n\n` +
`## Initial buy impact\n\n| Buy size | Execution impact | Post-trade spot move |\n|---:|---:|---:|\n${impacts.map((x) => x.executionBps === null ? `| ${x.sizeNative} native | unavailable | exceeds inventory |` : `| ${x.sizeNative} native | ${(x.executionBps / 100).toFixed(2)}% | ${(x.postTradeBps / 100).toFixed(2)}% |`).join("\n")}\n\n` +
`## Graduation candidates\n\n| Real reserve | Market cap at graduation | Inventory sold | Inventory left for V4 | Fees accrued |\n|---:|---:|---:|---:|---:|\n${selected.map((x) => x.thresholdReached ? `| ${x.graduationReserveNative} native | $${x.graduationMarketCapUsd.toLocaleString(undefined, {maximumFractionDigits: 0})} | ${x.tokensSoldPct.toFixed(2)}% | ${(100 - x.tokensSoldPct).toFixed(2)}% | ${x.feeAccruedNative.toFixed(4)} native |` : `| ${x.graduationReserveNative} native | unreachable | inventory exhausted | 0% | ${x.feeAccruedNative.toFixed(4)} native |`).join("\n")}\n\n` +
`## Engineering interpretation\n\nThe 5-native threshold was selected because it retains about 10% of supply for the permanent V4 position. Thresholds of 10–25 native consume roughly 96–100% of curve inventory, leaving an increasingly weak token side for graduation. The selected set accepts substantial price impact on larger early trades in exchange for retaining a meaningful token side at graduation.\n\n` +
`## Stress result\n\n${stress.buys.toLocaleString()} buys and ${stress.sells.toLocaleString()} sells completed without negative reserves. Final accounted reserves: ${stress.finalRealQuote.toFixed(6)} native and ${stress.finalRealTokens.toLocaleString(undefined, {maximumFractionDigits: 2})} tokens.\n\n` +
`## Launch reference policy\n\nA static native virtual quote reserve cannot keep the starting USD market cap near $2,000 when the native asset/USD price changes. Proto therefore derives and snapshots the virtual quote reserve at launch from a display-only quote/USD reference. The oracle/reference never participates in trade execution after initialization.\n`;
fs.writeFileSync("docs/economic-simulation-report.md", md);
console.log(`evaluated ${rows.length} candidates and ${config.randomTradeCount} mixed trades`);
