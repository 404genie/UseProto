# Proto V1 — Clean-room protocol core

Clean-room implementation of Proto's native-quote, constant-product-style bonding curve.

## Current scope

- `CurveMath`: conservative integer arithmetic for buy/sell quotes.
- `BondingCurve`: native quote execution, slippage/deadline checks, reserve reconciliation, fee isolation, and reentrancy protection.
- Unit, fuzz, and stateful invariant tests.
- BigInt off-chain simulation model matching the Solidity formulas.
- `ProtoToken`: fixed supply, immutable ProtoCore reference, explicit system classification, and 2% liquid-cap enforcement.
- `VestingVault`: token-backed 30-day linear vesting with bounded tranche processing and capacity-safe partial claims.
- Stateful invariants for fixed supply, liquid caps, vault solvency, and token conservation.
- `FeeController`: exact 15/35/50 fee conservation with pull-based creator/protocol claims.
- `RewardEngine`: O(1) committed-balance reward index and pull-based reward claims.
- `ProtoRouter`: registered-curve execution, protected liquid/committed allocation, fee forwarding, deadlines, and slippage enforcement.
- `ProtoRouter` also executes protected post-graduation V4 exact-input swaps through PoolManager unlock callbacks, with the same fee split, cap, vesting, deadline, and slippage rules.
- `ProtoCore`: canonical launch registry, lifecycle metadata, and explicit system-address registry.
- `ProtoFactory`: permissionless fixed-economics launches with a freshness-checked, launch-only native/USD snapshot.
- `GraduationManager` and `LiquidityLocker`: atomic asset handoff and permanent V4-position custody.
- `V4GraduationAdapter`: canonical V4 PositionManager pool initialization and full-range position minting; the Robinhood testnet Cancun opcode gate has passed.
- `ProtoHook` and `HookCreate2Deployer`: canonical-pool authorization and deterministic deployment with V4's required address permission bits.
- Canonical V4 integration tests deploy the real `PoolManager`, Permit2, `PositionManager`, and a permission-bit-correct Proto hook; they prove that graduation mints the actual position NFT directly to `LiquidityLocker` and that protected buys/sells settle through the real manager.
- A Robinhood-testnet-only infrastructure bootstrap plus two-stage `DeployBase`, `ConfigureV4`, and read-only `VerifyDeployment` scripts remove constructor cycles while preserving permanent one-time wiring; see `docs/deployment.md`.

The SDK and frontend are not included yet. Robinhood Chain testnet's required Cancun opcodes have been verified as documented in `docs/v4-compatibility.md`; production deployment addresses and final economic parameters still need to be frozen.

The launch-pricing decision is recorded in `docs/adr-001-launch-price-snapshot.md`: native/USD is read only at launch to derive an immutable virtual quote reserve. It is never consulted during trading.

## Accounting model

Effective reserves are:

`x = virtualQuoteReserve + realQuoteReserve`

`y = virtualTokenReserve + realTokenReserve`

For a buy, the quote fee is removed first, then `newY = ceil(x*y/(x+netQuote))`. For a sell, `newX = ceil(x*y/(y+tokenIn))`. Ceiling division deliberately rounds output against the trader so rounding cannot manufacture reserve value.

The on-chain reconciliation requirement is:

`curve ETH balance >= realQuoteReserve + accruedFees`

`curve token balance >= realTokenReserve`

The inequality is intentional: forced ETH and unsolicited ERC-20 transfers cannot be prevented and must not brick trading. Any surplus is excluded from pricing and requires an explicit governance policy before production.

## Frozen V1 parameters

The selected V1 economic parameters are now frozen in `ProtoFactory`:

- `TOTAL_SUPPLY`: 1,000,000,000 tokens
- `VIRTUAL_TOKEN_RATIO_BPS`: 250 (2.5% virtual-token reserve)
- `TRADING_FEE_BPS`: 100 (1%)
- `GRADUATION_THRESHOLD`: 5 native ETH of real quote reserve
- `TARGET_MARKET_CAP_USD8`: $2,000 at launch
- `MAX_PRICE_AGE`: 1 hour for the launch-only native/USD snapshot

The launch-time reference is read once to derive an immutable virtual quote
reserve. It is never consulted during trading. These values require an
independent security/economic review before mainnet deployment; changing them
requires a new factory deployment.

## Run

```bash
npm ci
forge install foundry-rs/forge-std@7fdf81f9ceb2f6ebbb8f9f1c6c5274d5bcc9a1f5 --no-git
forge test -vv
node simulation/curve-model.mjs
npm test
npm run simulate
npm run probe:robinhood
```

After building, `npm run mine:hook` mines the CREATE2 salt from the five deployment-address environment variables documented by the script. ProtoHook requires permission mask `0x2080` (`beforeInitialize | beforeSwap`) and its constructor rejects any incorrectly mined address.

The expanded sweep derives the virtual quote reserve from a launch-time quote/USD reference, compares curve shapes, fees, and graduation thresholds, and writes provisional evidence to `simulation/output/`.
