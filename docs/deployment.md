# Robinhood Chain deployment

Proto uses a two-stage deployment because the V4 hook address must encode its
permissions. All bind operations are configurator-only and permanent after the
first successful call.

## Prerequisites

- Robinhood Chain RPC and a funded deployment key.
- Canonical V4 `PoolManager` and `PositionManager` addresses for chain ID 46630.
- Permit2 address used by that PositionManager.
- A native/USD reference contract implementing `ILaunchPriceOracle`. It is read
  only when a token launches; no oracle is used during trading.
- A protocol treasury address that can safely receive pull-based claims.

Never commit a private key or `.env` file.

## 0. Bootstrap isolated testnet V4 infrastructure

Robinhood testnet does not currently publish canonical V4 deployment addresses.
For protocol testing, deploy Permit2 and then the isolated V4 stack. These
contracts are testnet infrastructure and are not claimed to be official Uniswap
deployments.

Deploy Permit2 from the pinned package and record the returned contract address:

```bash
forge create node_modules/@uniswap/v4-periphery/lib/permit2/src/Permit2.sol:Permit2 \
  --rpc-url "$RH_RPC_URL" --private-key "$PRIVATE_KEY" --broadcast
```

Set `PERMIT2` to that address and set `LAUNCH_PRICE_USD8` to the native/USD
reference with eight decimals (for example, `300000000000` represents $3,000).
Simulate, then broadcast:

```bash
forge script script/DeployTestnetInfrastructure.s.sol:DeployTestnetInfrastructure --rpc-url "$RH_RPC_URL"
forge script script/DeployTestnetInfrastructure.s.sol:DeployTestnetInfrastructure --rpc-url "$RH_RPC_URL" --broadcast
```

Record `V4_POOL_MANAGER`, `V4_POSITION_MANAGER`, `WRAPPED_NATIVE`,
`V4_POSITION_DESCRIPTOR`, and `LAUNCH_PRICE_ORACLE` in `.env`. The manual
reference must be refreshed with `setPrice` before launches if its timestamp is
older than ProtoFactory's one-hour launch window. It is never read during trades.

## 1. Deploy and bind the base protocol

Set `PRIVATE_KEY`, `PROTOCOL_TREASURY`, `LAUNCH_PRICE_ORACLE`,
`V4_POSITION_MANAGER`, and `PERMIT2`, then simulate before broadcasting:

```bash
forge script script/DeployBase.s.sol:DeployBase --rpc-url "$RH_RPC_URL"
forge script script/DeployBase.s.sol:DeployBase --rpc-url "$RH_RPC_URL" --broadcast
```

Record every returned address. The base script binds rewards, vesting, fees,
the graduation manager, and locker, but intentionally leaves V4 disabled.

## 2. Mine the ProtoHook salt

Build first, then set these values from stage one:

```text
HOOK_CREATE2_DEPLOYER
V4_POOL_MANAGER
PROTO_CORE
GRADUATION_ADAPTER
PROTO_ROUTER
```

Run `npm run mine:hook`. Record both `salt` and the predicted hook address.

## 3. Deploy the hook and finalize V4

Set `PRIVATE_KEY`, `PROTO_CORE`, `PROTO_ROUTER`, `GRADUATION_MANAGER`,
`GRADUATION_ADAPTER`, `LIQUIDITY_LOCKER`, `HOOK_CREATE2_DEPLOYER`,
`V4_POOL_MANAGER`, `V4_POSITION_MANAGER`, and `HOOK_SALT`.

```bash
forge script script/ConfigureV4.s.sol:ConfigureV4 --rpc-url "$RH_RPC_URL"
forge script script/ConfigureV4.s.sol:ConfigureV4 --rpc-url "$RH_RPC_URL" --broadcast
```

The hook constructor rejects a salt whose resulting address does not have the
required `0x2080` permission mask.

## 4. Verify read-only wiring

Set the component addresses required by `VerifyDeployment.s.sol`, then run:

```bash
forge script script/VerifyDeployment.s.sol:VerifyDeployment --rpc-url "$RH_RPC_URL"
```

The verifier checks every critical cross-contract reference and reverts on a
mismatch. After that, launch a disposable test token and test buy, sell,
vesting, fee claims, graduation, the locked position, and V4 buy/sell before
the deployment is accepted.

For the first on-chain smoke test, broadcast the testnet-only runner:

```bash
forge script script/SmokeTest.s.sol:SmokeTest --rpc-url "$RH_RPC_URL" --broadcast
```

It launches `PSMOKE`, buys with `0.0001` native token, sells half of the
liquid balance, and reports the token/curve addresses and quote returned.
