// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

contract MockLaunchPriceOracle {
    uint256 public price = 3_000e8;
    uint256 public updatedAt = block.timestamp;

    function latestPrice() external view returns (uint256, uint256) {
        return (price, updatedAt);
    }

    function set(uint256 p, uint256 t) external {
        price = p;
        updatedAt = t;
    }
}
