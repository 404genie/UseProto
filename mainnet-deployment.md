# Proto V1 mainnet deployment

Status: deployed on Robinhood Chain mainnet (`4663`), with source verification
handled through Sourcify.
Last reviewed: 2026-09-14

## Network

| Item | Value |
|---|---|
| Chain | Robinhood Chain mainnet |
| Chain ID | `4663` |
| RPC | `https://rpc.mainnet.chain.robinhood.com` |
| Explorer | [Robinhood Blockscout](https://robinhoodchain.blockscout.com/) |
| Source verifier | [Sourcify](https://sourcify.dev/) |

## Proto contracts

These are the deployed mainnet addresses. Addresses are public; credentials remain outside this repository.

| Contract | Address | Explorer |
|---|---|---|
| ProtoCore | `0x9227F8464808ff6EfF2B710c86A1af0Ed6BbCA0F` | [view](https://robinhoodchain.blockscout.com/address/0x9227F8464808ff6EfF2B710c86A1af0Ed6BbCA0F) |
| ProtoFactory | `0xcE6381A54Bdf51c71efAdD61eff2270c75F48454` | [view](https://robinhoodchain.blockscout.com/address/0xcE6381A54Bdf51c71efAdD61eff2270c75F48454) |
| ProtoRouter | `0x43933426c3D2809413564bD3F93Cf4B3ceA3f000` | [view](https://robinhoodchain.blockscout.com/address/0x43933426c3D2809413564bD3F93Cf4B3ceA3f000) |
| RewardEngine | `0x72c33b319D2bf9494b3E13815cf319d119322429` | [view](https://robinhoodchain.blockscout.com/address/0x72c33b319D2bf9494b3E13815cf319d119322429) |
| FeeController | `0x7168f7B129AFF719F63d89c1D9D4aBf4D750635A` | [view](https://robinhoodchain.blockscout.com/address/0x7168f7B129AFF719F63d89c1D9D4aBf4D750635A) |
| VestingVault | `0x1D56e23b1829ed5f2309467e7AF2515422FC8183` | [view](https://robinhoodchain.blockscout.com/address/0x1D56e23b1829ed5f2309467e7AF2515422FC8183) |
| GraduationManager | `0xf5fB52CB0828C06504f02252CBb803256b749534` | [view](https://robinhoodchain.blockscout.com/address/0xf5fB52CB0828C06504f02252CBb803256b749534) |
| V4GraduationAdapter | `0x9cD0d4061c72915f13B054Ab18cC7f346319c569` | [view](https://robinhoodchain.blockscout.com/address/0x9cD0d4061c72915f13B054Ab18cC7f346319c569) |
| LiquidityLocker | `0x9889d707Df37E2396A527AfC8bF170144f1530Fe` | [view](https://robinhoodchain.blockscout.com/address/0x9889d707Df37E2396A527AfC8bF170144f1530Fe) |
| ProtoHook | `0xB8fed88026B939Cf0161b95F6456e47a5CD02080` | [view](https://robinhoodchain.blockscout.com/address/0xB8fed88026B939Cf0161b95F6456e47a5CD02080) |
| HookCreate2Deployer | `0x8C28a10f3d618cac580A1bE436Fac6804922C673` | [view](https://robinhoodchain.blockscout.com/address/0x8C28a10f3d618cac580A1bE436Fac6804922C673) |
| LaunchPriceOracle | `0x10cDD084B81Ce0D7dd2dBE4515F3aCf198B3f47c` | [view](https://robinhoodchain.blockscout.com/address/0x10cDD084B81Ce0D7dd2dBE4515F3aCf198B3f47c) |

## Canonical V4 infrastructure

| Component | Address |
|---|---|
| PoolManager | `0x8366a39CC670B4001A1121B8F6A443A643e40951` |
| PositionManager | `0x58daec3116aae6D93017bAAea7749052E8a04fA7` |
| Permit2 | `0x000000000022D473030F116dDEE9F6B43aC78BA3` |
| Wrapped native | `0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73` |

The hook was mined with the required `0x2080` permission mask
(`beforeInitialize | beforeSwap`) and configured against the addresses above.

## Deployment and configuration evidence

The two-stage deployment is intentional: base contracts are deployed first,
then the deterministic hook is deployed and V4 bindings are finalized.

| Operation | Transaction | Block |
|---|---|---:|
| LaunchPriceOracle deployment | [`0x92348006135a8ae3ea3858fcd13ef405b00cf73c445fd841c5f9e69f25d896c5`](https://robinhoodchain.blockscout.com/tx/0x92348006135a8ae3ea3858fcd13ef405b00cf73c445fd841c5f9e69f25d896c5) | 62197957 |
| Hook CREATE2 deployment | [`0x2d3578db6e09de474c2678940b53d5fac4d6f71c55c687d7b49f95d7d851a922`](https://robinhoodchain.blockscout.com/tx/0x2d3578db6e09de474c2678940b53d5fac4d6f71c55c687d7b49f95d7d851a922) | 62214559 |
| Adapter-to-hook binding | [`0x2199a2ee904e81eeb7e4caa1d6568c01c9eccb31899a947c76a326c1e498f35d`](https://robinhoodchain.blockscout.com/tx/0x2199a2ee904e81eeb7e4caa1d6568c01c9eccb31899a947c76a326c1e498f35d) | 62214590 |
| ProtoCore V4 binding | [`0x728e253a7bae1310a3d01c30898eb28ca2078f793f1485feb82ec20e4aef3c8f`](https://robinhoodchain.blockscout.com/tx/0x728e253a7bae1310a3d01c30898eb28ca2078f793f1485feb82ec20e4aef3c8f) | 62214605 |

The base deployment also recorded the one-time module bindings and protocol
registry writes. The deployment broadcast artifacts are the source of truth
for constructor arguments and transaction ordering.

## Frozen V1 parameters

| Parameter | Value |
|---|---:|
| Total supply | 1,000,000,000 tokens |
| Virtual token ratio | 250 BPS (2.5%) |
| Trading fee | 100 BPS (1%) |
| Graduation threshold | 5 native ETH |
| Target launch market cap | $2,000 |
| Launch-price freshness | 1 hour |
| Per-address liquid cap | 200 BPS (2%) |
| Vesting duration | 30 days |
| Fee split | 15% protocol / 35% creator / 50% committed-token holders |

The launch oracle is read only during token creation. Trading and graduation do
not query it.

## Verification status

Verification is performed from the exact deployment source and Foundry
settings (`solc 0.8.26`, Cancun, via-IR, optimizer runs `10,000`).

| Contract | Sourcify status | Job |
|---|---|---|
| GraduationManager | `exact_match` | `5a83f2a6-8ee7-4d1e-9900-92ec31347b39` |
| V4GraduationAdapter | `exact_match` | `cf47f007-9c1b-4328-bcdf-3fb2c4b04b00` |
| LiquidityLocker | `exact_match` | `e7f99219-7c61-4645-a6ec-67e7f815b5fb` |
| ProtoHook | Submitted; confirm with `forge verify-check` | `d6f81fc8-2d67-4fb8-87fc-99c3168f0df2` |

Check a pending job with:

```bash
forge verify-check <JOB_ID> --chain-id 4663 --verifier sourcify
```

## Operational verification

Run these checks from a clean checkout with production variables supplied by
the operator:

```bash
test "$(cast chain-id --rpc-url "$RH_RPC_URL")" = "4663"
forge script script/VerifyDeployment.s.sol:VerifyDeployment \
  --rpc-url "$RH_RPC_URL"
```

The indexer must report `chainId: 4663`, `storage: "postgres"`, and a
non-null, advancing `indexedThrough`. Its production start command is
`node src/index.mjs` from the `indexer` service root; the production `.env` is
provided by Railway variables and is not stored in Git.

## Change and recovery policy

The deployed contracts are immutable and the LP position is intentionally held
without a withdrawal path. A bytecode mismatch, incorrect constructor argument,
or faulty one-time binding cannot be patched in place. It requires a new
deployment, new hook salt, new environment addresses, fresh source
verification, and a complete release-candidate review.
