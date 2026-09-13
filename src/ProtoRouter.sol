// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IBondingCurve} from "../interfaces/IBondingCurve.sol";
import {IProtoToken} from "../interfaces/IProtoToken.sol";
import {IVestingVault} from "../interfaces/IVestingVault.sol";
import {IFeeController} from "../interfaces/IFeeController.sol";
import {IProtoCore} from "../interfaces/IProtoCore.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "@uniswap/v4-core/src/types/BalanceDelta.sol";

contract ProtoRouter is ReentrancyGuard, IUnlockCallback {
    using SafeERC20 for IERC20;
    using PoolIdLibrary for PoolKey;

    uint16 public constant V4_TRADING_FEE_BPS = 100;
    uint256 private constant BPS = 10_000;

    struct CurveInfo {
        address token;
        address creator;
        bool registered;
    }
    address public immutable registrar;
    IVestingVault public vestingVault;
    IFeeController public feeController;
    bool public modulesBound;
    IPoolManager public v4PoolManager;
    IHooks public v4Hook;
    bool public v4Bound;
    mapping(address curve => CurveInfo) public curveInfo;
    // A callback is valid only while this router has an unlock in flight.
    // The hash binds it to the exact payload supplied to PoolManager.unlock.
    bytes32 private _activeUnlockContext;

    error Unauthorized();
    error InvalidInput();
    error AlreadyConfigured();
    error UnknownCurve();
    error DeadlineExpired();
    error SlippageExceeded();
    error PartialFill();

    event ProtectedBuy(
        address indexed curve,
        address indexed buyer,
        address indexed recipient,
        uint256 total,
        uint256 liquid,
        uint256 committed
    );
    event ProtectedSell(
        address indexed curve, address indexed seller, address indexed recipient, uint256 tokenIn, uint256 quoteOut
    );
    event ProtectedV4Buy(
        address indexed token,
        address indexed buyer,
        address indexed recipient,
        uint256 quoteIn,
        uint256 total,
        uint256 liquid,
        uint256 committed
    );
    event ProtectedV4Sell(
        address indexed token, address indexed seller, address indexed recipient, uint256 tokenIn, uint256 quoteOut
    );

    struct V4CallbackData {
        PoolKey key;
        address trader;
        address recipient;
        uint256 amountIn;
        uint160 sqrtPriceLimitX96;
        bool zeroForOne;
    }

    constructor(address registrar_) {
        if (registrar_ == address(0)) revert InvalidInput();
        registrar = registrar_;
    }

    receive() external payable {
        if (!curveInfo[msg.sender].registered && msg.sender != address(v4PoolManager)) revert UnknownCurve();
    }

    function bindV4(address poolManager, address hook) external {
        if (msg.sender != registrar) revert Unauthorized();
        if (v4Bound) revert AlreadyConfigured();
        if (poolManager == address(0) || hook == address(0)) revert InvalidInput();
        v4PoolManager = IPoolManager(poolManager);
        v4Hook = IHooks(hook);
        v4Bound = true;
    }

    function buyV4(address token, address recipient, uint256 minTotalOut, uint160 sqrtPriceLimitX96, uint256 deadline)
        external
        payable
        nonReentrant
        returns (uint256 totalOut, uint256 liquid, uint256 committed)
    {
        if (block.timestamp > deadline) revert DeadlineExpired();
        if (!v4Bound || token == address(0) || recipient == address(0) || msg.value == 0) revert InvalidInput();
        uint256 fee = msg.value * V4_TRADING_FEE_BPS / BPS;
        uint256 swapInput = msg.value - fee;
        totalOut = _v4Swap(token, msg.sender, recipient, swapInput, sqrtPriceLimitX96, true);
        if (totalOut < minTotalOut) revert SlippageExceeded();
        (liquid, committed) = _allocate(token, recipient, totalOut);
        if (fee != 0) {
            feeController.recordTradingFee{value: fee}(token, IProtoCore(registrar).creatorOf(token));
        }
        emit ProtectedV4Buy(token, msg.sender, recipient, msg.value, totalOut, liquid, committed);
    }

    function sellV4(
        address token,
        uint256 tokenIn,
        address payable recipient,
        uint256 minQuoteOut,
        uint160 sqrtPriceLimitX96,
        uint256 deadline
    ) external nonReentrant returns (uint256 quoteOut) {
        if (block.timestamp > deadline) revert DeadlineExpired();
        if (!v4Bound || token == address(0) || recipient == address(0) || tokenIn == 0) revert InvalidInput();
        uint256 grossOut = _v4Swap(token, msg.sender, recipient, tokenIn, sqrtPriceLimitX96, false);
        uint256 fee = grossOut * V4_TRADING_FEE_BPS / BPS;
        quoteOut = grossOut - fee;
        if (quoteOut < minQuoteOut) revert SlippageExceeded();
        if (fee != 0) {
            feeController.recordTradingFee{value: fee}(token, IProtoCore(registrar).creatorOf(token));
        }
        (bool ok,) = recipient.call{value: quoteOut}("");
        if (!ok) revert InvalidInput();
        emit ProtectedV4Sell(token, msg.sender, recipient, tokenIn, quoteOut);
    }

    function unlockCallback(bytes calldata rawData) external returns (bytes memory) {
        if (msg.sender != address(v4PoolManager) || _activeUnlockContext != keccak256(rawData)) {
            revert Unauthorized();
        }
        // Consume the context before crossing another external boundary. This
        // prevents a nested callback from replaying the same unlock payload.
        delete _activeUnlockContext;
        V4CallbackData memory data = abi.decode(rawData, (V4CallbackData));
        SwapParams memory params = SwapParams(data.zeroForOne, -int256(data.amountIn), data.sqrtPriceLimitX96);
        BalanceDelta delta = v4PoolManager.swap(data.key, params, abi.encode(data.trader, data.recipient));
        int128 inputDelta = data.zeroForOne ? delta.amount0() : delta.amount1();
        int128 outputDelta = data.zeroForOne ? delta.amount1() : delta.amount0();
        if (inputDelta >= 0 || outputDelta <= 0 || uint256(-int256(inputDelta)) != data.amountIn) revert PartialFill();

        Currency input = data.zeroForOne ? data.key.currency0 : data.key.currency1;
        Currency output = data.zeroForOne ? data.key.currency1 : data.key.currency0;
        if (Currency.unwrap(input) == address(0)) {
            v4PoolManager.settle{value: data.amountIn}();
        } else {
            v4PoolManager.sync(input);
            IERC20(Currency.unwrap(input)).safeTransferFrom(data.trader, address(v4PoolManager), data.amountIn);
            v4PoolManager.settle();
        }
        v4PoolManager.take(output, address(this), uint256(int256(outputDelta)));
        return abi.encode(uint256(int256(outputDelta)));
    }

    function bindModules(address vault, address fees) external {
        if (msg.sender != registrar) revert Unauthorized();
        if (modulesBound) revert AlreadyConfigured();
        if (vault == address(0) || fees == address(0)) revert InvalidInput();
        vestingVault = IVestingVault(vault);
        feeController = IFeeController(fees);
        modulesBound = true;
    }

    function registerCurve(address curve, address token, address creator) external {
        if (msg.sender != registrar) revert Unauthorized();
        if (!modulesBound || curve == address(0) || token == address(0) || creator == address(0)) {
            revert InvalidInput();
        }
        if (curveInfo[curve].registered || IBondingCurve(curve).token() != token) revert InvalidInput();
        curveInfo[curve] = CurveInfo(token, creator, true);
    }

    function buy(address curve, address recipient, uint256 minTotalOut, uint256 deadline)
        external
        payable
        nonReentrant
        returns (uint256 totalOut, uint256 liquid, uint256 committed)
    {
        if (recipient == address(0) || msg.value == 0) revert InvalidInput();
        CurveInfo memory info = _curve(curve);
        totalOut = IBondingCurve(curve).buy{value: msg.value}(minTotalOut, deadline, address(this));
        uint256 capacity = IProtoToken(info.token).liquidCapacity(recipient);
        liquid = totalOut < capacity ? totalOut : capacity;
        committed = totalOut - liquid;
        if (liquid != 0) IERC20(info.token).safeTransfer(recipient, liquid);
        if (committed != 0) {
            IERC20(info.token).forceApprove(address(vestingVault), committed);
            vestingVault.commit(info.token, recipient, committed);
        }
        _forwardFee(curve, info);
        emit ProtectedBuy(curve, msg.sender, recipient, totalOut, liquid, committed);
    }

    function sell(address curve, uint256 tokenIn, uint256 minQuoteOut, uint256 deadline, address payable recipient)
        external
        nonReentrant
        returns (uint256 quoteOut)
    {
        if (recipient == address(0) || tokenIn == 0) revert InvalidInput();
        CurveInfo memory info = _curve(curve);
        IERC20(info.token).safeTransferFrom(msg.sender, address(this), tokenIn);
        IERC20(info.token).forceApprove(curve, tokenIn);
        quoteOut = IBondingCurve(curve).sell(tokenIn, minQuoteOut, deadline, recipient);
        _forwardFee(curve, info);
        emit ProtectedSell(curve, msg.sender, recipient, tokenIn, quoteOut);
    }

    function _forwardFee(address curve, CurveInfo memory info) private {
        uint256 fee = IBondingCurve(curve).takeAccruedFees();
        if (fee != 0) feeController.recordTradingFee{value: fee}(info.token, info.creator);
    }

    function _v4Swap(
        address token,
        address trader,
        address recipient,
        uint256 amountIn,
        uint160 sqrtPriceLimitX96,
        bool zeroForOne
    ) private returns (uint256 amountOut) {
        if (amountIn == 0 || amountIn > uint256(uint128(type(int128).max))) {
            revert InvalidInput();
        }
        IProtoCore core = IProtoCore(registrar);
        if (!core.isGraduated(token)) revert InvalidInput();
        PoolKey memory key = PoolKey(Currency.wrap(address(0)), Currency.wrap(token), 3_000, 60, v4Hook);
        if (core.poolOf(token) != PoolId.unwrap(key.toId())) revert InvalidInput();
        bytes memory callbackData =
            abi.encode(V4CallbackData(key, trader, recipient, amountIn, sqrtPriceLimitX96, zeroForOne));
        _activeUnlockContext = keccak256(callbackData);
        bytes memory result = v4PoolManager.unlock(callbackData);
        delete _activeUnlockContext;
        amountOut = abi.decode(result, (uint256));
    }

    function _allocate(address token, address recipient, uint256 totalOut)
        private
        returns (uint256 liquid, uint256 committed)
    {
        uint256 capacity = IProtoToken(token).liquidCapacity(recipient);
        liquid = totalOut < capacity ? totalOut : capacity;
        committed = totalOut - liquid;
        if (liquid != 0) IERC20(token).safeTransfer(recipient, liquid);
        if (committed != 0) {
            IERC20(token).forceApprove(address(vestingVault), committed);
            vestingVault.commit(token, recipient, committed);
        }
    }

    function _curve(address curve) private view returns (CurveInfo memory info) {
        info = curveInfo[curve];
        if (!info.registered) revert UnknownCurve();
    }
}
