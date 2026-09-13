// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IProtoToken is IERC20 {
    function MAX_LIQUID_BPS() external view returns (uint16);
    function maxLiquidBalance() external view returns (uint256);
    function liquidCapacity(address account) external view returns (uint256);
    function isSystemAddress(address account) external view returns (bool);
}

