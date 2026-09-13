// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IFeeController {
    function recordTradingFee(address token, address creator) external payable;
    function claimCreatorFees(address payable recipient) external returns (uint256 amount);
    function claimProtocolFees(address payable recipient) external returns (uint256 amount);
}

