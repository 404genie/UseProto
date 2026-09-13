// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IGraduationAdapter} from "../interfaces/IGraduationAdapter.sol";
import {IGraduationCurve} from "../interfaces/IGraduationCurve.sol";
import {LiquidityLocker} from "./LiquidityLocker.sol";

interface IGraduationCore {
    function beginGraduation(address token) external returns (address curve);
    function finalizeGraduation(address token, bytes32 poolId, uint256 positionId) external;
}

contract GraduationManager is ReentrancyGuard {
    using SafeERC20 for IERC20;
    IGraduationCore public immutable core;
    address public immutable configurator;
    IGraduationAdapter public adapter;
    LiquidityLocker public locker;

    error Unauthorized();
    error AlreadyConfigured();
    error ThresholdNotReached();
    error AssetMismatch();

    event Graduated(
        address indexed token,
        address indexed curve,
        bytes32 indexed poolId,
        uint256 positionId,
        uint256 tokens,
        uint256 quote
    );

    constructor(address core_, address configurator_) {
        if (core_ == address(0) || configurator_ == address(0)) revert AssetMismatch();
        core = IGraduationCore(core_);
        configurator = configurator_;
    }

    function bindModules(address adapter_, address locker_) external {
        if (msg.sender != configurator) revert Unauthorized();
        if (address(adapter) != address(0)) revert AlreadyConfigured();
        if (adapter_ == address(0) || locker_ == address(0)) revert AssetMismatch();
        adapter = IGraduationAdapter(adapter_);
        locker = LiquidityLocker(payable(locker_));
    }

    function graduate(address token) external nonReentrant returns (bytes32 poolId, uint256 positionId) {
        if (address(adapter) == address(0)) revert AssetMismatch();
        address curve = core.beginGraduation(token);
        IGraduationCurve source = IGraduationCurve(curve);
        if (source.realQuoteReserve() < source.graduationThreshold()) revert ThresholdNotReached();
        (uint256 tokenAmount, uint256 quoteAmount) = source.releaseForGraduation(address(this));
        if (IERC20(token).balanceOf(address(this)) < tokenAmount || address(this).balance < quoteAmount) {
            revert AssetMismatch();
        }
        IERC20(token).forceApprove(address(adapter), tokenAmount);
        (poolId, positionId) = adapter.initializeAndMint{value: quoteAmount}(token, tokenAmount, address(locker));
        locker.registerPosition(token, positionId);
        core.finalizeGraduation(token, poolId, positionId);
        emit Graduated(token, curve, poolId, positionId, tokenAmount, quoteAmount);
    }

    receive() external payable {}
}
