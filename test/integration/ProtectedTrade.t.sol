// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {ProtoToken} from "../../src/ProtoToken.sol";
import {BondingCurve} from "../../src/BondingCurve.sol";
import {ProtoRouter} from "../../src/ProtoRouter.sol";
import {VestingVault} from "../../src/VestingVault.sol";
import {FeeController} from "../../src/FeeController.sol";
import {RewardEngine} from "../../src/RewardEngine.sol";
import {MockProtoCore} from "../mocks/MockProtoCore.sol";

contract ProtectedTradeIntegrationTest is Test {
    MockProtoCore core;
    ProtoToken token;
    BondingCurve curve;
    ProtoRouter router;
    VestingVault vault;
    FeeController fees;
    RewardEngine rewards;
    address alice = makeAddr("alice");
    address creator = makeAddr("creator");
    address treasury = makeAddr("treasury");
    uint256 constant SUPPLY = 1_000_000_000 ether;

    function setUp() public {
        core = new MockProtoCore();
        router = new ProtoRouter(address(this));
        rewards = new RewardEngine(address(this));
        fees = new FeeController(address(router), treasury, address(rewards));
        vault = new VestingVault(address(router), address(rewards));
        rewards.bindCommitmentSource(address(vault));
        rewards.bindFeeController(address(fees));
        router.bindModules(address(vault), address(fees));

        token = new ProtoToken("Proto", "PROTO", SUPPLY, address(core), address(this));
        curve = new BondingCurve(
            address(token), address(router), address(this), SUPPLY, 10 ether, 200_000_000 ether, 100, 100 ether
        );
        core.setSystem(address(token), address(router), true);
        core.setSystem(address(token), address(vault), true);
        core.setSystem(address(token), address(curve), true);
        token.transfer(address(curve), SUPPLY);
        router.registerCurve(address(curve), address(token), creator);
        vm.deal(alice, 100 ether);
    }

    function test_ProtectedBuySplitsLiquidAndCommittedAndAccountsFees() public {
        (uint256 expected, uint256 fee) = curve.quoteBuy(1 ether);
        vm.prank(alice);
        (uint256 total, uint256 liquid, uint256 committed) =
            router.buy{value: 1 ether}(address(curve), alice, expected, block.timestamp);

        assertEq(total, expected);
        assertEq(liquid, token.maxLiquidBalance());
        assertEq(committed, total - liquid);
        assertEq(token.balanceOf(alice), token.maxLiquidBalance());
        assertEq(vault.committedBalance(address(token), alice), committed);
        assertEq(rewards.committedBalance(address(token), alice), committed);
        assertEq(fees.totalFeesRecorded(), fee);
        assertTrue(fees.feeConservationHolds());
        assertTrue(curve.reservesReconcile());
    }

    function test_ProtectedSellUsesOnlyLiquidTokensAndAccountsFee() public {
        vm.startPrank(alice);
        router.buy{value: 1 ether}(address(curve), alice, 0, block.timestamp);
        uint256 tokenIn = 10_000_000 ether;
        token.approve(address(router), tokenIn);
        uint256 beforeBalance = alice.balance;
        uint256 quoteOut = router.sell(address(curve), tokenIn, 0, block.timestamp, payable(alice));
        vm.stopPrank();
        assertEq(alice.balance - beforeBalance, quoteOut);
        assertEq(token.balanceOf(alice), 10_000_000 ether);
        assertTrue(fees.feeConservationHolds());
        assertTrue(curve.reservesReconcile());
    }

    function test_DirectCurveTradeIsRejected() public {
        vm.prank(alice);
        vm.expectRevert(BondingCurve.Unauthorized.selector);
        curve.buy{value: 1 ether}(0, block.timestamp, alice);
    }
}
