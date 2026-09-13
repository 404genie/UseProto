// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHook} from "@uniswap/v4-periphery/src/utils/BaseHook.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {IProtoCore} from "../interfaces/IProtoCore.sol";

/// @notice Authorization boundary for canonical Proto native/token V4 pools.
contract ProtoHook is BaseHook {
    using PoolIdLibrary for PoolKey;

    IProtoCore public immutable core;
    address public immutable graduationAdapter;
    address public immutable protoV4Router;
    bytes32 public pendingInitialization;

    error UnauthorizedContext();
    error InvalidProtoPool();

    event InitializationAuthorized(bytes32 indexed poolId);

    constructor(IPoolManager poolManager_, IProtoCore core_, address graduationAdapter_, address protoV4Router_)
        BaseHook(poolManager_)
    {
        if (address(core_) == address(0) || graduationAdapter_ == address(0) || protoV4Router_ == address(0)) {
            revert UnauthorizedContext();
        }
        core = core_;
        graduationAdapter = graduationAdapter_;
        protoV4Router = protoV4Router_;
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory permissions) {
        permissions.beforeInitialize = true;
        permissions.beforeSwap = true;
    }

    function authorizeInitialization(bytes32 poolId) external {
        if (msg.sender != graduationAdapter || poolId == bytes32(0)) revert UnauthorizedContext();
        pendingInitialization = poolId;
        emit InitializationAuthorized(poolId);
    }

    function _beforeInitialize(address sender, PoolKey calldata key, uint160) internal override returns (bytes4) {
        address token = _validateShape(key);
        bytes32 poolId = PoolId.unwrap(key.toId());
        if (
            sender == address(0) || pendingInitialization != poolId || core.curveOf(token) == address(0)
                || core.poolOf(token) != bytes32(0)
        ) {
            revert InvalidProtoPool();
        }
        delete pendingInitialization;
        return BaseHook.beforeInitialize.selector;
    }

    function _beforeSwap(address sender, PoolKey calldata key, SwapParams calldata, bytes calldata hookData)
        internal
        view
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        address token = _validateShape(key);
        if (sender != protoV4Router || !core.isGraduated(token) || core.poolOf(token) != PoolId.unwrap(key.toId())) {
            revert UnauthorizedContext();
        }
        if (hookData.length != 64) revert UnauthorizedContext();
        (address trader, address recipient) = abi.decode(hookData, (address, address));
        if (trader == address(0) || recipient == address(0)) revert UnauthorizedContext();
        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    function _validateShape(PoolKey calldata key) private view returns (address token) {
        if (
            Currency.unwrap(key.currency0) != address(0) || Currency.unwrap(key.currency1) == address(0)
                || address(key.hooks) != address(this)
        ) revert InvalidProtoPool();
        token = Currency.unwrap(key.currency1);
    }
}
