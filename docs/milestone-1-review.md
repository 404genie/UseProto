# Milestone 1 design review

## Decisions

- Native ETH is the V1 quote asset for this milestone.
- Fees are denominated in quote asset and segregated from real curve reserves.
- The curve holds real inventory; quotes cannot exceed that inventory.
- Sell output cannot exceed the real quote reserve, even though virtual quote liquidity exists.
- Rounding uses ceiling division for post-trade reserves, favoring solvency.
- Parameters are immutable per curve but remain economically provisional.

## Deliberately deferred

- Router-only execution and protected liquid/committed allocation.
- Fee withdrawal/distribution; `accruedFees` remains escrowed pending FeeController integration.
- Graduation state transitions and asset handoff.
- ERC-20 liquid-cap enforcement and VestingVault.
- Uniswap V4 and hook deployment.

## Integration boundary

Before milestone 3, direct `buy`/`sell` entry points must be restricted to ProtoRouter or refactored into router-authorized execution. That change should happen only after the independent curve and token/vesting proofs are complete.

ProtoCore must also prevent removing a system classification while that address holds more than the token's liquid cap. Otherwise an administrative registry change could make an already-existing balance violate the invariant.
