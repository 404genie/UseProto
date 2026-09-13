# Graduation safety layer

Graduation is permissionless after the immutable real-quote threshold is reached. ProtoCore moves `ACTIVE_CURVE` to `GRADUATING`; BondingCurve disables trading and releases its accounted token and native reserves; the adapter initializes the V4 pool and mints its position directly to LiquidityLocker; then ProtoCore records the pool and irreversibly marks `GRADUATED`.

All operations occur in one transaction. If pool initialization or position minting fails, the lifecycle change, curve shutdown, and asset transfers all revert.

LiquidityLocker accepts NFTs only from the configured PositionManager and deliberately exposes no transfer, withdrawal, removal, or emergency-drain function.

V4GraduationAdapter uses the canonical PositionManager interface. Before initialization it arms the exact PoolId in ProtoHook; that one-transaction authorization is consumed by the hook when PoolManager initializes the pool. ProtoHook then permits swaps only for the pool recorded by ProtoCore, after graduation, through the authorized Proto V4 router.

HookCreate2Deployer and `script/mine-hook-salt.mjs` enforce the hook's `0x2080` permission mask (`beforeInitialize | beforeSwap`).
