# Proto V1 parameter freeze

Status: selected for V1 testnet and release-candidate review.

| Parameter | Frozen value | Purpose |
|---|---:|---|
| Total supply | 1,000,000,000 tokens | Fixed supply for every launch |
| Virtual token ratio | 250 BPS (2.5%) | Curve starting shape |
| Trading fee | 100 BPS (1%) | Quote-asset fee before curve execution |
| Graduation threshold | 5 native ETH | Real quote reserve trigger |
| Target launch market cap | $2,000 | Virtual starting valuation target |
| Launch price freshness | 1 hour | Maximum age of launch-only native/USD reference |
| Liquid cap | 200 BPS (2%) | Maximum liquid balance per non-system address |
| Vesting duration | 30 days | Linear vesting for excess allocations |

The native/USD reference is read only during `ProtoFactory.createToken`. The
derived virtual quote reserve is stored in the curve; no oracle is consulted
by trading or graduation.

Simulation evidence shows the 5-ETH threshold leaves approximately 9.82% of
curve inventory for the permanent V4 position. Larger early buys have high
price impact, which is an acknowledged V1 trade-off and must be covered in
frontend slippage messaging and the independent economic review.

Changing any factory-level value requires deploying a new factory and running
the complete release-candidate testnet lifecycle again.
