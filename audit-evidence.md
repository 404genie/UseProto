# Proto V1 audit evidence

This file collects reproducible evidence for the deployed Robinhood Chain
mainnet release. It distinguishes source verification, wiring verification,
and functional graduation evidence; these are separate claims.

Last reviewed: 2026-09-14

## Scope and current conclusion

- Mainnet chain: Robinhood Chain (`4663`).
- The four core graduation contracts have been submitted to Sourcify; the
  manager, adapter, and locker returned `exact_match`.
- The hook job was submitted and must be checked for `exact_match`.
- Mainnet wiring was checked with `VerifyDeployment.s.sol`.
- No state-changing mainnet graduation rehearsal was performed because the
  immutable graduation threshold is 5 native ETH.
- Therefore, source and wiring evidence are available, while a mainnet
  threshold-crossing transaction is explicitly not claimed.

## Graduation-path source verification

| Component | Address | Evidence |
|---|---|---|
| GraduationManager | `0xf5fB52CB0828C06504f02252CBb803256b749534` | Sourcify `exact_match`, job `5a83f2a6-8ee7-4d1e-9900-92ec31347b39` |
| V4GraduationAdapter | `0x9cD0d4061c72915f13B054Ab18cC7f346319c569` | Sourcify `exact_match`, job `cf47f007-9c1b-4328-bcdf-3fb2c4b04b00` |
| LiquidityLocker | `0x9889d707Df37E2396A527AfC8bF170144f1530Fe` | Sourcify `exact_match`, job `e7f99219-7c61-4645-a6ec-67e7f815b5fb` |
| ProtoHook | `0xB8fed88026B939Cf0161b95F6456e47a5CD02080` | Sourcify job `d6f81fc8-2d67-4fb8-87fc-99c3168f0df2`; status must be checked |

The deployed hook—not only `HookCreate2Deployer`—must be verified because its
constructor immutables define the PoolManager, core, adapter, and router
authorization boundary.

## Functional test evidence

The release candidate test suite covered:

- protected bonding-curve buy and sell paths;
- liquid-cap and vesting allocation behavior;
- fee conservation and reward accounting;
- deadline and slippage protection;
- callback and reentrancy boundaries;
- lifecycle authorization and monotonic graduation state;
- canonical V4 pool initialization and position minting;
- permanent LP-NFT custody in `LiquidityLocker`;
- protected post-graduation V4 buys and sells.

The reported full suite result was 73 passing tests. The canonical V4 tests
prove the adapter/hook/locker interaction in a real V4 integration test
environment; they are not evidence that 5 ETH was spent on mainnet.

## On-chain deployment evidence

The mainnet deployment used a two-stage process:

1. `DeployBase.s.sol` deployed and permanently bound the core, factory, router,
   fee, vesting, reward, graduation, adapter, and locker modules.
2. `ConfigureV4.s.sol` deployed the mined hook, bound it to the adapter, and
   called `ProtoCore.bindV4` with the canonical V4 addresses.

Relevant configuration transactions:

| Operation | Transaction | Block |
|---|---|---:|
| Hook deployment | `0x2d3578db6e09de474c2678940b53d5fac4d6f71c55c687d7b49f95d7d851a922` | 62214559 |
| Adapter hook binding | `0x2199a2ee904e81eeb7e4caa1d6568c01c9eccb31899a947c76a326c1e498f35d` | 62214590 |
| Core V4 binding | `0x728e253a7bae1310a3d01c30898eb28ca2078f793f1485feb82ec20e4aef3c8f` | 62214605 |

Reproduce the wiring check:

```bash
forge script script/VerifyDeployment.s.sol:VerifyDeployment \
  --rpc-url "$RH_RPC_URL"
```

The script is read-only. A successful `Script ran successfully` means the
cross-contract references and V4 binding invariants did not revert.

## Graduation behavior documented for review

Once `realQuoteReserve >= graduationThreshold`, graduation is atomic:

1. `ProtoCore` moves the token to `GRADUATING`.
2. The curve stops trading and releases accounted reserves.
3. `V4GraduationAdapter` arms the exact pool ID in `ProtoHook`.
4. The canonical PositionManager initializes the native/token pool and mints a
   full-range position.
5. The position NFT is sent to `LiquidityLocker` and registered.
6. `ProtoCore` records the pool and irreversibly marks the token `GRADUATED`.

Any failure reverts the transaction. The locker has no transfer, withdrawal,
removal, or emergency-drain path by design. Consequently, the V4 LP position
and its trading fees are permanently non-claimable; this is an intentional
liquidity-lock property, separate from Proto's pull-based protocol/creator/
holder fee claims.

## Mainnet smoke-test boundary

`SmokeTestMainnet.s.sol` successfully exercised disposable mainnet token
creation, curve buy, and curve sell. It did not cross the 5 ETH graduation
threshold. This boundary must remain visible in any auditor response.

If the auditor requires a state-changing mainnet graduation transaction, obtain
their acceptance criteria and budget approval first. Do not represent the
testnet or fork evidence as a mainnet graduation transaction.

## Infrastructure evidence

The production indexer is expected to be healthy when:

```bash
curl -sS https://useproto-production.up.railway.app/health
```

The response must show:

```json
{
  "ok": true,
  "chainId": 4663,
  "storage": "postgres"
}
```

`indexedThrough` must be non-null and advance over time. The Vercel frontend
must use the mainnet chain ID and the Railway indexer URL; secrets remain in
Vercel/Railway variable stores.

## Auditor sign-off checklist

- [ ] Mainnet chain and deployed address inventory recorded.
- [ ] GraduationManager source exact-match verified.
- [ ] V4GraduationAdapter source exact-match verified.
- [ ] LiquidityLocker source exact-match verified.
- [ ] ProtoHook source exact-match confirmed.
- [ ] Mainnet V4 wiring checked with `VerifyDeployment.s.sol`.
- [ ] Canonical V4 integration tests passed.
- [ ] Mainnet curve smoke test passed.
- [ ] Auditor accepts non-mainnet graduation evidence, or a funded mainnet
      graduation rehearsal is completed.
