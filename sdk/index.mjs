import { ethers } from "ethers";
import {
  CORE_ABI,
  CURVE_ABI,
  FACTORY_ABI,
  FEE_ABI,
  GRADUATION_ABI,
  REWARD_ABI,
  ROUTER_ABI,
  TOKEN_ABI,
  VESTING_ABI
} from "./abis.mjs";

export const ROBINHOOD_CHAIN_ID = 46630n;
export const MAX_UINT256 = (1n << 256n) - 1n;
export const BUY_SQRT_PRICE_LIMIT_X96 = 4_295_128_740n;
export const SELL_SQRT_PRICE_LIMIT_X96 =
  1_461_446_703_485_210_103_287_273_052_203_988_822_378_723_970_341n;

export const LIFECYCLE = Object.freeze({
  0: "NONE",
  1: "ACTIVE_CURVE",
  2: "GRADUATING",
  3: "GRADUATED"
});

const ADDRESS_KEYS = [
  "core",
  "factory",
  "router",
  "rewardEngine",
  "feeController",
  "vestingVault",
  "graduationManager",
  "graduationAdapter",
  "liquidityLocker",
  "hookCreate2Deployer",
  "hook",
  "poolManager",
  "positionManager",
  "permit2",
  "wrappedNative",
  "launchPriceOracle"
];

export function normalizeDeployment(input) {
  if (!input || typeof input !== "object") throw new TypeError("deployment is required");
  const chainId = BigInt(input.chainId ?? ROBINHOOD_CHAIN_ID);
  if (chainId !== ROBINHOOD_CHAIN_ID) {
    throw new Error(`Proto V1 only supports Robinhood Chain (${ROBINHOOD_CHAIN_ID})`);
  }
  const source = {
    ...(input.external ?? {}),
    ...(input.proto ?? {}),
    ...input
  };
  const addresses = {};
  for (const key of ADDRESS_KEYS) {
    const value = source[key];
    if (value == null || value === "") continue;
    addresses[key] = ethers.getAddress(value);
  }
  for (const key of ["core", "factory", "router", "rewardEngine", "feeController", "vestingVault", "graduationManager"]) {
    if (!addresses[key]) throw new Error(`deployment is missing ${key}`);
  }
  return Object.freeze({ chainId, ...addresses });
}

export function lifecycleName(value) {
  const numeric = typeof value === "bigint" ? Number(value) : Number(value);
  return LIFECYCLE[numeric] ?? `UNKNOWN_${numeric}`;
}

export function requireDeadline(deadline) {
  const value = BigInt(deadline);
  if (value <= 0n) throw new Error("deadline must be a positive unix timestamp");
  return value;
}

function asBigInt(value, field) {
  try {
    return BigInt(value);
  } catch {
    throw new TypeError(`${field} must be an integer-like value`);
  }
}

function requireAddress(value, field) {
  try {
    return ethers.getAddress(value);
  } catch {
    throw new TypeError(`${field} must be a valid address`);
  }
}

export class ProtoClient {
  constructor({ rpcUrl, provider, signer, deployment } = {}) {
    if (!provider && !rpcUrl) throw new TypeError("rpcUrl or provider is required");
    this.provider = provider ?? new ethers.JsonRpcProvider(rpcUrl, Number(ROBINHOOD_CHAIN_ID));
    this.signer = signer ?? null;
    this.deployment = normalizeDeployment(deployment);
  }

  static fromRpc({ rpcUrl, privateKey, deployment }) {
    const provider = new ethers.JsonRpcProvider(rpcUrl, Number(ROBINHOOD_CHAIN_ID));
    const signer = privateKey ? new ethers.Wallet(privateKey, provider) : null;
    return new ProtoClient({ provider, signer, deployment });
  }

  async assertNetwork() {
    const network = await this.provider.getNetwork();
    if (network.chainId !== ROBINHOOD_CHAIN_ID) {
      throw new Error(`wrong network: expected ${ROBINHOOD_CHAIN_ID}, got ${network.chainId}`);
    }
    return network;
  }

  async account() {
    if (!this.signer) return null;
    return ethers.getAddress(await this.signer.getAddress());
  }

  _contract(address, abi, write = false) {
    const target = requireAddress(address, "contract address");
    if (write && !this.signer) throw new Error("a signer is required for this operation");
    return new ethers.Contract(target, abi, write ? this.signer : this.provider);
  }

  _read(name, abi) {
    return this._contract(this.deployment[name], abi, false);
  }

  _write(name, abi) {
    return this._contract(this.deployment[name], abi, true);
  }

  async getTokenInfo(token) {
    const address = requireAddress(token, "token");
    const [info, name, symbol, totalSupply] = await Promise.all([
      this._read("core", CORE_ABI).tokenInfo(address),
      this._contract(address, TOKEN_ABI).name(),
      this._contract(address, TOKEN_ABI).symbol(),
      this._contract(address, TOKEN_ABI).totalSupply()
    ]);
    return {
      token: address,
      creator: ethers.getAddress(info.creator),
      curve: ethers.getAddress(info.curve),
      launchPriceUsd8: BigInt(info.launchPriceUsd8),
      virtualQuoteReserve: BigInt(info.virtualQuoteReserve),
      launchedAt: BigInt(info.launchedAt),
      lifecycle: Number(info.lifecycle),
      lifecycleName: lifecycleName(info.lifecycle),
      metadataURI: info.metadataURI,
      name,
      symbol,
      totalSupply: BigInt(totalSupply)
    };
  }

  async getCurveState(curve) {
    const address = requireAddress(curve, "curve");
    const contract = this._contract(address, CURVE_ABI);
    const [token, state, realQuoteReserve, realTokenReserve, virtualQuoteReserve, virtualTokenReserve, graduationThreshold, tradingFeeBps, spotPriceWad, reservesReconcile] = await Promise.all([
      contract.token(),
      contract.state(),
      contract.realQuoteReserve(),
      contract.realTokenReserve(),
      contract.virtualQuoteReserve(),
      contract.virtualTokenReserve(),
      contract.graduationThreshold(),
      contract.tradingFeeBps(),
      contract.spotPriceWad(),
      contract.reservesReconcile()
    ]);
    return {
      curve: address,
      token: ethers.getAddress(token),
      state: Number(state),
      stateName: lifecycleName(Number(state) + 1),
      realQuoteReserve: BigInt(realQuoteReserve),
      realTokenReserve: BigInt(realTokenReserve),
      virtualQuoteReserve: BigInt(virtualQuoteReserve),
      virtualTokenReserve: BigInt(virtualTokenReserve),
      graduationThreshold: BigInt(graduationThreshold),
      graduationProgressBps: graduationThreshold === 0n
        ? 0n
        : (BigInt(realQuoteReserve) * 10_000n) / BigInt(graduationThreshold),
      tradingFeeBps: BigInt(tradingFeeBps),
      spotPriceWad: BigInt(spotPriceWad),
      reservesReconcile: Boolean(reservesReconcile)
    };
  }

  async quoteBuy(curve, quoteIn) {
    const [tokenOut, fee] = await this._contract(curve, CURVE_ABI).quoteBuy(asBigInt(quoteIn, "quoteIn"));
    return { tokenOut: BigInt(tokenOut), fee: BigInt(fee), netQuoteIn: asBigInt(quoteIn, "quoteIn") - BigInt(fee) };
  }

  async quoteSell(curve, tokenIn) {
    const [quoteOut, fee, grossQuoteOut] = await this._contract(curve, CURVE_ABI).quoteSell(asBigInt(tokenIn, "tokenIn"));
    return { quoteOut: BigInt(quoteOut), fee: BigInt(fee), grossQuoteOut: BigInt(grossQuoteOut) };
  }

  async createToken({ name, symbol, metadataURI = "" } = {}) {
    return this._write("factory", FACTORY_ABI).createToken(name, symbol, metadataURI);
  }

  async approveRouter(token, amount = MAX_UINT256) {
    return this._contract(token, TOKEN_ABI, true).approve(this.deployment.router, asBigInt(amount, "amount"));
  }

  async buy({ curve, recipient, value, minTotalOut = 0n, deadline } = {}) {
    const account = recipient ?? await this.account();
    return this._write("router", ROUTER_ABI).buy(
      requireAddress(curve, "curve"),
      requireAddress(account, "recipient"),
      asBigInt(minTotalOut, "minTotalOut"),
      requireDeadline(deadline),
      { value: asBigInt(value, "value") }
    );
  }

  async sell({ curve, tokenIn, recipient, minQuoteOut = 0n, deadline } = {}) {
    const account = recipient ?? await this.account();
    return this._write("router", ROUTER_ABI).sell(
      requireAddress(curve, "curve"),
      asBigInt(tokenIn, "tokenIn"),
      asBigInt(minQuoteOut, "minQuoteOut"),
      requireDeadline(deadline),
      requireAddress(account, "recipient")
    );
  }

  async buyV4({ token, recipient, value, minTotalOut = 0n, sqrtPriceLimitX96 = BUY_SQRT_PRICE_LIMIT_X96, deadline } = {}) {
    const account = recipient ?? await this.account();
    return this._write("router", ROUTER_ABI).buyV4(
      requireAddress(token, "token"),
      requireAddress(account, "recipient"),
      asBigInt(minTotalOut, "minTotalOut"),
      asBigInt(sqrtPriceLimitX96, "sqrtPriceLimitX96"),
      requireDeadline(deadline),
      { value: asBigInt(value, "value") }
    );
  }

  async quoteBuyV4({ token, recipient, value, sqrtPriceLimitX96 = BUY_SQRT_PRICE_LIMIT_X96, deadline } = {}) {
    const account = recipient ?? await this.account();
    const [totalOut, liquid, committed] = await this._contract(this.deployment.router, ROUTER_ABI).buyV4.staticCall(
      requireAddress(token, "token"),
      requireAddress(account, "recipient"),
      0n,
      asBigInt(sqrtPriceLimitX96, "sqrtPriceLimitX96"),
      requireDeadline(deadline),
      { value: asBigInt(value, "value"), from: requireAddress(account, "recipient") }
    );
    return { totalOut: BigInt(totalOut), liquid: BigInt(liquid), committed: BigInt(committed) };
  }

  async sellV4({ token, tokenIn, recipient, minQuoteOut = 0n, sqrtPriceLimitX96 = SELL_SQRT_PRICE_LIMIT_X96, deadline } = {}) {
    const account = recipient ?? await this.account();
    return this._write("router", ROUTER_ABI).sellV4(
      requireAddress(token, "token"),
      asBigInt(tokenIn, "tokenIn"),
      requireAddress(account, "recipient"),
      asBigInt(minQuoteOut, "minQuoteOut"),
      asBigInt(sqrtPriceLimitX96, "sqrtPriceLimitX96"),
      requireDeadline(deadline)
    );
  }

  async quoteSellV4({ token, tokenIn, recipient, sqrtPriceLimitX96 = SELL_SQRT_PRICE_LIMIT_X96, deadline } = {}) {
    const account = recipient ?? await this.account();
    const quoteOut = await this._contract(this.deployment.router, ROUTER_ABI).sellV4.staticCall(
      requireAddress(token, "token"),
      asBigInt(tokenIn, "tokenIn"),
      requireAddress(account, "recipient"),
      0n,
      asBigInt(sqrtPriceLimitX96, "sqrtPriceLimitX96"),
      requireDeadline(deadline),
      { from: requireAddress(account, "recipient") }
    );
    return { quoteOut: BigInt(quoteOut) };
  }

  async getVestingPosition(token, beneficiary, index = 0n) {
    const asset = requireAddress(token, "token");
    const user = requireAddress(beneficiary, "beneficiary");
    const position = await this._read("vestingVault", VESTING_ABI).getPosition(asset, user, asBigInt(index, "index"));
    return { amount: BigInt(position.amount), claimed: BigInt(position.claimed), start: BigInt(position.start) };
  }

  async getVestingState(token, beneficiary, maxPositions = 50n) {
    const asset = requireAddress(token, "token");
    const user = requireAddress(beneficiary, "beneficiary");
    const vault = this._read("vestingVault", VESTING_ABI);
    const [committed, claimable, positionCount] = await Promise.all([
      vault.committedBalance(asset, user),
      vault.claimable(asset, user, asBigInt(maxPositions, "maxPositions")),
      vault.positionCount(asset, user)
    ]);
    return { token: asset, beneficiary: user, committed: BigInt(committed), claimable: BigInt(claimable), positionCount: BigInt(positionCount) };
  }

  async claimVested(token, maxPositions = 50n) {
    return this._write("vestingVault", VESTING_ABI).claim(requireAddress(token, "token"), asBigInt(maxPositions, "maxPositions"));
  }

  async getRewardBalance(token, user) {
    const account = requireAddress(user ?? await this.account(), "user");
    return BigInt(await this._read("rewardEngine", REWARD_ABI).earned(requireAddress(token, "token"), account));
  }

  async claimRewards(token, recipient) {
    const account = recipient ?? await this.account();
    return this._write("rewardEngine", REWARD_ABI).claim(requireAddress(token, "token"), requireAddress(account, "recipient"));
  }

  async getCreatorFees(creator) {
    return BigInt(await this._read("feeController", FEE_ABI).creatorClaimable(requireAddress(creator, "creator")));
  }

  async claimCreatorFees(recipient) {
    const account = recipient ?? await this.account();
    return this._write("feeController", FEE_ABI).claimCreatorFees(requireAddress(account, "recipient"));
  }

  async getGraduationProgress(token) {
    const info = await this.getTokenInfo(token);
    const curve = await this.getCurveState(info.curve);
    return {
      token: info.token,
      lifecycle: info.lifecycle,
      lifecycleName: info.lifecycleName,
      realQuoteReserve: curve.realQuoteReserve,
      graduationThreshold: curve.graduationThreshold,
      progressBps: curve.graduationProgressBps > 10_000n ? 10_000n : curve.graduationProgressBps,
      poolId: info.lifecycle === 3 ? await this._read("core", CORE_ABI).poolOf(info.token) : null,
      positionId: info.lifecycle === 3 ? BigInt(await this._read("core", CORE_ABI).positionOf(info.token)) : null
    };
  }

  async graduate(token) {
    return this._write("graduationManager", GRADUATION_ABI).graduate(requireAddress(token, "token"));
  }
}

export { ethers };
