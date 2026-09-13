import test from "node:test";
import assert from "node:assert/strict";
import {
  BUY_SQRT_PRICE_LIMIT_X96,
  LIFECYCLE,
  ROBINHOOD_CHAIN_ID,
  SELL_SQRT_PRICE_LIMIT_X96,
  lifecycleName,
  normalizeDeployment,
  requireDeadline
} from "../sdk/index.mjs";

const addresses = {
  core: "0xFe90351A8bA46eC552A85A1F07628690dbf9AEE7",
  factory: "0xd711cBDfa3Fecfc3DC3e99bea6313c0a52aC5BAA",
  router: "0x820234d85e2d197ee066CA00512e87c3D20F520c",
  rewardEngine: "0x007E033Bb6F52326AB61dC48e011f9698bD144B4",
  feeController: "0x5efA300548750Aa63b15f9B123c1b896657fD199",
  vestingVault: "0x4b04bc845221B7A1fdf76e603D2274Bb3322b130",
  graduationManager: "0xf5d2061475D2b06588ab9E17F96F0c855e0eEd84"
};

test("normalizes the Robinhood deployment manifest", () => {
  const result = normalizeDeployment({ chainId: Number(ROBINHOOD_CHAIN_ID), proto: addresses });
  assert.equal(result.chainId, ROBINHOOD_CHAIN_ID);
  assert.equal(result.router, addresses.router);
});

test("rejects incomplete or non-Robinhood deployments", () => {
  assert.throws(() => normalizeDeployment({ chainId: 1, proto: addresses }), /only supports Robinhood/);
  assert.throws(() => normalizeDeployment({ chainId: Number(ROBINHOOD_CHAIN_ID), proto: { core: addresses.core } }), /missing factory/);
});

test("keeps lifecycle and V4 limits explicit", () => {
  assert.equal(LIFECYCLE[1], "ACTIVE_CURVE");
  assert.equal(lifecycleName(3), "GRADUATED");
  assert.equal(BUY_SQRT_PRICE_LIMIT_X96, 4_295_128_740n);
  assert.equal(SELL_SQRT_PRICE_LIMIT_X96 > BUY_SQRT_PRICE_LIMIT_X96, true);
});

test("requires a finite positive deadline value", () => {
  assert.equal(requireDeadline("1789227757"), 1_789_227_757n);
  assert.throws(() => requireDeadline(0), /positive unix timestamp/);
});
