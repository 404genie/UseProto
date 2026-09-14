# Proto V1 terminal integration kit

This kit is for wallets, trading terminals, portfolio trackers, and aggregators that want to display or trade Proto pre-graduation tokens on Robinhood Chain.

The supplied ABI entries are ethers-compatible human-readable ABI fragments. The same signatures can be converted to JSON ABI objects for viem, web3.js, or another client library.

## Network and contracts

Proto V1 currently runs on Robinhood Chain mainnet:

| Field | Value |
| --- | --- |
| Chain ID | `4663` |
| Native quote asset | ETH |
| RPC | `https://rpc.mainnet.chain.robinhood.com` |
| Explorer | `https://robinhoodchain.blockscout.com` |

Use `deployment.json` as the source of truth for the deployed contract addresses. Do not discover or substitute protocol addresses from an arbitrary deployment.

## Market model

Each token has a Proto token contract and a dedicated bonding-curve contract before graduation. Resolve the curve from `ProtoCore.tokenInfo(token).curve` or `ProtoCore.curveOf(token)`.

Pre-graduation trades are not ordinary DEX swaps. They must go through `ProtoRouter`:

- Buy native ETH with `router.buy(curve, recipient, minTotalOut, deadline)` and pass ETH as `msg.value`.
- Sell liquid Proto tokens with `router.sell(curve, tokenIn, minQuoteOut, deadline, recipient)`.
- The router applies the 1% trading fee and enforces allocation limits.
- The recipient receives up to its 2% liquid cap. Any excess is committed automatically to the vesting vault for 30-day linear vesting.
- A terminal must never call `BondingCurve.buy` or `BondingCurve.sell` directly for user execution.

The 2% cap is 20,000,000 tokens for a fresh address under the current 1,000,000,000-token supply. Read `token.maxLiquidBalance()` and `token.liquidCapacity(recipient)` instead of hard-coding this in UI logic.

## Discovery and indexing

Index either `ProtoCore.TokenRegistered` or `ProtoFactory.TokenLaunched`, then hydrate the token with:

1. `core.tokenInfo(token)` for creator, curve, launch price, launch time, lifecycle, and metadata URI.
2. ERC-20 `name`, `symbol`, `decimals`, `totalSupply`.
3. Curve state and reserves from the bonding-curve ABI.

Use `ProtoRouter.ProtectedBuy`, `ProtectedSell`, `ProtectedV4Buy`, and `ProtectedV4Sell` as the canonical trade records. If you also index curve-level `Bought`/`Sold`, deduplicate by transaction hash and log identity so volume is not counted twice.

For a token page, quote-asset volume is the sum of the canonical router trade amounts. Pre-graduation buy volume uses `ProtectedBuy.total`; sell volume uses `ProtectedSell.quoteOut`. Do not multiply, scale, or infer volume from a chart price.

## Quotes and execution

For an active curve:

```js
const [tokenOut, fee] = await curve.quoteBuy(quoteInWei);
const [quoteOut, fee, grossQuoteOut] = await curve.quoteSell(tokenInWei);
```

`quoteBuy` takes the total ETH the user will send and returns total token output plus the fee. `quoteSell` returns net ETH output, the fee, and gross ETH output.

Recommended transaction flow:

1. Read lifecycle and curve state immediately before quoting.
2. Quote the exact input amount.
3. Apply the terminal’s user-selected slippage tolerance to the quoted output. Pass the result as `minTotalOut` for buys or `minQuoteOut` for sells.
4. Use a short deadline, normally 5–10 minutes from signing, and refresh the quote if it expires.
5. Simulate or estimate gas, then ask the user to sign the router transaction.
6. Wait for the receipt and index the canonical router event.

The relevant custom errors include `DeadlineExpired`, `SlippageExceeded`, `PartialFill`, `UnknownCurve`, and `InvalidInput`. A failed transaction should be surfaced as a failed quote/execution, not recorded as volume.

For sells, the user must approve the router for the token amount first:

```js
await token.approve(deployment.contracts.router, tokenInWei);
```

An infinite approval is optional; a terminal should let users choose its approval policy.

## Graduation and post-graduation routing

Read `core.tokenInfo(token).lifecycle` or `core.isGraduated(token)`:

| Lifecycle | Meaning | Terminal route |
| --- | --- | --- |
| `0` | NONE | Not a tradable Proto market |
| `1` | ACTIVE_CURVE | ProtoRouter curve methods |
| `2` | GRADUATING | Pause new curve orders and refresh state |
| `3` | GRADUATED | ProtoRouter V4 methods / Uniswap V4 integration |

When `GraduationManager.Graduated` is observed, read `core.poolOf(token)` and `core.positionOf(token)`. Do not assume the pool ID from token metadata. For a graduated market, use `router.buyV4` and `router.sellV4`, with the documented V4 price-limit constants or a terminal-specific limit derived from a fresh quote.

## Balances, vesting, and rewards

Show these as separate balances:

- Liquid: `token.balanceOf(user)`.
- Committed: `vestingVault.committedBalance(token, user)`.
- Claimable: `vestingVault.claimable(token, user, maxPositions)`.
- Holder rewards: `rewardEngine.earned(token, user)`.

Claim committed tokens with `vestingVault.claim(token, maxPositions)` and claim holder rewards with `rewardEngine.claim(token, recipient)`. Both are user-signed transactions. The claim call is bounded by the user’s current liquid capacity; a terminal should expose the claimable amount returned by the read call and explain when only part of a position can be released.

## Price movement and analytics

The launch oracle price is a USD reference used to initialize the curve; it is not a substitute for the observed market return. For all-time percentage movement, use the first valid recorded trade price and the latest valid recorded trade price, with the same price convention throughout the series. If there is no valid baseline, display `0%` or `N/A` rather than manufacturing a value.

Keep quote-asset amounts in wei on the indexer and format them as ETH only at the presentation layer. This avoids discrepancies between Explore and token detail pages.

## Security and UX requirements

- Verify chain ID `4663` before presenting a signing flow.
- Verify token and curve relationships from `core.tokenInfo` and `curve.token`.
- Use only the official deployment addresses in `deployment.json`.
- Route all pre-graduation execution through `ProtoRouter`.
- Re-quote after lifecycle changes, account changes, or a stale quote.
- Show the liquid/committed split for every buy.
- Never treat a reverted transaction as a fill or volume event.
- Keep private keys and wallet credentials outside this kit; transactions should be signed by the user’s wallet.

## Suggested integration checklist

- [ ] Add Robinhood Chain network metadata and chain ID `4663`.
- [ ] Add the contract addresses and ABI fragments from this kit.
- [ ] Index launch, graduation, and canonical router trade events.
- [ ] Build a token resolver using `tokenInfo` and `curveOf`.
- [ ] Implement curve quote, slippage, deadline, approval, and router execution.
- [ ] Display liquid, committed, claimable, and holder-reward balances separately.
- [ ] Switch routing when lifecycle changes to `GRADUATED`.
- [ ] Add receipt/event-based fill accounting and deduplication.

The repository SDK in `sdk/` contains an ethers implementation of these reads and writes. `example-ethers.mjs` shows the minimum read/quote/transaction-data flow without holding a private key.
