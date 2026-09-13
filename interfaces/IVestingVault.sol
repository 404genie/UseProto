// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IVestingVault {
    function commit(address token, address beneficiary, uint256 amount) external;
    function claim(address token, uint256 maxPositions) external returns (uint256 released);
    function committedBalance(address token, address beneficiary) external view returns (uint256);
    function claimable(address token, address beneficiary, uint256 maxPositions) external view returns (uint256);
}

