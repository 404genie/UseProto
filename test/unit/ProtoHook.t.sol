// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {ProtoHook} from "../../src/ProtoHook.sol";
import {MockProtoCore} from "../mocks/MockProtoCore.sol";
import {BaseHook} from "@uniswap/v4-periphery/src/utils/BaseHook.sol";
import {ImmutableState} from "@uniswap/v4-periphery/src/base/ImmutableState.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";

contract TestProtoHook is ProtoHook {
    constructor(IPoolManager manager, MockProtoCore core, address adapter, address router)
        ProtoHook(manager, core, adapter, router)
    {}

    function validateHookAddress(BaseHook) internal pure override {}
}

contract ProtoHookTest is Test {
    using PoolIdLibrary for PoolKey;

    address internal constant POOL_MANAGER = address(0x1000);
    address internal constant ADAPTER = address(0x2000);
    address internal constant ROUTER = address(0x3000);
    address internal constant TOKEN = address(0x4000);
    MockProtoCore internal core;
    TestProtoHook internal hook;
    PoolKey internal key;

    function setUp() public {
        core = new MockProtoCore();
        hook = new TestProtoHook(IPoolManager(POOL_MANAGER), core, ADAPTER, ROUTER);
        key = PoolKey(Currency.wrap(address(0)), Currency.wrap(TOKEN), 3_000, 60, IHooks(address(hook)));
        core.setCurve(TOKEN, address(0x5000));
    }

    function test_OnlyAdapterCanInitializeRegisteredProtoPool() public {
        bytes32 poolId = PoolId.unwrap(key.toId());
        vm.prank(ADAPTER);
        hook.authorizeInitialization(poolId);

        vm.prank(POOL_MANAGER);
        bytes4 result = hook.beforeInitialize(address(0xBEEF), key, 1 << 96);
        assertEq(result, hook.beforeInitialize.selector);
        assertEq(hook.pendingInitialization(), bytes32(0));

        vm.expectRevert(ProtoHook.UnauthorizedContext.selector);
        hook.authorizeInitialization(poolId);

        vm.prank(ADAPTER);
        hook.authorizeInitialization(poolId);
        vm.expectRevert(ProtoHook.InvalidProtoPool.selector);
        vm.prank(POOL_MANAGER);
        hook.beforeInitialize(address(0), key, 1 << 96);
    }

    function test_OnlyRouterCanSwapCanonicalGraduatedPoolWithContext() public {
        bytes32 poolId = PoolId.unwrap(key.toId());
        core.setPool(TOKEN, poolId);
        core.setGraduated(TOKEN, true);
        SwapParams memory params = SwapParams(true, -1 ether, 1);

        vm.prank(POOL_MANAGER);
        (bytes4 result,,) = hook.beforeSwap(ROUTER, key, params, abi.encode(address(1), address(2)));
        assertEq(result, hook.beforeSwap.selector);

        vm.expectRevert(ProtoHook.UnauthorizedContext.selector);
        vm.prank(POOL_MANAGER);
        hook.beforeSwap(address(this), key, params, abi.encode(address(1), address(2)));
    }

    function test_FakeDirectHookCallIsRejected() public {
        SwapParams memory params = SwapParams(true, -1 ether, 1);
        vm.expectRevert(ImmutableState.NotPoolManager.selector);
        hook.beforeSwap(ROUTER, key, params, abi.encode(address(1), address(2)));
    }
}
