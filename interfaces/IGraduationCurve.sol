// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
interface IGraduationCurve {
    function realQuoteReserve() external view returns (uint256);
    function graduationThreshold() external view returns (uint256);
    function releaseForGraduation(address recipient) external returns (uint256 tokenAmount, uint256 quoteAmount);
}
