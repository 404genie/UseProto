# Proto SDK

`/sdk/index.mjs` is the first client integration layer for Proto V1. It uses
ethers v6 and only targets Robinhood Chain (chain ID `46630`). The SDK keeps
deployment addresses in a manifest and centralizes signer/account resolution
so a frontend does not duplicate protected-trade rules.

```js
import { ProtoClient } from "./sdk/index.mjs";
import deployment from "./deployments/robinhood-testnet.json" with { type: "json" };

const proto = ProtoClient.fromRpc({
  rpcUrl: process.env.RH_RPC_URL,
  privateKey: process.env.PRIVATE_KEY,
  deployment
});

await proto.assertNetwork();
const quote = await proto.quoteBuy(curve, 1_000_000_000_000_000n);
const deadline = BigInt(Math.floor(Date.now() / 1000) + 900);
const tx = await proto.buy({
  curve,
  value: 1_000_000_000_000_000n,
  minTotalOut: quote.tokenOut * 99n / 100n,
  deadline
});
await tx.wait();
```

All write methods require a signer and all swap methods require an explicit
deadline. `buy`/`buyV4` return the router transaction response; call
`wait()` before treating the state change as final. For sells, call
`approveRouter(token, amount)` first and wait for that approval transaction.

The SDK exposes read models for token metadata, curve reserves and progress,
vesting, rewards, creator fees, and the graduation pool/position. It does not
use a USD oracle during trading; the immutable launch snapshot remains the
source of the launch-price display.
