// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {LiquidityAmounts} from "@uniswap/v4-periphery/src/libraries/LiquidityAmounts.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {IGraduationAdapter} from "../interfaces/IGraduationAdapter.sol";

interface IInitializationAuthorizer {
    function authorizeInitialization(bytes32 poolId) external;
}

/// @notice Concrete native/token Uniswap V4 graduation adapter.
contract V4GraduationAdapter is IGraduationAdapter {
    using SafeERC20 for IERC20;
    using PoolIdLibrary for PoolKey;

    int24 public constant TICK_SPACING = 60;
    uint24 public constant LP_FEE = 3_000;
    address public immutable configurator;
    address public graduationManager;
    IPositionManager public immutable positionManager;
    IAllowanceTransfer public immutable permit2;
    IHooks public hook;

    error Unauthorized();
    error AlreadyConfigured();
    error InvalidInput();
    error AmountTooLarge();

    constructor(address configurator_, address positionManager_, address permit2_) {
        if (configurator_ == address(0) || positionManager_ == address(0) || permit2_ == address(0)) {
            revert InvalidInput();
        }
        configurator = configurator_;
        positionManager = IPositionManager(positionManager_);
        permit2 = IAllowanceTransfer(permit2_);
    }

    function bindGraduation(address manager_, address hook_) external {
        if (msg.sender != configurator) revert Unauthorized();
        if (graduationManager != address(0)) revert AlreadyConfigured();
        if (manager_ == address(0) || hook_ == address(0)) revert InvalidInput();
        graduationManager = manager_;
        hook = IHooks(hook_);
    }

    function initializeAndMint(address token, uint256 tokenAmount, address locker)
        external
        payable
        returns (bytes32 poolId, uint256 positionId)
    {
        if (msg.sender != graduationManager || address(hook) == address(0)) revert Unauthorized();
        if (token == address(0) || locker == address(0) || tokenAmount == 0 || msg.value == 0) revert InvalidInput();
        if (tokenAmount > type(uint128).max || msg.value > type(uint128).max) revert AmountTooLarge();

        IERC20(token).safeTransferFrom(msg.sender, address(this), tokenAmount);
        PoolKey memory key = PoolKey(Currency.wrap(address(0)), Currency.wrap(token), LP_FEE, TICK_SPACING, hook);
        poolId = PoolId.unwrap(key.toId());
        IInitializationAuthorizer(address(hook)).authorizeInitialization(poolId);
        uint160 sqrtPriceX96 = uint160(Math.sqrt(Math.mulDiv(tokenAmount, uint256(1) << 192, msg.value)));
        positionManager.initializePool(key, sqrtPriceX96);

        int24 tickLower = (TickMath.MIN_TICK / TICK_SPACING) * TICK_SPACING;
        int24 tickUpper = (TickMath.MAX_TICK / TICK_SPACING) * TICK_SPACING;
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            msg.value,
            tokenAmount
        );
        if (liquidity == 0) revert InvalidInput();

        IERC20(token).forceApprove(address(permit2), tokenAmount);
        permit2.approve(token, address(positionManager), uint160(tokenAmount), type(uint48).max);
        positionId = positionManager.nextTokenId();
        bytes memory actions =
            abi.encodePacked(uint8(Actions.MINT_POSITION), uint8(Actions.SETTLE_PAIR), uint8(Actions.SWEEP));
        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            key, tickLower, tickUpper, liquidity, uint128(msg.value), uint128(tokenAmount), locker, bytes("")
        );
        params[1] = abi.encode(key.currency0, key.currency1);
        params[2] = abi.encode(key.currency0, locker);
        positionManager.modifyLiquidities{value: msg.value}(abi.encode(actions, params), block.timestamp);

        // Full-range integer math may leave token dust. It is permanently locked
        // with the position instead of remaining recoverable by an administrator.
        uint256 tokenDust = IERC20(token).balanceOf(address(this));
        if (tokenDust != 0) IERC20(token).safeTransfer(locker, tokenDust);
    }

    receive() external payable {}
}
