import { ProtoClient } from "../../sdk/index.mjs";
import deployment from "../../deployments/robinhood-testnet.json";
import { ethers } from "ethers";

const INDEXER_URL = import.meta.env.VITE_PROTO_INDEXER_URL?.replace(/\/$/, "") || "";
const RPC_URL = import.meta.env.VITE_RH_RPC_URL || "";
export const client = RPC_URL ? new ProtoClient({ rpcUrl: RPC_URL, deployment }) : null;

export async function uploadTokenImage(file) {
  if (!INDEXER_URL) throw new Error("Set VITE_PROTO_INDEXER_URL to enable secure image uploads.");
  const response = await fetch(`${INDEXER_URL}/upload`, {
    method: "POST",
    headers: { "content-type": file.type, "x-file-name": file.name },
    body: file
  });
  const result = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(result.error || `Image upload failed (${response.status})`);
  if (!result.url) throw new Error("Image upload returned no URL");
  return result.url;
}

const ageInMinutes = (value) => {
  const match = String(value).match(/([0-9.]+)\s*(m|h|d)/i);
  if (!match) return Number.POSITIVE_INFINITY;
  const amount = Number(match[1]);
  return match[2].toLowerCase() === "d" ? amount * 1440 : match[2].toLowerCase() === "h" ? amount * 60 : amount;
};

export async function connectWallet() {
  if (!window.ethereum) throw new Error("Install an EVM wallet to connect to Robinhood Chain.");
  const provider = new ethers.BrowserProvider(window.ethereum);
  const accounts = await provider.send("eth_requestAccounts", []);
  const network = await provider.getNetwork();
  if (network.chainId !== 46630n) throw new Error("Switch your wallet to Robinhood Chain (46630) before connecting.");
  const signer = await provider.getSigner(accounts[0]);
  const account = ethers.getAddress(accounts[0]);
  return { account, client: new ProtoClient({ provider, signer, deployment }) };
}

const FALLBACK_TOKENS = [
  { token: "0xB84934eF1FdaE0096551Fc80333E3ae182e5F8d7", symbol: "SMOKE", name: "Proto Smoke", image: "/proto-mark.png", age: "2h", marketCap: 2464, volumeAllTime: 12840, volume1h: 5440, volume5m: 1260, status: "curve", creator: "0xd3e65218345AE57deBb8585dfb759763d0Fd6e78", change: 18.4 },
  { token: "0x1111111111111111111111111111111111111111", symbol: "NOVA", name: "Nova Protocol", image: "/proto-mark.png", age: "11m", marketCap: 18420, volumeAllTime: 9240, volume1h: 3120, volume5m: 880, status: "curve", creator: "0x91c2a45d3b1b8c5dd6f1e14e0112b73516f2c31a", change: 9.7 },
  { token: "0x2222222222222222222222222222222222222222", symbol: "MINT", name: "Mint Club", image: "/proto-mark.png", age: "1d", marketCap: 56200, volumeAllTime: 118900, volume1h: 8700, volume5m: 2100, status: "graduated", creator: "0x602e8f0e4a0ea72168b3c9d8f2c8bead6dff9d10", change: -3.2 },
  { token: "0x3333333333333333333333333333333333333333", symbol: "BLOB", name: "Blob Energy", image: "/proto-mark.png", age: "3d", marketCap: 119800, volumeAllTime: 422000, volume1h: 18200, volume5m: 5200, status: "graduated", creator: "0x338b1fcab2ea82b0b053ad7bd6f6e9a9e5f7cd21", change: 26.8 }
];

async function indexed(path, fallback) {
  if (!INDEXER_URL) return fallback;
  try {
    const response = await fetch(`${INDEXER_URL}${path}`, { headers: { accept: "application/json" } });
    if (!response.ok) throw new Error(`indexer ${response.status}`);
    return await response.json();
  } catch {
    return fallback;
  }
}

async function hydrateSparseToken(record) {
  if (!client || !record?.token || (record.name && record.symbol)) return record;
  try {
    const info = await client.getTokenInfo(record.token);
    let metadata = {};
    try {
      const parsed = JSON.parse(info.metadataURI || "{}");
      if (parsed && typeof parsed === "object") metadata = parsed;
    } catch { /* metadata is optional */ }
    return {
      ...record,
      ...info,
      name: record.name || info.name,
      symbol: record.symbol || info.symbol,
      image: record.image || metadata.image || "/proto-mark.png",
      description: record.description || metadata.description,
      x: record.x || metadata.x
    };
  } catch {
    return record;
  }
}

export async function fetchTokens(tab = "trending") {
  const query = tab === "trending" ? "?sort=volume_1h" : tab === "graduated" ? "?status=graduated&sort=launched_at" : "?sort=launched_at";
  const fallback = tab === "graduated"
      ? FALLBACK_TOKENS.filter((item) => item.status === "graduated")
      : tab === "new"
      ? FALLBACK_TOKENS.filter((item) => item.status === "curve").sort((a, b) => ageInMinutes(a.age) - ageInMinutes(b.age))
      : [...FALLBACK_TOKENS].sort((a, b) => b.volume1h - a.volume1h);
  const result = await indexed(`/tokens${query}`, fallback);
  const records = Array.isArray(result) ? result : result.tokens || FALLBACK_TOKENS;
  return Promise.all(records.map(hydrateSparseToken));
}

export async function fetchToken(address) {
  const fallback = FALLBACK_TOKENS.find((item) => item.token.toLowerCase() === address.toLowerCase()) || { ...FALLBACK_TOKENS[0], token: address };
  const result = await indexed(`/tokens/${address}`, fallback);
  if (result?.token) return hydrateSparseToken(result);
  if (client) {
    try {
      const info = await client.getTokenInfo(address);
      return { ...fallback, ...info, image: fallback.image, marketCap: Number(info.launchPriceUsd8 / 100000000n), volumeAllTime: 0, chart: [] };
    } catch { /* indexer remains optional while the UI is being integrated */ }
  }
  return fallback;
}

export async function fetchProfile(address) {
  const fallback = { address, name: "Proto explorer", bio: "Building in public on Robinhood Chain.", avatar: "/proto-mark.png", created: FALLBACK_TOKENS.filter((item) => item.creator.toLowerCase() === address.toLowerCase()), holdings: FALLBACK_TOKENS.slice(0, 2) };
  return indexed(`/profiles/${address}`, fallback);
}

export const fallbackTokens = FALLBACK_TOKENS;
