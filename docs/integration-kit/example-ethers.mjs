import { ethers } from "ethers";
import deployment from "./deployment.json" with { type: "json" };
import { CORE_ABI, CURVE_ABI, ROUTER_ABI, TOKEN_ABI, VESTING_ABI } from "../../sdk/abis.mjs";

const provider = new ethers.JsonRpcProvider(deployment.rpcUrl, deployment.chainId);
const addresses = deployment.contracts;

export async function getMarket(tokenAddress) {
  const token = ethers.getAddress(tokenAddress);
  const core = new ethers.Contract(addresses.core, CORE_ABI, provider);
  const tokenContract = new ethers.Contract(token, TOKEN_ABI, provider);
  const info = await core.tokenInfo(token);
  const curve = new ethers.Contract(info.curve, CURVE_ABI, provider);
  const [name, symbol, decimals, graduated, state, spotPriceWad] = await Promise.all([
    tokenContract.name(),
    tokenContract.symbol(),
    tokenContract.decimals(),
    core.isGraduated(token),
    curve.state(),
    curve.spotPriceWad()
  ]);
  return {
    token,
    curve: ethers.getAddress(info.curve),
    creator: ethers.getAddress(info.creator),
    name,
    symbol,
    decimals: Number(decimals),
    lifecycle: Number(info.lifecycle),
    graduated,
    curveState: Number(state),
    spotPriceWad: BigInt(spotPriceWad),
    metadataURI: info.metadataURI
  };
}

export async function quoteCurveBuy(tokenAddress, ethAmount) {
  const market = await getMarket(tokenAddress);
  const curve = new ethers.Contract(market.curve, CURVE_ABI, provider);
  const quoteIn = ethers.parseEther(ethAmount);
  const [tokenOut, fee] = await curve.quoteBuy(quoteIn);
  return { quoteIn, tokenOut: BigInt(tokenOut), fee: BigInt(fee) };
}

export async function buildCurveBuy(tokenAddress, recipient, ethAmount, slippageBps = 200, ttlSeconds = 300) {
  const market = await getMarket(tokenAddress);
  if (market.lifecycle !== 1 || market.graduated) throw new Error("token is not on an active Proto curve");
  const curve = new ethers.Contract(market.curve, CURVE_ABI, provider);
  const quoteIn = ethers.parseEther(ethAmount);
  const [quotedTotalOut] = await curve.quoteBuy(quoteIn);
  const minTotalOut = BigInt(quotedTotalOut) * BigInt(10_000 - slippageBps) / 10_000n;
  const deadline = BigInt(Math.floor(Date.now() / 1000) + ttlSeconds);
  const router = new ethers.Interface(ROUTER_ABI);
  return {
    to: addresses.router,
    data: router.encodeFunctionData("buy", [market.curve, ethers.getAddress(recipient), minTotalOut, deadline]),
    value: quoteIn,
    minTotalOut,
    quotedTotalOut,
    deadline
  };
}

export async function getUserBalances(tokenAddress, userAddress, maxPositions = 50) {
  const token = new ethers.Contract(ethers.getAddress(tokenAddress), TOKEN_ABI, provider);
  const vault = new ethers.Contract(addresses.vestingVault, VESTING_ABI, provider);
  const user = ethers.getAddress(userAddress);
  const [liquid, committed, claimable] = await Promise.all([
    token.balanceOf(user),
    vault.committedBalance(token.target, user),
    vault.claimable(token.target, user, maxPositions)
  ]);
  return { liquid: BigInt(liquid), committed: BigInt(committed), claimable: BigInt(claimable) };
}
