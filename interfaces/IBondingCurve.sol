// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
interface IBondingCurve {
    function token() external view returns (address);
    function buy(uint256 minOut, uint256 deadline, address recipient) external payable returns (uint256);
    function sell(uint256 tokenIn, uint256 minOut, uint256 deadline, address payable recipient) external returns (uint256);
    function quoteBuy(uint256 quoteIn) external view returns (uint256 tokenOut, uint256 fee);
    function quoteSell(uint256 tokenIn) external view returns (uint256 quoteOut, uint256 fee, uint256 grossQuoteOut);
    function takeAccruedFees() external returns (uint256);
}
