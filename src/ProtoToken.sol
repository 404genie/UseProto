// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IProtoCore} from "../interfaces/IProtoCore.sol";

/// @notice Fixed-supply ERC-20 enforcing Proto's address-level 2% liquid cap.
contract ProtoToken is ERC20 {
    uint16 public constant MAX_LIQUID_BPS = 200;
    uint16 private constant BPS = 10_000;

    IProtoCore public immutable protoCore;
    address public immutable initialInventoryHolder;
    uint256 public immutable maxLiquidBalance;

    error InvalidConfiguration();
    error LiquidCapExceeded(address recipient, uint256 resultingBalance, uint256 maximum);

    constructor(
        string memory name_,
        string memory symbol_,
        uint256 supply_,
        address protoCore_,
        address initialInventoryHolder_
    ) ERC20(name_, symbol_) {
        if (supply_ == 0 || protoCore_ == address(0) || initialInventoryHolder_ == address(0)) {
            revert InvalidConfiguration();
        }
        protoCore = IProtoCore(protoCore_);
        initialInventoryHolder = initialInventoryHolder_;
        maxLiquidBalance = supply_ * MAX_LIQUID_BPS / BPS;
        _mint(initialInventoryHolder_, supply_);
    }

    function isSystemAddress(address account) public view returns (bool) {
        return account == initialInventoryHolder || protoCore.isSystemAddress(address(this), account);
    }

    function liquidCapacity(address account) external view returns (uint256) {
        if (isSystemAddress(account)) return type(uint256).max;
        uint256 balance = balanceOf(account);
        return balance >= maxLiquidBalance ? 0 : maxLiquidBalance - balance;
    }

    function _update(address from, address to, uint256 value) internal override {
        if (to != address(0) && to != from && !isSystemAddress(to)) {
            uint256 resultingBalance = balanceOf(to) + value;
            if (resultingBalance > maxLiquidBalance) {
                revert LiquidCapExceeded(to, resultingBalance, maxLiquidBalance);
            }
        }
        super._update(from, to, value);
    }
}

