# ADR-001: Snapshot the native/USD reference at launch

Status: accepted

Proto derives each curve's `virtualQuoteReserve` at launch from the protocol target market capitalization, fixed supply, approved virtual-token ratio, and the launch-time native/USD reference. The resulting reserve is stored immutably in the curve.

After construction, the oracle/reference has no role in `quoteBuy`, `quoteSell`, `buy`, or `sell`. Trading uses only virtual reserves fixed at launch and the curve's on-chain real reserves.

The launch reference, timestamp, and derived reserve should later be recorded in ProtoCore for transparent analytics. Stale-price limits and accepted price-source rules belong to Factory/Core integration, not BondingCurve execution.

