// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {IPositionDescriptor} from "@uniswap/v4-periphery/src/interfaces/IPositionDescriptor.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

/// @notice Minimal metadata implementation for the testnet PositionManager.
contract TestnetPositionDescriptor is IPositionDescriptor {
    IPoolManager public immutable poolManager;
    address public immutable wrappedNative;

    constructor(IPoolManager poolManager_, address wrappedNative_) {
        poolManager = poolManager_;
        wrappedNative = wrappedNative_;
    }

    function nativeCurrencyLabel() external pure returns (string memory) {
        return "ETH";
    }

    function flipRatio(address currency0, address currency1) external pure returns (bool) {
        return currency0 > currency1;
    }

    function currencyRatioPriority(address currency) external view returns (int256) {
        return currency == address(0) || currency == wrappedNative ? int256(1) : int256(0);
    }

    function tokenURI(IPositionManager, uint256 tokenId) external pure returns (string memory) {
        return string.concat("proto-v4-testnet-position:", _toString(tokenId));
    }

    function _toString(uint256 value) private pure returns (string memory) {
        if (value == 0) return "0";
        uint256 digits;
        uint256 cursor = value;
        while (cursor != 0) {
            digits++;
            cursor /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits--;
            buffer[digits] = bytes1(uint8(48 + value % 10));
            value /= 10;
        }
        return string(buffer);
    }
}
