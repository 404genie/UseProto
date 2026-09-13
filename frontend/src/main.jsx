import React, { useEffect, useMemo, useState } from "react";
import { createRoot } from "react-dom/client";
import { ethers } from "ethers";
import { client, connectWallet, fallbackTokens, fetchProfile, fetchToken, fetchTokens, uploadTokenImage } from "./data.js";
import "./styles.css";

const shorten = (value = "") => value ? `${value.slice(0, 6)}…${value.slice(-4)}` : "";
const money = (value = 0) => {
  const amount = Number(value || 0);
  if (!Number.isFinite(amount)) return "$—";
  const absolute = Math.abs(amount);
  const units = [[1e12, "T"], [1e9, "B"], [1e6, "M"], [1e3, "k"]];
  for (const [threshold, suffix] of units) {
    if (absolute >= threshold) {
      const scaled = amount / threshold;
      const digits = Math.abs(scaled) >= 100 ? 0 : Math.abs(scaled) >= 10 ? 1 : 2;
      return `$${scaled.toFixed(digits).replace(/\.00$|(?<=\.[0-9])0$/, "")}${suffix}`;
    }
  }
  return new Intl.NumberFormat("en-US", { style: "currency", currency: "USD", maximumFractionDigits: 2 }).format(amount);
};
const age = (value) => value || "just now";

function Logo({ compact = false }) {
  return <a className={`brand ${compact ? "brand-compact" : ""}`} href="#/explore" aria-label="Proto home"><img src="/proto-mark.png" alt="" className="brand-mark" /><span className="brand-wordmark"><img src="/proto-wordmark.png" alt="Proto" /></span></a>;
}

function WalletButton({ address, onConnect, onOpenProfile }) {
  return <button className="wallet-button" onClick={address ? onOpenProfile : onConnect}><span className="wallet-dot" />{address ? shorten(address) : "Connect wallet"}</button>;
}

function ProfilePrompt({ onSave, onSkip }) {
  const [name, setName] = useState("");
  const [bio, setBio] = useState("");
  const [avatar, setAvatar] = useState("");
  const chooseAvatar = (event) => { const file = event.target.files?.[0]; if (!file) return; const reader = new FileReader(); reader.onload = () => setAvatar(String(reader.result)); reader.readAsDataURL(file); };
  return <div className="modal-backdrop"><div className="modal profile-prompt"><button className="modal-close" onClick={onSkip}>×</button><div className="modal-kicker">WELCOME TO PROTO</div><h2>Make your profile yours.</h2><p>Add a name, avatar, and short bio now — or skip and do it later from your profile.</p><label className="avatar-picker"><input type="file" accept="image/*" onChange={chooseAvatar} />{avatar ? <img src={avatar} alt="Preview" /> : <span>＋</span>}</label><label className="field"><span>Display name <em>optional</em></span><input value={name} onChange={(event) => setName(event.target.value)} placeholder="How should we call you?" maxLength={40} /></label><label className="field"><span>Bio <em>optional</em></span><textarea value={bio} onChange={(event) => setBio(event.target.value)} placeholder="A sentence about you" maxLength={160} /></label><button className="primary-button full" onClick={() => onSave({ name, bio, avatar })}>Save profile</button><button className="text-button" onClick={onSkip}>Skip for now</button></div></div>;
}

function Header({ address, onConnect, onOpenProfile }) {
  return <header className="topbar"><Logo /><nav><a href="#/explore">Explore</a><a href="#/profile">Profile</a></nav><WalletButton address={address} onConnect={onConnect} onOpenProfile={onOpenProfile} /></header>;
}

function TokenImage({ token, large = false }) {
  return <div className={`token-image ${large ? "token-image-large" : ""}`}><img src={token.image || "/proto-mark.png"} alt="" /><span className="token-image-glow" /></div>;
}

function TokenCard({ token, onOpen }) {
  const name = token.name || "Unnamed token";
  const symbol = token.symbol || "PROTO";
  return <button className="token-card" onClick={() => onOpen(token.token)}><div className="card-top"><TokenImage token={token} /><div className="card-identity"><strong>{name}</strong><span>${symbol}</span></div><span className={`status-pill ${token.status}`}>{token.status === "graduated" ? "V4" : "CURVE"}</span></div><div className="card-metrics"><div><span>Market cap</span><strong>{money(token.marketCap)}</strong></div><div><span>All-time volume</span><strong>{money(token.volumeAllTime)}</strong></div></div><div className="card-bottom"><span>{age(token.age)} old</span><span className={token.change >= 0 ? "positive" : "negative"}>{token.change >= 0 ? "↗" : "↘"} {Math.abs(token.change).toFixed(1)}%</span></div></button>;
}

function Explore({ onOpen, onCreate }) {
  const [tab, setTab] = useState("trending");
  const [tokens, setTokens] = useState(fallbackTokens);
  const [updated, setUpdated] = useState(new Date());
  useEffect(() => { let active = true; const load = async () => { const next = await fetchTokens(tab); if (active) { setTokens(next); setUpdated(new Date()); } }; load(); const timer = setInterval(load, 15000); return () => { active = false; clearInterval(timer); }; }, [tab]);
  return <main className="page"><section className="explore-hero"><div><div className="eyebrow"><span className="live-dot" />LIVE MARKETS · ROBINHOOD CHAIN</div><h1>Find what’s <span>next.</span></h1><p>Discover new launches, follow the momentum, and trade tokens before they graduate to Uniswap V4.</p></div><button className="primary-button create-button" onClick={onCreate}><span>＋</span> Create token</button></section><section className="market-toolbar"><div className="tabs">{[["trending", "Trending"], ["graduated", "Newly graduated"], ["new", "Newly created"]].map(([value, label]) => <button className={tab === value ? "active" : ""} onClick={() => setTab(value)} key={value}>{label}{value === "trending" && <small>1h / 5m vol</small>}</button>)}</div><div className="refresh-label"><span className="refresh-icon">↻</span> Auto-refresh · {updated.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })}</div></section><div className="token-grid">{tokens.map((token) => <TokenCard token={token} onOpen={onOpen} key={token.token} />)}</div></main>;
}

function Create({ address, txClient, onConnect, onCreated }) {
  const [form, setForm] = useState({ name: "", symbol: "", description: "", x: "" });
  const [image, setImage] = useState("");
  const [file, setFile] = useState(null);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const set = (key, value) => setForm((current) => ({ ...current, [key]: value }));
  const choose = (event) => { const picked = event.target.files?.[0]; if (!picked) return; setFile(picked); setImage(URL.createObjectURL(picked)); };
  const submit = async (event) => { event.preventDefault(); if (!address) return onConnect(); if (!form.name || !form.symbol || !form.description || !file) return setMessage("Add a name, symbol, description, and token image first."); setBusy(true); setMessage(""); try { const imageUrl = await uploadTokenImage(file); const activeClient = txClient || client; if (!activeClient) { setMessage("Set VITE_RH_RPC_URL in frontend/.env.local before launching."); return; } const tx = await activeClient.createToken({ name: form.name, symbol: form.symbol, metadataURI: JSON.stringify({ description: form.description, image: imageUrl, x: form.x }) }); await tx.wait(); onCreated(); } catch (error) { setMessage(error.shortMessage || error.message || "Launch failed"); } finally { setBusy(false); } };
  return <main className="page narrow-page"><div className="form-heading"><a href="#/explore" className="back-link">← Back to explore</a><div className="eyebrow">CREATE ON PROTO</div><h1>Give it a name.<br /><span>Give it a shot.</span></h1><p>Launch a fixed-supply token directly onto Proto’s bonding curve. No liquidity deposit required.</p></div><form className="create-form" onSubmit={submit}><div className="image-upload-row"><label className="image-drop"><input type="file" accept="image/png,image/jpeg,image/webp,image/gif" onChange={choose} />{image ? <img src={image} alt="Token preview" /> : <><span className="upload-plus">＋</span><strong>Token image</strong><small>PNG, JPG, WEBP or GIF · max 5MB</small></>}</label><div className="form-note"><span className="note-icon">✦</span><p>Your image will be pinned to IPFS and attached to the token metadata.</p></div></div><div className="form-grid"><label className="field"><span>Token name</span><input value={form.name} onChange={(event) => set("name", event.target.value)} placeholder="e.g. Proto Dog" maxLength={64} /></label><label className="field"><span>Symbol</span><input value={form.symbol} onChange={(event) => set("symbol", event.target.value.toUpperCase())} placeholder="e.g. PDOG" maxLength={16} /></label></div><label className="field"><span>Description</span><textarea value={form.description} onChange={(event) => set("description", event.target.value)} placeholder="What makes this token worth watching?" maxLength={512} rows={4} /></label><label className="field"><span>X link <em>optional</em></span><input value={form.x} onChange={(event) => set("x", event.target.value)} placeholder="https://x.com/yourtoken" /></label><div className="launch-summary"><div><span>Supply</span><strong>1,000,000,000</strong></div><div><span>Liquid cap</span><strong>2% per wallet</strong></div><div><span>Vesting</span><strong>30 days</strong></div></div>{message && <div className="form-message">{message}</div>}<button className="primary-button full" disabled={busy}>{busy ? "Launching…" : "Launch token"}</button><p className="form-footnote">By launching, you agree that token economics are fixed by Proto V1.</p></form></main>;
}

function LineChart({ points = [] }) {
  const values = points.length ? points : [34, 38, 35, 44, 41, 49, 47, 58, 54, 65, 61, 72, 70, 82];
  const min = Math.min(...values); const max = Math.max(...values); const range = max - min || 1;
  const coords = values.map((value, index) => `${(index / (values.length - 1)) * 100},${94 - ((value - min) / range) * 78}`).join(" ");
  const area = `0,100 ${coords} 100,100`;
  return <div className="chart"><svg viewBox="0 0 100 100" preserveAspectRatio="none" role="img" aria-label="Token price chart"><defs><linearGradient id="chart-fill" x1="0" x2="0" y1="0" y2="1"><stop offset="0" stopColor="#f4ff18" stopOpacity=".26" /><stop offset="1" stopColor="#f4ff18" stopOpacity="0" /></linearGradient></defs><polyline className="chart-area" points={area} /><polyline className="chart-line" points={coords} /></svg><div className="chart-axis"><span>1D</span><span>1W</span><span>1M</span><span>ALL</span></div></div>;
}

function Trade({ tokenAddress, txClient, onOpenProfile, onConnect }) {
  const [token, setToken] = useState(null);
  const [mode, setMode] = useState("buy");
  const [amount, setAmount] = useState("");
  const [estimate, setEstimate] = useState(null);
  const [copied, setCopied] = useState(false);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  useEffect(() => { let active = true; fetchToken(tokenAddress).then((item) => active && setToken(item)); return () => { active = false; }; }, [tokenAddress]);
  useEffect(() => {
    let active = true;
    const quote = async () => {
      const quoteClient = txClient || client;
      const isGraduated = token?.status === "graduated";
      if (!token || !amount || Number(amount) <= 0 || !quoteClient || (isGraduated && !txClient)) return setEstimate(null);
      try {
        const deadline = BigInt(Math.floor(Date.now() / 1000) + 900);
        const account = isGraduated ? await quoteClient.account() : null;
        const result = mode === "buy"
          ? isGraduated
            ? await quoteClient.quoteBuyV4({ token: token.token, recipient: account, value: ethers.parseEther(amount), deadline })
            : await quoteClient.quoteBuy(token.curve, ethers.parseEther(amount))
          : isGraduated
            ? await quoteClient.quoteSellV4({ token: token.token, tokenIn: ethers.parseUnits(amount, 18), recipient: account, deadline })
            : await quoteClient.quoteSell(token.curve, ethers.parseUnits(amount, 18));
        if (active) setEstimate(mode === "buy" ? (isGraduated ? result.totalOut : result.tokenOut) : result.quoteOut);
      } catch { if (active) setEstimate(null); }
    };
    quote();
    return () => { active = false; };
  }, [token, amount, mode, txClient]);
  if (!token) return <main className="page loading">Loading market…</main>;
  const copy = async () => { await navigator.clipboard?.writeText(token.token); setCopied(true); setTimeout(() => setCopied(false), 1600); };
  const submit = async () => {
    if (!txClient) return onConnect();
    if (!amount || Number(amount) <= 0) return setMessage("Enter an amount first.");
    if (mode === "buy" && !estimate) return setMessage("Waiting for a protected quote. Try again in a moment.");
    setBusy(true); setMessage("");
    try {
      const deadline = BigInt(Math.floor(Date.now() / 1000) + 900);
      const isGraduated = token.status === "graduated";
      if (mode === "buy") {
        const value = ethers.parseEther(amount);
        const minOut = estimate * 98n / 100n;
        const tx = isGraduated ? await txClient.buyV4({ token: token.token, value, minTotalOut: minOut, deadline }) : await txClient.buy({ curve: token.curve, value, minTotalOut: minOut, deadline });
        await tx.wait();
      } else {
        const tokenIn = ethers.parseUnits(amount, 18);
        const approval = await txClient.approveRouter(token.token, tokenIn); await approval.wait();
        let quoteOut = estimate;
        if (!quoteOut) {
          const quote = isGraduated
            ? await txClient.quoteSellV4({ token: token.token, tokenIn, deadline })
            : await txClient.quoteSell(token.curve, tokenIn);
          quoteOut = quote.quoteOut;
        }
        if (!quoteOut) throw new Error("Unable to obtain a protected sell quote");
        const minOut = quoteOut * 98n / 100n;
        const tx = isGraduated ? await txClient.sellV4({ token: token.token, tokenIn, minQuoteOut: minOut, deadline }) : await txClient.sell({ curve: token.curve, tokenIn, minQuoteOut: minOut, deadline });
        await tx.wait();
      }
      setMessage("Trade confirmed on Robinhood Chain."); setAmount("");
    } catch (error) { setMessage(error.shortMessage || error.message || "Trade failed"); } finally { setBusy(false); }
  };
  const output = estimate == null ? "0.00" : mode === "buy" ? Number(ethers.formatUnits(estimate, 18)).toLocaleString(undefined, { maximumFractionDigits: 2 }) : Number(ethers.formatEther(estimate)).toLocaleString(undefined, { maximumFractionDigits: 5 });
  return <main className="page trade-page"><div className="trade-breadcrumb"><a href="#/explore">Explore</a><span>/</span><strong>${token.symbol}</strong></div><section className="trade-heading"><div className="trade-token-title"><TokenImage token={token} large /><div><div className="eyebrow">{token.status === "graduated" ? "UNISWAP V4 MARKET" : "PROTO BONDING CURVE"}</div><h1>{token.name} <span>${token.symbol}</span></h1><button className="ca-button" onClick={copy}>CA {shorten(token.token)} <span>{copied ? "Copied" : "▣"}</span></button></div></div><button className="creator-link" onClick={() => onOpenProfile(token.creator)}><span className="mini-avatar"><img src="/proto-mark.png" alt="" /></span> Created by {shorten(token.creator)} ↗</button></section><div className="trade-layout"><section className="chart-panel"><div className="chart-stats"><div><span>Market cap</span><strong>{money(token.marketCap)}</strong></div><div><span>24h volume</span><strong>{money(token.volume1h * 10)}</strong></div><div><span>Token age</span><strong>{age(token.age)}</strong></div><div className={token.change >= 0 ? "positive" : "negative"}><span>All time</span><strong>{token.change >= 0 ? "+" : ""}{token.change.toFixed(1)}%</strong></div></div><LineChart points={token.chart} /></section><section className="swap-panel"><div className="swap-tabs"><button className={mode === "buy" ? "active" : ""} onClick={() => { setMode("buy"); setEstimate(null); }}>Buy</button><button className={mode === "sell" ? "active" : ""} onClick={() => { setMode("sell"); setEstimate(null); }}>Sell</button></div><div className="swap-caption">{mode === "buy" ? "Buy with native ETH" : "Sell liquid tokens"}</div><label className="swap-input"><span>{mode === "buy" ? "You pay" : "You sell"}</span><input value={amount} onChange={(event) => setAmount(event.target.value)} placeholder="0.00" inputMode="decimal" /><strong>{mode === "buy" ? "ETH" : token.symbol}</strong></label><div className="swap-arrow">↓</div><div className="swap-input output"><span>Estimated receive</span><strong>{output}</strong><strong>{mode === "buy" ? token.symbol : "ETH"}</strong></div><div className="swap-details"><span>Proto fee <b>1%</b></span><span>Liquid allocation <b>up to 2%</b></span><span>Slippage protection <b>2% buffer</b></span></div>{message && <div className="form-message">{message}</div>}<button className="primary-button full" onClick={submit} disabled={busy}>{busy ? "Confirming…" : txClient ? `${mode === "buy" ? "Buy" : "Sell"} ${token.symbol}` : `Connect wallet to ${mode}`}</button><p className="swap-note">Excess allocation is automatically committed to 30-day vesting.</p></section></div></main>;
}

function Profile({ address, onConnect, onOpen, onEditProfile }) {
  const [profile, setProfile] = useState(null); const user = address || "0xd3e65218345AE57deBb8585dfb759763d0Fd6e78";
  useEffect(() => { let active = true; fetchProfile(user).then((item) => { const saved = user.toLowerCase() === address?.toLowerCase() ? JSON.parse(localStorage.getItem("proto-profile") || "null") : null; if (active) setProfile(saved ? { ...item, ...saved, address: user } : item); }); return () => { active = false; }; }, [user, address]);
  if (!profile) return <main className="page loading">Loading profile…</main>;
  return <main className="page profile-page"><section className="profile-header"><div className="profile-avatar"><img src={profile.avatar || "/proto-mark.png"} alt="" /></div><div className="profile-copy"><div className="eyebrow">PROTO PROFILE</div><h1>{profile.name || "Unnamed builder"}</h1><button className="address-link" onClick={() => navigator.clipboard?.writeText(profile.address)}>{shorten(profile.address)} <span>▣</span></button><p>{profile.bio || "No bio yet."}</p></div>{address && <button className="outline-button" onClick={onEditProfile}>Edit profile</button>}</section><section className="profile-stats"><div><span>Tokens created</span><strong>{profile.created?.length || 0}</strong></div><div><span>Proto holdings</span><strong>{profile.holdings?.length || 0}</strong></div><div><span>Member since</span><strong>Today</strong></div></section><section className="profile-section"><div className="section-heading"><h2>Tokens created</h2><span>{profile.created?.length || 0}</span></div><div className="token-grid compact-grid">{(profile.created?.length ? profile.created : []).map((token) => <TokenCard token={token} onOpen={onOpen} key={token.token} />)}{!profile.created?.length && <div className="empty-state">Your launched tokens will appear here.</div>}</div></section><section className="profile-section"><div className="section-heading"><h2>Holdings</h2><span>{profile.holdings?.length || 0}</span></div><div className="token-grid compact-grid">{(profile.holdings || []).map((token) => <TokenCard token={token} onOpen={onOpen} key={token.token} />)}</div></section>{!address && <button className="primary-button" onClick={onConnect}>Connect to see your profile</button>}</main>;
}

function App() {
  const [address, setAddress] = useState(""); const [txClient, setTxClient] = useState(null); const [profilePrompt, setProfilePrompt] = useState(false); const [route, setRoute] = useState(window.location.hash || "#/explore");
  useEffect(() => { const update = () => setRoute(window.location.hash || "#/explore"); window.addEventListener("hashchange", update); return () => window.removeEventListener("hashchange", update); }, []);
  const connect = async () => { try { const connection = await connectWallet(); setAddress(connection.account); setTxClient(connection.client); if (!localStorage.getItem("proto-profile")) setProfilePrompt(true); } catch (error) { alert(error.message || "Wallet connection failed"); } };
  const saveProfile = (value) => { const next = { ...value, address }; localStorage.setItem("proto-profile", JSON.stringify(next)); setProfilePrompt(false); };
  const open = (token) => { window.location.hash = `#/token/${token}`; };
  const openProfile = (user = address) => { window.location.hash = user ? `#/profile/${user}` : "#/profile"; };
  const page = useMemo(() => { if (route.startsWith("#/create")) return <Create address={address} txClient={txClient} onConnect={connect} onCreated={() => { window.location.hash = "#/explore"; }} />; if (route.startsWith("#/token/")) return <Trade tokenAddress={route.split("/")[2]} txClient={txClient} onOpenProfile={openProfile} onConnect={connect} />; if (route.startsWith("#/profile")) return <Profile address={route.split("/")[2] || address} onConnect={connect} onOpen={open} onEditProfile={() => setProfilePrompt(true)} />; return <Explore onOpen={open} onCreate={() => { window.location.hash = "#/create"; }} />; }, [route, address, txClient]);
  return <><Header address={address} onConnect={connect} onOpenProfile={() => openProfile(address)} />{page}<footer><Logo compact /><span>Permissionless launches on Robinhood Chain.</span><a href="https://github.com" target="_blank" rel="noreferrer">Docs ↗</a></footer>{profilePrompt && <ProfilePrompt address={address} onSave={saveProfile} onSkip={() => setProfilePrompt(false)} />}</>;
}

createRoot(document.getElementById("root")).render(<App />);
