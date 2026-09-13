// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
interface ILaunchPriceOracle { function latestPrice() external view returns (uint256 priceUsd8, uint256 updatedAt); }
