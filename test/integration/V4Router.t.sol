// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {ProtoRouter} from "../../src/ProtoRouter.sol";
import {ProtoToken} from "../../src/ProtoToken.sol";
import {RewardEngine} from "../../src/RewardEngine.sol";
import {FeeController} from "../../src/FeeController.sol";
import {VestingVault} from "../../src/VestingVault.sol";
import {MockProtoCore} from "../mocks/MockProtoCore.sol";
import {MockV4PoolManager} from "../mocks/MockV4PoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";

contract V4RouterIntegrationTest is Test {
    using PoolIdLibrary for PoolKey;

    MockProtoCore internal core;
    MockV4PoolManager internal manager;
    ProtoRouter internal router;
    ProtoToken internal token;
    RewardEngine internal rewards;
    FeeController internal fees;
    VestingVault internal vault;
    address internal constant HOOK = address(0x7777);
    address internal user = makeAddr("user");

    function setUp() public {
        core = new MockProtoCore();
        manager = new MockV4PoolManager();
        router = new ProtoRouter(address(core));
        rewards = new RewardEngine(address(this));
        fees = new FeeController(address(router), address(this), address(rewards));
        vault = new VestingVault(address(router), address(rewards));
        rewards.bindCommitmentSource(address(vault));
        rewards.bindFeeController(address(fees));
        vm.prank(address(core));
        router.bindModules(address(vault), address(fees));
        vm.prank(address(core));
        router.bindV4(address(manager), HOOK);

        token = new ProtoToken("Proto V4", "P4", 1_000_000_000 ether, address(core), address(router));
        core.setSystem(address(token), address(manager), true);
        core.setSystem(address(token), address(router), true);
        core.setSystem(address(token), address(vault), true);
        core.setSystem(address(token), address(rewards), true);
        core.setSystem(address(token), address(fees), true);
        vm.prank(address(router));
        token.transfer(address(manager), 500_000_000 ether);
        PoolKey memory key = PoolKey(Currency.wrap(address(0)), Currency.wrap(address(token)), 3_000, 60, IHooks(HOOK));
        core.setPool(address(token), PoolId.unwrap(key.toId()));
        core.setCurve(address(token), address(1));
        core.setCreator(address(token), address(this));
        core.setGraduated(address(token), true);
        vm.deal(address(manager), 100 ether);
        vm.deal(user, 10 ether);
    }

    function test_BuyV4SplitsLiquidAndVestingAndChargesFee() public {
        vm.prank(user);
        (uint256 total, uint256 liquid, uint256 committed) =
            router.buyV4{value: 1 ether}(address(token), user, 1 ether, 0, block.timestamp + 1);

        assertEq(total, 39_600_000 ether); // 0.99 ETH net input × 40,000,000
        assertEq(liquid, token.maxLiquidBalance());
        assertEq(committed, total - liquid);
        assertEq(token.balanceOf(user), liquid);
        assertEq(vault.committedBalance(address(token), user), committed);
        assertEq(fees.totalFeesRecorded(), 0.01 ether);
    }

    function test_SellV4ChargesFeeAndPaysRecipient() public {
        vm.prank(user);
        router.buyV4{value: 1 ether}(address(token), user, 1 ether, 0, block.timestamp + 1);
        manager.setOutputMultiplier(2);
        uint256 beforeBalance = user.balance;
        vm.startPrank(user);
        token.approve(address(router), 1 ether);
        uint256 quoteOut = router.sellV4(address(token), 1 ether, payable(user), 1 ether, 0, block.timestamp + 1);
        vm.stopPrank();

        assertEq(quoteOut, 1.98 ether);
        assertEq(user.balance, beforeBalance + quoteOut);
        assertEq(fees.totalFeesRecorded(), 0.03 ether); // buy fee + sell fee
    }

    function test_DeadlineAndSlippageProtectV4Trades() public {
        vm.warp(100);
        vm.prank(user);
        vm.expectRevert(ProtoRouter.DeadlineExpired.selector);
        router.buyV4{value: 1 ether}(address(token), user, 0, 0, 99);

        vm.prank(user);
        vm.expectRevert(ProtoRouter.SlippageExceeded.selector);
        router.buyV4{value: 1 ether}(address(token), user, 40_000_000 ether, 0, block.timestamp + 1);
    }

    function test_UnlockCallbackRequiresRouterInitiatedContext() public {
        PoolKey memory key = PoolKey(Currency.wrap(address(0)), Currency.wrap(address(token)), 3_000, 60, IHooks(HOOK));
        bytes memory rawData = abi.encode(key, user, user, 1 ether, uint160(0), true);

        vm.expectRevert(ProtoRouter.Unauthorized.selector);
        manager.unlockFor(address(router), rawData);
    }
}
