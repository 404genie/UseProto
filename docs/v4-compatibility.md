# Uniswap V4 compatibility gate

Proto's graduation boundary targets canonical Uniswap V4. The pinned upstream
V4 core uses EIP-1153 `TSTORE`/`TLOAD` for unlock state, currency deltas,
reserve synchronization, and settlement. Consequently, compiling Proto's
adapter against V4 interfaces does not prove that PoolManager itself can run on
the target chain.

Before any Robinhood Chain deployment, the release process must prove on the
exact target RPC that:

1. `PUSH0` (EIP-3855) is accepted.
2. `TSTORE` and `TLOAD` (EIP-1153) are accepted.
3. Canonical PoolManager and PositionManager deployment bytecode executes.
4. A native/token pool can initialize and complete an unlock/settlement cycle.
5. The minted position is owned by LiquidityLocker and no withdrawal path
   exists.

On 2026-09-10, a read-only probe against Robinhood Chain testnet chain ID
`46630` successfully estimated contract-creation execution containing `PUSH0`,
`TSTORE`, and `TLOAD` at block `117054104`. The repository therefore targets `cancun`, and the
testnet opcode gate is cleared. The probe must be repeated against the exact
RPC immediately before deployment and independently for mainnet; silently
replacing canonical V4 with a modified local AMM is not an acceptable fallback.

Run `npm run probe:robinhood` to repeat the check. Set `RH_RPC_URL` when using
an authenticated or alternate endpoint.

Pinned npm releases used by the adapter (with integrity hashes recorded in
`package-lock.json`):

- `@uniswap/v4-core`: `1.0.2`
- `@uniswap/v4-periphery`: `1.0.3`
