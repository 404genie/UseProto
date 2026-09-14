import fs from "node:fs";
import path from "node:path";
import { Pool } from "pg";

const EMPTY_STATE = { lastBlock: null, tokens: {}, trades: [] };

function openFileStore(filePath) {
  const resolved = path.resolve(filePath);
  fs.mkdirSync(path.dirname(resolved), { recursive: true });
  let state = { ...EMPTY_STATE };
  try {
    state = { ...EMPTY_STATE, ...JSON.parse(fs.readFileSync(resolved, "utf8")) };
  } catch (error) {
    if (error.code !== "ENOENT") throw error;
  }

  const save = async () => {
    const now = Math.floor(Date.now() / 1000);
    for (const record of Object.values(state.tokens)) {
      let volume1h = 0n;
      let volume5m = 0n;
      for (const trade of record.trades || []) {
        const age = now - Number(trade.timestamp || 0);
        const quote = BigInt(trade.quoteWei || "0");
        if (age >= 0 && age <= 3_600) volume1h += quote;
        if (age >= 0 && age <= 300) volume5m += quote;
      }
      record.volume1hWei = volume1h.toString();
      record.volume5mWei = volume5m.toString();
    }
    const temporary = `${resolved}.tmp`;
    fs.writeFileSync(temporary, JSON.stringify(state, null, 2));
    fs.renameSync(temporary, resolved);
  };

  return { state, save, path: resolved, kind: "file" };
}

function postgresSsl(databaseUrl) {
  return /localhost|127\\.0\\.1/.test(databaseUrl) ? false : { rejectUnauthorized: false };
}

async function openPostgresStore(databaseUrl) {
  const pool = new Pool({
    connectionString: databaseUrl,
    max: Number(process.env.PG_POOL_MAX || 5),
    ssl: postgresSsl(databaseUrl)
  });

  await pool.query(`
    CREATE TABLE IF NOT EXISTS proto_indexer_state (
      id SMALLINT PRIMARY KEY CHECK (id = 1),
      last_block BIGINT,
      updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
    );
    CREATE TABLE IF NOT EXISTS proto_indexer_tokens (
      token TEXT PRIMARY KEY,
      data JSONB NOT NULL,
      updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
    );
    CREATE TABLE IF NOT EXISTS proto_indexer_trades (
      token TEXT NOT NULL,
      trade_key TEXT NOT NULL,
      block_number BIGINT NOT NULL DEFAULT 0,
      log_index BIGINT NOT NULL DEFAULT 0,
      timestamp BIGINT NOT NULL,
      side TEXT NOT NULL,
      trader TEXT,
      quote_wei NUMERIC(78, 0) NOT NULL,
      token_amount NUMERIC(78, 0) NOT NULL,
      price_usd DOUBLE PRECISION NOT NULL DEFAULT 0,
      PRIMARY KEY (token, trade_key)
    );
    CREATE INDEX IF NOT EXISTS proto_indexer_trades_time_idx
      ON proto_indexer_trades (timestamp);
  `);

  const state = { ...EMPTY_STATE };
  const stateRow = await pool.query("SELECT last_block FROM proto_indexer_state WHERE id = 1");
  state.lastBlock = stateRow.rows[0]?.last_block == null ? null : Number(stateRow.rows[0].last_block);

  const tokenRows = await pool.query("SELECT token, data FROM proto_indexer_tokens");
  for (const row of tokenRows.rows) state.tokens[row.token] = row.data;

  const save = async () => {
    const client = await pool.connect();
    try {
      await client.query("BEGIN");

      const trades = [];
      for (const record of Object.values(state.tokens)) {
        for (const trade of record.trades || []) {
          trades.push({
            token: record.token.toLowerCase(),
            tradeKey: trade.tradeKey || `${trade.txHash || "unknown"}:${trade.logIndex || 0}`,
            blockNumber: Number(trade.blockNumber || 0),
            logIndex: Number(trade.logIndex || 0),
            timestamp: Number(trade.timestamp || 0),
            side: trade.side || "unknown",
            trader: trade.trader || null,
            quoteWei: String(trade.quoteWei || "0"),
            tokenAmount: String(trade.tokenAmount || "0"),
            priceUsd: Number(trade.priceUsd || 0)
          });
        }
      }

      for (let offset = 0; offset < trades.length; offset += 2_000) {
        const batch = trades.slice(offset, offset + 2_000);
        if (!batch.length) continue;
        const params = [];
        const values = batch.map((trade, index) => {
          const base = index * 10;
          params.push(
            trade.token,
            trade.tradeKey,
            trade.blockNumber,
            trade.logIndex,
            trade.timestamp,
            trade.side,
            trade.trader,
            trade.quoteWei,
            trade.tokenAmount,
            trade.priceUsd
          );
          return `($${base + 1},$${base + 2},$${base + 3},$${base + 4},$${base + 5},$${base + 6},$${base + 7},$${base + 8},$${base + 9},$${base + 10})`;
        }).join(",");
        await client.query(
          `INSERT INTO proto_indexer_trades
            (token, trade_key, block_number, log_index, timestamp, side, trader, quote_wei, token_amount, price_usd)
           VALUES ${values}
           ON CONFLICT (token, trade_key) DO UPDATE SET
             block_number = EXCLUDED.block_number,
             log_index = EXCLUDED.log_index,
             timestamp = EXCLUDED.timestamp,
             side = EXCLUDED.side,
             trader = EXCLUDED.trader,
             quote_wei = EXCLUDED.quote_wei,
             token_amount = EXCLUDED.token_amount,
             price_usd = EXCLUDED.price_usd`,
          params
        );
      }

      const now = Math.floor(Date.now() / 1000);
      const windows = await client.query(`
        SELECT token,
          COALESCE(SUM(quote_wei) FILTER (WHERE timestamp >= $1), 0)::text AS volume1h,
          COALESCE(SUM(quote_wei) FILTER (WHERE timestamp >= $2), 0)::text AS volume5m
        FROM proto_indexer_trades
        GROUP BY token
      `, [now - 3_600, now - 300]);
      for (const row of windows.rows) {
        const record = state.tokens[row.token];
        if (record) {
          record.volume1hWei = row.volume1h || "0";
          record.volume5mWei = row.volume5m || "0";
        }
      }

      const tokenEntries = Object.values(state.tokens);
      for (let offset = 0; offset < tokenEntries.length; offset += 2_000) {
        const batch = tokenEntries.slice(offset, offset + 2_000);
        if (!batch.length) continue;
        const params = [];
        const values = batch.map((record, index) => {
          const base = index * 2;
          params.push(record.token.toLowerCase(), JSON.stringify(record));
          return `($${base + 1},$${base + 2}::jsonb)`;
        }).join(",");
        await client.query(
          `INSERT INTO proto_indexer_tokens (token, data)
           VALUES ${values}
           ON CONFLICT (token) DO UPDATE SET data = EXCLUDED.data, updated_at = now()`,
          params
        );
      }

      await client.query(
        `INSERT INTO proto_indexer_state (id, last_block)
         VALUES (1, $1)
         ON CONFLICT (id) DO UPDATE SET last_block = EXCLUDED.last_block, updated_at = now()`,
        [state.lastBlock]
      );
      await client.query("COMMIT");
    } catch (error) {
      await client.query("ROLLBACK");
      throw error;
    } finally {
      client.release();
    }
  };

  return {
    state,
    save,
    path: "postgres",
    kind: "postgres",
    close: () => pool.end()
  };
}

export async function openStore(filePath) {
  const databaseUrl = String(process.env.DATABASE_URL || "").trim();
  if (!databaseUrl) return openFileStore(filePath);
  return openPostgresStore(databaseUrl);
}
