// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ILaunchPriceOracle} from "../interfaces/ILaunchPriceOracle.sol";

/// @notice Explicit native/USD reference used only when a token is launched.
/// @dev ProtoFactory snapshots this value into the curve. Trading never reads it.
contract LaunchPriceOracle is ILaunchPriceOracle {
    address public immutable owner;
    uint256 public priceUsd8;
    uint256 public updatedAt;

    error Unauthorized();
    error InvalidPrice();

    event PriceUpdated(uint256 indexed priceUsd8, uint256 indexed updatedAt);

    constructor(address owner_, uint256 initialPriceUsd8_) {
        if (owner_ == address(0) || initialPriceUsd8_ == 0) revert InvalidPrice();
        owner = owner_;
        _update(initialPriceUsd8_);
    }

    /// @notice Refresh the launch reference. The caller should be a multisig in production.
    function setPrice(uint256 newPriceUsd8) external {
        if (msg.sender != owner) revert Unauthorized();
        if (newPriceUsd8 == 0) revert InvalidPrice();
        _update(newPriceUsd8);
    }

    function latestPrice() external view returns (uint256, uint256) {
        return (priceUsd8, updatedAt);
    }

    function _update(uint256 newPriceUsd8) private {
        priceUsd8 = newPriceUsd8;
        updatedAt = block.timestamp;
        emit PriceUpdated(newPriceUsd8, block.timestamp);
    }
}
