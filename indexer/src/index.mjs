import http from "node:http";
import process from "node:process";
import { ethers, JsonRpcProvider } from "ethers";
import { openStore } from "./store.mjs";

const RPC_URL = process.env.INDEXER_RPC_URL || process.env.RH_RPC_URL || process.env.VITE_RH_RPC_URL;
const CORE_ADDRESS = process.env.PROTO_CORE;
const ROUTER_ADDRESS = process.env.PROTO_ROUTER;
const GRADUATION_MANAGER = process.env.GRADUATION_MANAGER || "";
const PORT = Number(process.env.INDEXER_PORT || 8787);
const POLL_MS = Number(process.env.INDEXER_POLL_MS || 15_000);
const STATE_PATH = process.env.INDEXER_STATE_PATH || "./data/state.json";
const PINATA_JWT = process.env.PINATA_JWT || "";
const PINATA_GATEWAY = (process.env.PINATA_GATEWAY || "https://gateway.pinata.cloud/ipfs").replace(/\/$/, "");
const ALLOWED_ORIGIN = process.env.INDEXER_ALLOWED_ORIGIN || "*";
const UPLOAD_MAX_BYTES = Number(process.env.UPLOAD_MAX_BYTES || 5 * 1024 * 1024);
const UPLOAD_WINDOW_MS = 60_000;
const UPLOAD_MAX_PER_WINDOW = Number(process.env.UPLOAD_MAX_PER_WINDOW || 10);
const CHUNK_SIZE = Number(process.env.INDEXER_CHUNK_SIZE || 2_000);
const LOG_CONCURRENCY = Number(process.env.INDEXER_LOG_CONCURRENCY || 2);
const CURVE_CONCURRENCY = Number(process.env.INDEXER_CURVE_CONCURRENCY || 2);
const RPC_RETRIES = Number(process.env.INDEXER_RPC_RETRIES || 4);
const RPC_CONCURRENCY = Math.max(1, Number(process.env.INDEXER_RPC_CONCURRENCY || 4));
const MAX_STORED_TRADES = Number(process.env.INDEXER_MAX_STORED_TRADES || 1_000);
const ZERO = "0x0000000000000000000000000000000000000000";

if (!RPC_URL || !CORE_ADDRESS || !ROUTER_ADDRESS) {
  throw new Error("RH_RPC_URL, PROTO_CORE, and PROTO_ROUTER are required");
}

const chainId = Number(process.env.CHAIN_ID ?? "4663");
const provider = new JsonRpcProvider(RPC_URL, chainId);
const store = await openStore(STATE_PATH);
const state = store.state;
const core = ethers.getAddress(CORE_ADDRESS);
const router = ethers.getAddress(ROUTER_ADDRESS);
const graduationManager = GRADUATION_MANAGER ? ethers.getAddress(GRADUATION_MANAGER) : null;

const coreInterface = new ethers.Interface([
  "event TokenRegistered(address indexed token,address indexed curve,address indexed creator,uint256 launchPriceUsd8,uint256 virtualQuoteReserve)",
  "event Graduated(address indexed token,address indexed curve,bytes32 indexed poolId,uint256 positionId,uint256 tokens,uint256 quote)"
]);
const curveInterface = new ethers.Interface([
  "event Bought(address indexed buyer,address indexed recipient,uint256 quoteIn,uint256 tokenOut,uint256 fee)",
  "event Sold(address indexed seller,address indexed recipient,uint256 tokenIn,uint256 quoteOut,uint256 fee)"
]);
const routerInterface = new ethers.Interface([
  "event ProtectedBuy(address indexed curve,address indexed buyer,address indexed recipient,uint256 total,uint256 liquid,uint256 committed)",
  "event ProtectedSell(address indexed curve,address indexed seller,address indexed recipient,uint256 tokenIn,uint256 quoteOut)",
  "event ProtectedV4Buy(address indexed token,address indexed buyer,address indexed recipient,uint256 quoteIn,uint256 total,uint256 liquid,uint256 committed)",
  "event ProtectedV4Sell(address indexed token,address indexed seller,address indexed recipient,uint256 tokenIn,uint256 quoteOut)"
]);
const tokenInterface = new ethers.Interface([
  "function name() view returns (string)",
  "function symbol() view returns (string)",
  "function decimals() view returns (uint8)",
  "function totalSupply() view returns (uint256)",
  "function balanceOf(address) view returns (uint256)"
]);
const coreReadInterface = new ethers.Interface([
  "function tokenInfo(address) view returns (address creator,address curve,uint256 launchPriceUsd8,uint256 virtualQuoteReserve,uint64 launchedAt,uint8 lifecycle,string metadataURI)"
]);
const curveReadInterface = new ethers.Interface([
  "function spotPriceWad() view returns (uint256)",
  "function realQuoteReserve() view returns (uint256)",
  "function state() view returns (uint8)"
]);
const vaultInterface = new ethers.Interface([
  "function committedBalance(address,address) view returns (uint256)"
]);

const topic = (iface, eventName) => iface.getEvent(eventName).topicHash;
const cache = new Map();
const uploadWindows = new Map();
let lastSync = null;

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

let rpcActive = 0;
const rpcQueue = [];

async function acquireRpcSlot() {
  if (rpcActive < RPC_CONCURRENCY) {
    rpcActive += 1;
    return;
  }
  await new Promise((resolve) => rpcQueue.push(resolve));
  rpcActive += 1;
}

function releaseRpcSlot() {
  rpcActive -= 1;
  rpcQueue.shift()?.();
}

async function withRetry(operation, label) {
  let lastError;
  for (let attempt = 0; attempt <= RPC_RETRIES; attempt += 1) {
    await acquireRpcSlot();
    try {
      return await operation();
    } catch (error) {
      lastError = error;
      const message = String(error?.shortMessage || error?.message || error);
      const retryable = /429|rate|timeout|temporar|network|502|503|504|ECONNRESET|ETIMEDOUT/i.test(message);
      if (!retryable || attempt === RPC_RETRIES) throw error;
      const delay = Math.min(8_000, 250 * 2 ** attempt);
      console.warn(`rpc retry ${label} (${attempt + 1}/${RPC_RETRIES}) in ${delay}ms: ${message}`);
      await sleep(delay);
    } finally {
      releaseRpcSlot();
    }
  }
  throw lastError;
}

async function mapLimit(items, limit, worker) {
  const results = new Array(items.length);
  let next = 0;
  async function run() {
    while (true) {
      const index = next;
      next += 1;
      if (index >= items.length) return;
      results[index] = await worker(items[index], index);
    }
  }
  const workers = Math.min(Math.max(1, limit), items.length);
  await Promise.all(Array.from({ length: workers }, () => run()));
  return results;
}

function call(address, iface, functionName, args = []) {
  const data = iface.encodeFunctionData(functionName, args);
  return withRetry(
    () => provider.call({ to: address, data }).then((result) => iface.decodeFunctionResult(functionName, result)),
    `call ${functionName}`
  );
}

function parseMetadata(metadataURI) {
  if (!metadataURI) return {};
  try {
    const value = JSON.parse(metadataURI);
    return typeof value === "object" && value ? value : {};
  } catch {
    return { metadataURI };
  }
}

function tokenRecord(token) {
  const key = token.toLowerCase();
  state.tokens[key] ||= { token, trades: [], volumeAllTimeWei: "0", volume1hWei: "0", volume5mWei: "0", lifecycle: 1, initialPriceUsd: null };
  const record = state.tokens[key];
  if (record.initialPriceUsd == null) {
    const firstTrade = (record.trades || []).find((trade) => Number(trade.priceUsd) > 0);
    if (firstTrade) record.initialPriceUsd = Number(firstTrade.priceUsd);
  }
  return record;
}

function ageLabel(timestamp) {
  const seconds = Math.max(0, Math.floor(Date.now() / 1000) - Number(timestamp || 0));
  if (seconds < 60) return "just now";
  if (seconds < 3600) return `${Math.floor(seconds / 60)}m`;
  if (seconds < 86_400) return `${Math.floor(seconds / 3600)}h`;
  return `${Math.floor(seconds / 86_400)}d`;
}

function usdFromWei(wei, launchPriceUsd8) {
  return Number(ethers.formatEther(wei)) * Number(launchPriceUsd8 || 0n) / 1e8;
}

async function blockTimestamp(blockNumber) {
  if (!cache.has(blockNumber)) {
    cache.set(blockNumber, withRetry(
      () => provider.getBlock(blockNumber).then((block) => Number(block?.timestamp || 0)),
      `getBlock ${blockNumber}`
    ));
  }
  return cache.get(blockNumber);
}

async function scanLogs(address, iface, eventName, fromBlock, toBlock) {
  const chunks = [];
  for (let start = fromBlock; start <= toBlock; start += CHUNK_SIZE) {
    chunks.push({ start, end: Math.min(toBlock, start + CHUNK_SIZE - 1) });
  }
  const batches = await mapLimit(chunks, LOG_CONCURRENCY, ({ start, end }) => withRetry(
    () => provider.getLogs({ address, topics: [topic(iface, eventName)], fromBlock: start, toBlock: end }),
    `getLogs ${eventName} ${start}-${end}`
  ));
  return batches.flat();
}

async function hydrateToken(record) {
  const errors = [];
  record.hydrationError = undefined;
  try {
    const info = await call(core, coreReadInterface, "tokenInfo", [record.token]);
    // tokenInfo returns seven top-level values, not a tuple wrapped at index 0.
    const decoded = info;
    record.creator = ethers.getAddress(decoded.creator);
    record.curve = ethers.getAddress(decoded.curve);
    record.launchPriceUsd8 = decoded.launchPriceUsd8.toString();
    record.launchedAt = Number(decoded.launchedAt);
    record.lifecycle = Number(decoded.lifecycle);
    record.metadataURI = decoded.metadataURI;
    Object.assign(record, parseMetadata(decoded.metadataURI));
  } catch (error) {
    // Keep the event-derived token/curve/creator fields. A temporary RPC
    // failure reading Core must not turn a discoverable token into a blank
    // record or prevent the remaining metadata reads from running.
    errors.push(`core: ${error.shortMessage || error.message}`);
  }

  const reads = await Promise.allSettled([
    call(record.token, tokenInterface, "name").then((value) => ["name", value[0]]),
    call(record.token, tokenInterface, "symbol").then((value) => ["symbol", value[0]]),
    call(record.token, tokenInterface, "totalSupply").then((value) => ["totalSupply", value[0].toString()])
  ]);
  for (const result of reads) {
    if (result.status === "fulfilled") record[result.value[0]] = result.value[1];
    else errors.push(`token: ${result.reason?.shortMessage || result.reason?.message || result.reason}`);
  }

  if (record.curve) {
    try {
      const [spotPriceWad, realQuoteReserve, curveState] = await Promise.all([
        call(record.curve, curveReadInterface, "spotPriceWad").then((value) => value[0]),
        call(record.curve, curveReadInterface, "realQuoteReserve").then((value) => value[0]),
        call(record.curve, curveReadInterface, "state").then((value) => value[0])
      ]);
      record.spotPriceWad = spotPriceWad.toString();
      record.realQuoteReserveWei = realQuoteReserve.toString();
      if (record.lifecycle < 3) record.curveState = Number(curveState);
      // spotPriceWad has 1e18 fixed-point scaling. Convert the token-side
      // product back to quote-asset wei before converting to USD.
      const marketCapQuoteWei = spotPriceWad * BigInt(record.totalSupply || "0") / 10n ** 18n;
      record.marketCap = Number(ethers.formatEther(marketCapQuoteWei)) * Number(record.launchPriceUsd8 || 0n) / 1e8;
    } catch (error) {
      errors.push(`curve: ${error.shortMessage || error.message}`);
    }
  }
  if (errors.length) record.hydrationError = errors.join(" | ");
  record.age = ageLabel(record.launchedAt);
  record.volumeAllTime = usdFromWei(BigInt(record.volumeAllTimeWei || "0"), BigInt(record.launchPriceUsd8 || "0"));
  record.volume1h = usdFromWei(BigInt(record.volume1hWei || "0"), BigInt(record.launchPriceUsd8 || "0"));
  record.volume5m = usdFromWei(BigInt(record.volume5mWei || "0"), BigInt(record.launchPriceUsd8 || "0"));
  record.chart = record.trades.slice(-30).map((trade) => Number(trade.priceUsd || 0));
  if (process.env.INDEXER_DEBUG === "true") {
    console.log(`hydrate ${record.token}: ${record.name || "<no name>"} ${record.symbol || "<no symbol>"}${record.hydrationError ? ` (${record.hydrationError})` : ""}`);
  }
  return record;
}

async function addTrade(record, trade) {
  const timestamp = await blockTimestamp(trade.blockNumber);
  const quoteWei = BigInt(trade.quoteWei);
  const tokenAmount = BigInt(trade.tokenAmount || 0n);
  const launchPrice = BigInt(record.launchPriceUsd8 || "0");
  const priceUsd = tokenAmount > 0n
    ? Number(ethers.formatEther(quoteWei)) / Number(ethers.formatUnits(tokenAmount, 18)) * Number(launchPrice) / 1e8
    : 0;
  if (record.initialPriceUsd == null && priceUsd > 0) record.initialPriceUsd = priceUsd;
  const tradeKey = `${trade.txHash}:${trade.logIndex ?? 0}`;
  if (record.trades.some((item) => item.tradeKey === tradeKey)) return;
  record.trades.push({
    tradeKey,
    timestamp,
    blockNumber: Number(trade.blockNumber),
    logIndex: Number(trade.logIndex ?? 0),
    quoteWei: quoteWei.toString(),
    tokenAmount: tokenAmount.toString(),
    priceUsd,
    side: trade.side,
    trader: trade.trader || "",
    txHash: trade.txHash
  });
  if (record.trades.length > MAX_STORED_TRADES) {
    record.trades.splice(0, record.trades.length - MAX_STORED_TRADES);
  }
  record.volumeAllTimeWei = (BigInt(record.volumeAllTimeWei || "0") + quoteWei).toString();
  const now = Math.floor(Date.now() / 1000);
  record.volume1hWei = (BigInt(record.volume1hWei || "0") + (now - timestamp <= 3600 ? quoteWei : 0n)).toString();
  record.volume5mWei = (BigInt(record.volume5mWei || "0") + (now - timestamp <= 300 ? quoteWei : 0n)).toString();
}

async function processCoreLogs(logs) {
  for (const log of logs) {
    const parsed = coreInterface.parseLog(log);
    if (parsed.name === "TokenRegistered") {
      const record = tokenRecord(parsed.args.token);
      record.token = ethers.getAddress(parsed.args.token);
      record.curve = ethers.getAddress(parsed.args.curve);
      record.creator = ethers.getAddress(parsed.args.creator);
      record.launchPriceUsd8 = parsed.args.launchPriceUsd8.toString();
      record.launchedAt = await blockTimestamp(log.blockNumber);
      await hydrateToken(record);
    } else if (parsed.name === "Graduated") {
      const record = tokenRecord(parsed.args.token);
      record.lifecycle = 3;
      record.poolId = parsed.args.poolId;
      record.positionId = parsed.args.positionId.toString();
      record.graduatedAt = await blockTimestamp(log.blockNumber);
    }
  }
}

async function processRouterLogs(logs, curveActors) {
  for (const log of logs) {
    const parsed = routerInterface.parseLog(log);
    if (parsed.name === "ProtectedBuy") {
      curveActors.set(
        `${log.transactionHash}:buy:${parsed.args.curve.toLowerCase()}`,
        ethers.getAddress(parsed.args.buyer)
      );
      continue;
    }
    if (parsed.name === "ProtectedSell") {
      curveActors.set(
        `${log.transactionHash}:sell:${parsed.args.curve.toLowerCase()}`,
        ethers.getAddress(parsed.args.seller)
      );
      continue;
    }

    const record = tokenRecord(parsed.args.token);
    if (parsed.name === "ProtectedV4Buy") {
      await addTrade(record, {
        blockNumber: log.blockNumber,
        logIndex: log.index,
        txHash: log.transactionHash,
        quoteWei: parsed.args.quoteIn,
        tokenAmount: parsed.args.total,
        side: "buy",
        trader: parsed.args.buyer
      });
    } else if (parsed.name === "ProtectedV4Sell") {
      await addTrade(record, {
        blockNumber: log.blockNumber,
        logIndex: log.index,
        txHash: log.transactionHash,
        quoteWei: parsed.args.quoteOut,
        tokenAmount: parsed.args.tokenIn,
        side: "sell",
        trader: parsed.args.seller
      });
    }
  }
}

async function processCurveLogs(logs, curveToToken, curveActors) {
  for (const log of logs) {
    const parsed = curveInterface.parseLog(log);
    const token = curveToToken.get(log.address.toLowerCase());
    if (!token) continue;
    const record = tokenRecord(token);
    if (parsed.name === "Bought") {
      await addTrade(record, {
        blockNumber: log.blockNumber,
        logIndex: log.index,
        txHash: log.transactionHash,
        quoteWei: parsed.args.quoteIn - parsed.args.fee,
        tokenAmount: parsed.args.tokenOut,
        side: "buy",
        trader: curveActors.get(`${log.transactionHash}:buy:${log.address.toLowerCase()}`)
      });
    } else {
      await addTrade(record, {
        blockNumber: log.blockNumber,
        logIndex: log.index,
        txHash: log.transactionHash,
        quoteWei: parsed.args.quoteOut,
        tokenAmount: parsed.args.tokenIn,
        side: "sell",
        trader: curveActors.get(`${log.transactionHash}:sell:${log.address.toLowerCase()}`)
      });
    }
  }
}

async function sync() {
  const latest = await withRetry(() => provider.getBlockNumber(), "getBlockNumber");
  const startBlock = state.lastBlock == null ? Number(process.env.PROTO_INDEXER_START_BLOCK || Math.max(0, latest - 5_000)) : state.lastBlock + 1;
  if (startBlock > latest) return { latest, indexedThrough: state.lastBlock, discovered: Object.keys(state.tokens).length, scanned: 0 };
  console.log(`sync ${startBlock}-${latest}: scanning core/router logs`);
  const [registered, graduated, protectedBuys, protectedSells, v4Buys, v4Sells] = await Promise.all([
    scanLogs(core, coreInterface, "TokenRegistered", startBlock, latest),
    graduationManager ? scanLogs(graduationManager, coreInterface, "Graduated", startBlock, latest) : [],
    scanLogs(router, routerInterface, "ProtectedBuy", startBlock, latest),
    scanLogs(router, routerInterface, "ProtectedSell", startBlock, latest),
    scanLogs(router, routerInterface, "ProtectedV4Buy", startBlock, latest),
    scanLogs(router, routerInterface, "ProtectedV4Sell", startBlock, latest)
  ]);
  console.log(`backfill ${startBlock}-${latest}: registered=${registered.length} graduated=${graduated.length} buys=${protectedBuys.length} sells=${protectedSells.length} v4Buys=${v4Buys.length} v4Sells=${v4Sells.length}`);
  await processCoreLogs([...registered, ...graduated].sort((a, b) => a.blockNumber - b.blockNumber || a.index - b.index));
  const curves = new Map(Object.values(state.tokens).filter((record) => record.curve).map((record) => [record.curve.toLowerCase(), record.token]));
  const curveLogs = (await mapLimit([...curves.keys()], CURVE_CONCURRENCY, async (curve) => {
    const [bought, sold] = await Promise.all([
      scanLogs(curve, curveInterface, "Bought", startBlock, latest),
      scanLogs(curve, curveInterface, "Sold", startBlock, latest)
    ]);
    return [...bought, ...sold];
  })).flat();
  const curveActors = new Map();
  await processRouterLogs(
    [...protectedBuys, ...protectedSells].sort((a, b) => a.blockNumber - b.blockNumber || a.index - b.index),
    curveActors
  );
  await processCurveLogs(
    curveLogs.sort((a, b) => a.blockNumber - b.blockNumber || a.index - b.index),
    curves,
    curveActors
  );
  await processRouterLogs(
    [...v4Buys, ...v4Sells].sort((a, b) => a.blockNumber - b.blockNumber || a.index - b.index),
    curveActors
  );
  for (const record of Object.values(state.tokens)) await hydrateToken(record);
  const previousLastBlock = state.lastBlock;
  state.lastBlock = latest;
  try {
    await store.save();
  } catch (error) {
    state.lastBlock = previousLastBlock;
    throw error;
  }
  return { latest, indexedThrough: state.lastBlock, discovered: Object.keys(state.tokens).length };
}

function publicToken(record) {
  const result = { ...record };
  result.recentTrades = (record.trades || []).slice(-30).reverse().map((trade) => ({
    timestamp: trade.timestamp,
    side: trade.side,
    trader: trade.trader ? ethers.getAddress(trade.trader) : "",
    tokenAmount: trade.tokenAmount || "0",
    quoteUsd: usdFromWei(BigInt(trade.quoteWei || "0"), BigInt(record.launchPriceUsd8 || "0")),
    priceUsd: trade.priceUsd,
    txHash: trade.txHash
  }));
  delete result.volumeAllTimeWei; delete result.volume1hWei; delete result.volume5mWei; delete result.trades;
  if (!result.hydrationError) delete result.hydrationError;
  result.token = ethers.getAddress(record.token);
  if (record.creator) result.creator = ethers.getAddress(record.creator);
  if (record.curve) result.curve = ethers.getAddress(record.curve);
  result.status = record.lifecycle === 3 ? "graduated" : "curve";
  const firstPrice = Number(record.initialPriceUsd || record.trades?.find((trade) => Number(trade.priceUsd) > 0)?.priceUsd || 0);
  const latestPrice = Number([...(record.trades || [])].reverse().find((trade) => Number(trade.priceUsd) > 0)?.priceUsd || 0);
  result.change = firstPrice > 0 && latestPrice > 0 ? ((latestPrice - firstPrice) / firstPrice) * 100 : 0;
  delete result.initialPriceUsd;
  return result;
}

function response(res, status, body) {
  res.writeHead(status, {
    "content-type": "application/json",
    "access-control-allow-origin": ALLOWED_ORIGIN,
    "access-control-allow-methods": "GET,POST,OPTIONS",
    "access-control-allow-headers": "content-type,x-file-name",
    "cache-control": "no-store"
  });
  res.end(JSON.stringify(body));
}

function clientOrigin(req) {
  return req.headers.origin || "";
}

function originAllowed(req) {
  return ALLOWED_ORIGIN === "*" || !clientOrigin(req) || clientOrigin(req) === ALLOWED_ORIGIN;
}

function clientKey(req) {
  const forwarded = req.headers["x-forwarded-for"];
  return (typeof forwarded === "string" ? forwarded.split(",")[0] : req.socket.remoteAddress) || "unknown";
}

function consumeUploadQuota(req) {
  const now = Date.now();
  const key = clientKey(req);
  const current = uploadWindows.get(key);
  if (!current || now - current.startedAt >= UPLOAD_WINDOW_MS) {
    uploadWindows.set(key, { startedAt: now, count: 1 });
    return true;
  }
  if (current.count >= UPLOAD_MAX_PER_WINDOW) return false;
  current.count += 1;
  return true;
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    req.on("data", (chunk) => {
      size += chunk.length;
      if (size > UPLOAD_MAX_BYTES) {
        reject(Object.assign(new Error("image exceeds upload limit"), { statusCode: 413 }));
        req.destroy();
        return;
      }
      chunks.push(chunk);
    });
    req.on("end", () => resolve(Buffer.concat(chunks)));
    req.on("error", reject);
  });
}

async function uploadImage(req, res) {
  if (!PINATA_JWT) return response(res, 503, { error: "image uploads are not configured" });
  if (!originAllowed(req)) return response(res, 403, { error: "origin not allowed" });
  if (!consumeUploadQuota(req)) return response(res, 429, { error: "upload rate limit exceeded" });
  const contentType = String(req.headers["content-type"] || "").split(";", 1)[0].toLowerCase();
  if (!/^image\/(png|jpeg|webp|gif)$/.test(contentType)) return response(res, 415, { error: "only PNG, JPEG, WEBP, or GIF images are accepted" });
  if (Number(req.headers["content-length"] || 0) > UPLOAD_MAX_BYTES) return response(res, 413, { error: "image exceeds upload limit" });
  const body = await readBody(req);
  if (!body.length) return response(res, 400, { error: "image body is empty" });
  const form = new FormData();
  const fileName = String(req.headers["x-file-name"] || "token-image").replace(/[^a-zA-Z0-9._-]/g, "_").slice(0, 120) || "token-image";
  form.append("file", new Blob([body], { type: contentType }), fileName);
  const upstream = await fetch("https://uploads.pinata.cloud/v3/files", {
    method: "POST",
    headers: { Authorization: `Bearer ${PINATA_JWT}` },
    body: form
  });
  if (!upstream.ok) {
    const detail = await upstream.text();
    console.error(`Pinata upload failed (${upstream.status}): ${detail.slice(0, 300)}`);
    return response(res, 502, { error: "image upload provider failed" });
  }
  const result = await upstream.json();
  const cid = result.data?.cid || result.IpfsHash;
  if (!cid) return response(res, 502, { error: "image upload provider returned no CID" });
  return response(res, 201, { cid, url: `${PINATA_GATEWAY}/${cid}` });
}

async function handle(req, res) {
  const url = new URL(req.url, "http://localhost");
  if (req.method === "OPTIONS") return response(res, 204, {});
  if (req.method === "POST" && url.pathname === "/upload") return uploadImage(req, res);
  if (req.method !== "GET") return response(res, 405, { error: "method not allowed" });
  if (url.pathname === "/health") {
    const records = Object.values(state.tokens);
    return response(res, 200, {
      ok: true,
      chainId: 4663,
      storage: store.kind,
      indexedThrough: state.lastBlock,
      discovered: records.length,
      hydrated: records.filter((item) => item.name && item.symbol).length,
      hydrationErrors: records.filter((item) => item.hydrationError).length,
      lastSync
    });
  }
  if (url.pathname === "/tokens") {
    const records = Object.values(state.tokens).map(publicToken);
    const filtered = url.searchParams.get("status") === "graduated" ? records.filter((item) => item.status === "graduated") : records;
    const sort = url.searchParams.get("sort") || "volume_1h";
    const key = sort === "launched_at" ? "launchedAt" : sort === "volume_5m" ? "volume5m" : "volume1h";
    filtered.sort((a, b) => Number(b[key] || 0) - Number(a[key] || 0));
    return response(res, 200, filtered);
  }
  const tokenMatch = url.pathname.match(/^\/tokens\/(0x[a-fA-F0-9]{40})$/);
  if (tokenMatch) {
    const record = state.tokens[tokenMatch[1].toLowerCase()];
    return record ? response(res, 200, publicToken(record)) : response(res, 404, { error: "token not found" });
  }
  const profileMatch = url.pathname.match(/^\/profiles\/(0x[a-fA-F0-9]{40})$/);
  if (profileMatch) {
    const address = ethers.getAddress(profileMatch[1]);
    const records = Object.values(state.tokens);
    const created = records.filter((item) => item.creator?.toLowerCase() === address.toLowerCase()).map(publicToken);
    const holdings = [];
    const vault = process.env.VESTING_VAULT;
    for (const record of records) {
      try {
        const balance = await call(record.token, tokenInterface, "balanceOf", [address]).then((value) => value[0]);
        const committed = vault ? await call(ethers.getAddress(vault), vaultInterface, "committedBalance", [record.token, address]).then((value) => value[0]) : 0n;
        if (balance > 0n || committed > 0n) holdings.push({ ...publicToken(record), liquidBalance: balance.toString(), committedBalance: committed.toString() });
      } catch { /* skip tokens whose RPC reads are temporarily unavailable */ }
    }
    return response(res, 200, { address, name: "Proto explorer", bio: "Building in public on Robinhood Chain.", avatar: "/proto-mark.png", created, holdings });
  }
  return response(res, 404, { error: "not found" });
}

const server = http.createServer((req, res) => {
  handle(req, res).catch((error) => response(res, error.statusCode || 500, { error: error.message }));
});
server.listen(PORT, () => console.log(`Proto indexer listening on http://localhost:${PORT}`));

let syncInFlight = false;
async function poll() {
  if (syncInFlight) {
    console.warn("indexer sync still running; skipping overlapping poll");
    return;
  }
  syncInFlight = true;
  try {
    const result = await sync();
    lastSync = { at: new Date().toISOString(), ...result };
    console.log("index", result);
  } catch (error) {
    lastSync = { at: new Date().toISOString(), error: error.message };
    console.error("indexer sync failed", error);
  } finally {
    syncInFlight = false;
  }
}
await poll();
setInterval(poll, POLL_MS);
