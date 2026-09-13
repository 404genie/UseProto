// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice Constant-product math for a curve with virtual and real reserves.
/// @dev Buy division rounds the post-trade token reserve up, favoring solvency.
library CurveMath {
    uint256 internal constant BPS = 10_000;

    error ZeroAmount();
    error InvalidFee();
    error InvalidReserves();
    error InsufficientTokenLiquidity();
    error InsufficientQuoteLiquidity();

    function feeOnInput(uint256 amount, uint16 feeBps) internal pure returns (uint256 netAmount, uint256 fee) {
        if (amount == 0) revert ZeroAmount();
        if (feeBps >= BPS) revert InvalidFee();
        fee = amount * feeBps / BPS;
        netAmount = amount - fee;
        if (netAmount == 0) revert ZeroAmount();
    }

    function quoteBuy(
        uint256 realQuote,
        uint256 realToken,
        uint256 virtualQuote,
        uint256 virtualToken,
        uint256 quoteIn,
        uint16 feeBps
    ) internal pure returns (uint256 tokenOut, uint256 fee) {
        (uint256 netQuote, uint256 chargedFee) = feeOnInput(quoteIn, feeBps);
        uint256 x = virtualQuote + realQuote;
        uint256 y = virtualToken + realToken;
        if (x == 0 || y == 0) revert InvalidReserves();

        uint256 k = x * y;
        uint256 newY = _ceilDiv(k, x + netQuote);
        tokenOut = y - newY;
        if (tokenOut == 0 || tokenOut > realToken) revert InsufficientTokenLiquidity();
        fee = chargedFee;
    }

    function quoteSell(
        uint256 realQuote,
        uint256 realToken,
        uint256 virtualQuote,
        uint256 virtualToken,
        uint256 tokenIn,
        uint16 feeBps
    ) internal pure returns (uint256 quoteOut, uint256 fee, uint256 grossQuoteOut) {
        if (tokenIn == 0) revert ZeroAmount();
        if (feeBps >= BPS) revert InvalidFee();
        uint256 x = virtualQuote + realQuote;
        uint256 y = virtualToken + realToken;
        if (x == 0 || y == 0) revert InvalidReserves();

        uint256 k = x * y;
        uint256 newX = _ceilDiv(k, y + tokenIn);
        grossQuoteOut = x - newX;
        if (grossQuoteOut == 0 || grossQuoteOut > realQuote) revert InsufficientQuoteLiquidity();
        fee = grossQuoteOut * feeBps / BPS;
        quoteOut = grossQuoteOut - fee;
        if (quoteOut == 0) revert ZeroAmount();
    }

    function spotPriceWad(uint256 realQuote, uint256 realToken, uint256 virtualQuote, uint256 virtualToken)
        internal
        pure
        returns (uint256)
    {
        uint256 denominator = virtualToken + realToken;
        if (denominator == 0) revert InvalidReserves();
        return (virtualQuote + realQuote) * 1e18 / denominator;
    }

    function _ceilDiv(uint256 a, uint256 b) private pure returns (uint256) {
        return a == 0 ? 0 : (a - 1) / b + 1;
    }
}

