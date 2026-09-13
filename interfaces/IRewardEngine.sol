// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IRewardEngine {
    function depositReward(address token) external payable;
    function updateCommitment(address token, address user, uint256 newBalance) external;
    function claim(address token, address payable recipient) external returns (uint256 amount);
    function earned(address token, address user) external view returns (uint256);
}

