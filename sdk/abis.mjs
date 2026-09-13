export const CORE_ABI = [
  "function tokenInfo(address) view returns (address creator,address curve,uint256 launchPriceUsd8,uint256 virtualQuoteReserve,uint64 launchedAt,uint8 lifecycle,string metadataURI)",
  "function curveOf(address) view returns (address)",
  "function creatorOf(address) view returns (address)",
  "function poolOf(address) view returns (bytes32)",
  "function positionOf(address) view returns (uint256)",
  "function isGraduated(address) view returns (bool)"
];

export const FACTORY_ABI = [
  "function createToken(string name,string symbol,string metadataURI) returns (address tokenAddress,address curveAddress)",
  "function launchCount() view returns (uint256)",
  "function TOTAL_SUPPLY() view returns (uint256)",
  "function TRADING_FEE_BPS() view returns (uint16)",
  "function GRADUATION_THRESHOLD() view returns (uint256)"
];

export const ROUTER_ABI = [
  "function buy(address curve,address recipient,uint256 minTotalOut,uint256 deadline) payable returns (uint256 totalOut,uint256 liquid,uint256 committed)",
  "function sell(address curve,uint256 tokenIn,uint256 minQuoteOut,uint256 deadline,address recipient) returns (uint256 quoteOut)",
  "function buyV4(address token,address recipient,uint256 minTotalOut,uint160 sqrtPriceLimitX96,uint256 deadline) payable returns (uint256 totalOut,uint256 liquid,uint256 committed)",
  "function sellV4(address token,uint256 tokenIn,address recipient,uint256 minQuoteOut,uint160 sqrtPriceLimitX96,uint256 deadline) returns (uint256 quoteOut)",
  "function curveInfo(address) view returns (address token,address creator,bool registered)",
  "function v4Bound() view returns (bool)"
];

export const CURVE_ABI = [
  "function token() view returns (address)",
  "function quoteBuy(uint256 quoteIn) view returns (uint256 tokenOut,uint256 fee)",
  "function quoteSell(uint256 tokenIn) view returns (uint256 quoteOut,uint256 fee,uint256 grossQuoteOut)",
  "function spotPriceWad() view returns (uint256)",
  "function realQuoteReserve() view returns (uint256)",
  "function realTokenReserve() view returns (uint256)",
  "function virtualQuoteReserve() view returns (uint256)",
  "function virtualTokenReserve() view returns (uint256)",
  "function graduationThreshold() view returns (uint256)",
  "function tradingFeeBps() view returns (uint16)",
  "function state() view returns (uint8)",
  "function reservesReconcile() view returns (bool)"
];

export const TOKEN_ABI = [
  "function name() view returns (string)",
  "function symbol() view returns (string)",
  "function decimals() view returns (uint8)",
  "function totalSupply() view returns (uint256)",
  "function balanceOf(address) view returns (uint256)",
  "function allowance(address,address) view returns (uint256)",
  "function approve(address,uint256) returns (bool)",
  "function maxLiquidBalance() view returns (uint256)",
  "function liquidCapacity(address) view returns (uint256)",
  "function isSystemAddress(address) view returns (bool)"
];

export const VESTING_ABI = [
  "function committedBalance(address token,address beneficiary) view returns (uint256)",
  "function claimable(address token,address beneficiary,uint256 maxPositions) view returns (uint256)",
  "function positionCount(address token,address beneficiary) view returns (uint256)",
  "function getPosition(address token,address beneficiary,uint256 index) view returns (uint128 amount,uint128 claimed,uint64 start)",
  "function claim(address token,uint256 maxPositions) returns (uint256 released)"
];

export const REWARD_ABI = [
  "function earned(address token,address user) view returns (uint256)",
  "function claim(address token,address payable recipient) returns (uint256 amount)"
];

export const FEE_ABI = [
  "function creatorClaimable(address) view returns (uint256)",
  "function claimCreatorFees(address payable recipient) returns (uint256 amount)"
];

export const GRADUATION_ABI = [
  "function graduate(address token) returns (bytes32 poolId,uint256 positionId)"
];
