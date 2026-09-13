// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta, toBalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";

/// @dev Minimal callback-compatible manager used to test ProtoRouter settlement paths.
contract MockV4PoolManager {
    uint256 public outputMultiplier = 40_000_000;

    function setOutputMultiplier(uint256 value) external {
        outputMultiplier = value;
    }

    function unlock(bytes calldata data) external returns (bytes memory) {
        return IUnlockCallback(msg.sender).unlockCallback(data);
    }

    /// @dev Test helper that simulates the manager invoking a callback without
    /// a router-initiated unlock context.
    function unlockFor(address callback, bytes calldata data) external returns (bytes memory) {
        return IUnlockCallback(callback).unlockCallback(data);
    }

    function swap(PoolKey memory, SwapParams memory params, bytes calldata) external view returns (BalanceDelta) {
        uint128 input = uint128(uint256(-params.amountSpecified));
        uint128 output = input * uint128(outputMultiplier);
        if (params.zeroForOne) return toBalanceDelta(-int128(input), int128(output));
        return toBalanceDelta(int128(output), -int128(input));
    }

    function sync(Currency) external {}

    function settle() external payable returns (uint256) {
        return msg.value;
    }

    function take(Currency currency, address to, uint256 amount) external {
        if (Currency.unwrap(currency) == address(0)) {
            (bool ok,) = payable(to).call{value: amount}("");
            require(ok);
        } else {
            require(IERC20(Currency.unwrap(currency)).transfer(to, amount));
        }
    }

    receive() external payable {}
}
