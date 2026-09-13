// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

contract MockRewardEngine {
    mapping(address => mapping(address => uint256)) public balance;

    function updateCommitment(address token, address user, uint256 amount) external {
        balance[token][user] = amount;
    }
}
