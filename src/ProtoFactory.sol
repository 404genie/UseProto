// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ProtoToken} from "./ProtoToken.sol";
import {BondingCurve} from "./BondingCurve.sol";
import {ProtoCore} from "./ProtoCore.sol";
import {ILaunchPriceOracle} from "../interfaces/ILaunchPriceOracle.sol";

contract ProtoFactory {
    using SafeERC20 for ProtoToken;
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 ether;
    uint16 public constant VIRTUAL_TOKEN_RATIO_BPS = 250;
    uint16 public constant TRADING_FEE_BPS = 100;
    uint256 public constant GRADUATION_THRESHOLD = 5 ether;
    uint256 public constant TARGET_MARKET_CAP_USD8 = 2_000 * 1e8;
    uint256 public constant MAX_PRICE_AGE = 1 hours;

    ProtoCore public immutable core;
    address public immutable router;
    ILaunchPriceOracle public immutable priceOracle;
    address public immutable vestingVault;
    address public immutable rewardEngine;
    address public immutable graduationManager;
    uint256 public launchCount;

    error InvalidInput();
    error StalePrice();
    event TokenLaunched(
        address indexed token,
        address indexed curve,
        address indexed creator,
        string name,
        string symbol,
        uint256 priceUsd8,
        uint256 virtualQuoteReserve
    );

    constructor(
        address core_,
        address router_,
        address oracle_,
        address vault_,
        address rewards_,
        address graduationManager_
    ) {
        if (
            core_ == address(0) || router_ == address(0) || oracle_ == address(0) || vault_ == address(0)
                || rewards_ == address(0) || graduationManager_ == address(0)
        ) revert InvalidInput();
        core = ProtoCore(core_);
        router = router_;
        priceOracle = ILaunchPriceOracle(oracle_);
        vestingVault = vault_;
        rewardEngine = rewards_;
        graduationManager = graduationManager_;
    }

    function createToken(string calldata name, string calldata symbol, string calldata metadataURI)
        external
        returns (address tokenAddress, address curveAddress)
    {
        if (
            bytes(name).length == 0 || bytes(name).length > 64 || bytes(symbol).length == 0 || bytes(symbol).length > 16
                || bytes(metadataURI).length > 512
        ) revert InvalidInput();
        (uint256 priceUsd8, uint256 updatedAt) = priceOracle.latestPrice();
        if (priceUsd8 == 0 || updatedAt > block.timestamp || block.timestamp - updatedAt > MAX_PRICE_AGE) {
            revert StalePrice();
        }
        uint256 virtualToken = TOTAL_SUPPLY * VIRTUAL_TOKEN_RATIO_BPS / 10_000;
        uint256 virtualQuote =
            Math.mulDiv(TARGET_MARKET_CAP_USD8, TOTAL_SUPPLY + virtualToken, priceUsd8 * (TOTAL_SUPPLY / 1 ether));
        ProtoToken token = new ProtoToken(name, symbol, TOTAL_SUPPLY, address(core), address(this));
        BondingCurve curve = new BondingCurve(
            address(token),
            router,
            graduationManager,
            TOTAL_SUPPLY,
            virtualQuote,
            virtualToken,
            TRADING_FEE_BPS,
            GRADUATION_THRESHOLD
        );
        core.registerLaunch(address(token), msg.sender, address(curve), priceUsd8, virtualQuote, metadataURI);
        core.setSystemAddress(address(token), vestingVault, true);
        core.setSystemAddress(address(token), rewardEngine, true);
        token.safeTransfer(address(curve), TOTAL_SUPPLY);
        launchCount++;
        emit TokenLaunched(address(token), address(curve), msg.sender, name, symbol, priceUsd8, virtualQuote);
        return (address(token), address(curve));
    }
}
