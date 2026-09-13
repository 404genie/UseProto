# Proto economic sweep — frozen V1 parameters

This report evaluates 432 parameter combinations and runs 100,000 deterministic mixed trades. The selected V1 reference below remains subject to independent security and economic review before mainnet deployment.

## Selected V1 reference

- Quote/USD reference: $3,000
- Initial target market cap: $2,000
- Virtual token reserve: 2.5% of real inventory
- Derived virtual quote reserve: 0.683333 native
- Trading fee: 1%

## Initial buy impact

| Buy size | Execution impact | Post-trade spot move |
|---:|---:|---:|
| 0.01 native | 1.44% | 2.91% |
| 0.1 native | 14.48% | 31.07% |
| 0.5 native | 72.43% | 197.35% |
| 1 native | 144.87% | 499.65% |
| 5 native | 724.39% | 6696.19% |

## Graduation candidates

| Real reserve | Market cap at graduation | Inventory sold | Inventory left for V4 | Fees accrued |
|---:|---:|---:|---:|---:|
| 5 native | $138,347 | 90.18% | 9.82% | 0.0505 native |
| 10 native | $488,853 | 95.94% | 4.06% | 0.1010 native |
| 20 native | $1,832,339 | 99.11% | 0.89% | 0.2020 native |
| 25 native | $2,825,319 | 99.77% | 0.23% | 0.2525 native |

## Engineering interpretation

The 5-native threshold was selected because it retains about 10% of supply for the permanent V4 position. Thresholds of 10–25 native consume roughly 96–100% of curve inventory, leaving an increasingly weak token side for graduation. The selected set accepts substantial price impact on larger early trades in exchange for retaining a meaningful token side at graduation.

## Stress result

57,975 buys and 42,025 sells completed without negative reserves. Final accounted reserves: 0.211058 native and 758,121,469.94 tokens.

## Launch reference policy

A static native virtual quote reserve cannot keep the starting USD market cap near $2,000 when the native asset/USD price changes. Proto therefore derives and snapshots the virtual quote reserve at launch from a display-only quote/USD reference. The oracle/reference never participates in trade execution after initialization.
