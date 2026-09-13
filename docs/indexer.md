# Proto indexer

The first indexer milestone is a small ethers v6 service in `indexer/`. It
scans Robinhood Chain (46630) events from `ProtoCore`, each bonding curve,
`ProtoRouter`, and `GraduationManager`, then persists a local JSON state file.
It exposes the endpoints consumed by the frontend:

```text
GET /health
GET /tokens?sort=volume_1h
GET /tokens?status=graduated&sort=launched_at
GET /tokens?sort=launched_at
GET /tokens/:address
GET /profiles/:address
POST /upload (raw image body; returns an IPFS URL)
```

## Run locally

```bash
cd indexer
npm install
cp .env.example .env
```

Set `RH_RPC_URL` in `.env`, then run:

```bash
npm start
```

For token image uploads, set `PINATA_JWT` and `PINATA_GATEWAY` in the indexer
environment. The frontend sends the raw image to `POST /upload`; the JWT is
never bundled into the browser. The route accepts PNG, JPEG, WEBP, and GIF
images up to `UPLOAD_MAX_BYTES` (5 MiB by default) and applies an in-memory
per-client rate limit. Set `INDEXER_ALLOWED_ORIGIN` to the deployed frontend
origin instead of `*` before exposing the service publicly.

The service polls every 15 seconds by default. `PROTO_INDEXER_START_BLOCK`
should be set to the earliest Proto deployment/launch block you want indexed;
the provided testnet example starts at the first smoke launch. State is stored
at `indexer/data/state.json`, which is development-only and ignored by Git.

Point the frontend at it with:

```env
VITE_PROTO_INDEXER_URL=http://localhost:8787
```

The indexer derives display market cap and USD volume using each token's
immutable launch-time native/USD snapshot. It never supplies execution prices
or ownership truth: balances, vesting, rewards, fees, and swaps remain
on-chain. Before production, replace the JSON store with Postgres, add RPC
provider failover, and backfill in bounded jobs.
