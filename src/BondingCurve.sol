// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {CurveMath} from "./libraries/CurveMath.sol";

interface IERC20Inventory {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

/// @notice Milestone-one native-quote bonding curve.
/// @dev Parameters are provisional until economic simulation freezes them.
contract BondingCurve {
    enum State {
        ACTIVE,
        GRADUATING,
        GRADUATED
    }

    IERC20Inventory public immutable token;
    address public immutable executor;
    address public immutable graduationManager;
    uint256 public immutable virtualQuoteReserve;
    uint256 public immutable virtualTokenReserve;
    uint256 public immutable graduationThreshold;
    uint16 public immutable tradingFeeBps;

    uint256 public realQuoteReserve;
    uint256 public realTokenReserve;
    uint256 public accruedFees;
    State public state;

    uint256 private _locked = 1;

    error DeadlineExpired();
    error SlippageExceeded();
    error CurveNotActive();
    error InvalidConfiguration();
    error TransferFailed();
    error NativeTransferFailed();
    error Reentrancy();
    error InventoryMismatch();
    error Unauthorized();

    event Bought(address indexed buyer, address indexed recipient, uint256 quoteIn, uint256 tokenOut, uint256 fee);
    event Sold(address indexed seller, address indexed recipient, uint256 tokenIn, uint256 quoteOut, uint256 fee);
    event GraduationThresholdReached(uint256 realQuoteReserve);

    modifier nonReentrant() {
        if (_locked != 1) revert Reentrancy();
        _locked = 2;
        _;
        _locked = 1;
    }

    modifier active() {
        if (state != State.ACTIVE) revert CurveNotActive();
        _;
    }

    constructor(
        address token_,
        address executor_,
        address graduationManager_,
        uint256 initialRealTokenReserve,
        uint256 virtualQuoteReserve_,
        uint256 virtualTokenReserve_,
        uint16 tradingFeeBps_,
        uint256 graduationThreshold_
    ) {
        if (
            token_ == address(0) || executor_ == address(0) || graduationManager_ == address(0)
                || initialRealTokenReserve == 0 || virtualQuoteReserve_ == 0 || virtualTokenReserve_ == 0
                || tradingFeeBps_ >= 10_000 || graduationThreshold_ == 0
        ) revert InvalidConfiguration();
        token = IERC20Inventory(token_);
        executor = executor_;
        graduationManager = graduationManager_;
        realTokenReserve = initialRealTokenReserve;
        virtualQuoteReserve = virtualQuoteReserve_;
        virtualTokenReserve = virtualTokenReserve_;
        tradingFeeBps = tradingFeeBps_;
        graduationThreshold = graduationThreshold_;
    }

    function quoteBuy(uint256 quoteIn) public view returns (uint256 tokenOut, uint256 fee) {
        return CurveMath.quoteBuy(
            realQuoteReserve, realTokenReserve, virtualQuoteReserve, virtualTokenReserve, quoteIn, tradingFeeBps
        );
    }

    function quoteSell(uint256 tokenIn) public view returns (uint256 quoteOut, uint256 fee, uint256 grossQuoteOut) {
        return CurveMath.quoteSell(
            realQuoteReserve, realTokenReserve, virtualQuoteReserve, virtualTokenReserve, tokenIn, tradingFeeBps
        );
    }

    function spotPriceWad() external view returns (uint256) {
        return CurveMath.spotPriceWad(realQuoteReserve, realTokenReserve, virtualQuoteReserve, virtualTokenReserve);
    }

    function buy(uint256 amountOutMinimum, uint256 deadline, address recipient)
        external
        payable
        nonReentrant
        active
        returns (uint256 tokenOut)
    {
        if (msg.sender != executor) revert Unauthorized();
        if (block.timestamp > deadline) revert DeadlineExpired();
        uint256 fee;
        (tokenOut, fee) = quoteBuy(msg.value);
        if (tokenOut < amountOutMinimum) revert SlippageExceeded();

        realQuoteReserve += msg.value - fee;
        realTokenReserve -= tokenOut;
        accruedFees += fee;
        if (!token.transfer(recipient, tokenOut)) revert TransferFailed();
        _assertInventory();
        emit Bought(msg.sender, recipient, msg.value, tokenOut, fee);
        if (realQuoteReserve >= graduationThreshold) emit GraduationThresholdReached(realQuoteReserve);
    }

    function sell(uint256 tokenIn, uint256 amountOutMinimum, uint256 deadline, address payable recipient)
        external
        nonReentrant
        active
        returns (uint256 quoteOut)
    {
        if (msg.sender != executor) revert Unauthorized();
        if (block.timestamp > deadline) revert DeadlineExpired();
        uint256 fee;
        uint256 grossQuoteOut;
        (quoteOut, fee, grossQuoteOut) = quoteSell(tokenIn);
        if (quoteOut < amountOutMinimum) revert SlippageExceeded();

        realQuoteReserve -= grossQuoteOut;
        realTokenReserve += tokenIn;
        accruedFees += fee;
        if (!token.transferFrom(msg.sender, address(this), tokenIn)) revert TransferFailed();
        (bool ok,) = recipient.call{value: quoteOut}("");
        if (!ok) revert NativeTransferFailed();
        _assertInventory();
        emit Sold(msg.sender, recipient, tokenIn, quoteOut, fee);
    }

    function takeAccruedFees() external nonReentrant returns (uint256 amount) {
        if (msg.sender != executor) revert Unauthorized();
        amount = accruedFees;
        accruedFees = 0;
        (bool ok,) = payable(executor).call{value: amount}("");
        if (!ok) revert NativeTransferFailed();
    }

    function releaseForGraduation(address recipient)
        external
        nonReentrant
        active
        returns (uint256 tokenAmount, uint256 quoteAmount)
    {
        if (msg.sender != graduationManager) revert Unauthorized();
        if (realQuoteReserve < graduationThreshold || accruedFees != 0 || recipient == address(0)) {
            revert InvalidConfiguration();
        }
        state = State.GRADUATING;
        tokenAmount = realTokenReserve;
        quoteAmount = realQuoteReserve;
        realTokenReserve = 0;
        realQuoteReserve = 0;
        if (!token.transfer(recipient, tokenAmount)) revert TransferFailed();
        (bool ok,) = payable(recipient).call{value: quoteAmount}("");
        if (!ok) revert NativeTransferFailed();
    }

    function reservesReconcile() external view returns (bool) {
        return
            token.balanceOf(address(this)) >= realTokenReserve
                && address(this).balance >= realQuoteReserve + accruedFees;
    }

    function _assertInventory() private view {
        // Forced ETH and unsolicited token transfers must not brick trading.
        // Surplus is deliberately excluded from pricing/accounted reserves.
        if (token.balanceOf(address(this)) < realTokenReserve || address(this).balance < realQuoteReserve + accruedFees)
        {
            revert InventoryMismatch();
        }
    }
}
