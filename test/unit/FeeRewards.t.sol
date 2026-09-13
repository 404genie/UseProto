// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {FeeController} from "../../src/FeeController.sol";
import {RewardEngine} from "../../src/RewardEngine.sol";
import {RejectingCreator} from "../mocks/RejectingCreator.sol";

contract FeeRewardsTest is Test {
    RewardEngine engine;
    FeeController controller;
    address token = makeAddr("token");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address treasury = makeAddr("treasury");
    address payout = makeAddr("payout");

    function setUp() public {
        engine = new RewardEngine(address(this));
        engine.bindCommitmentSource(address(this));
        controller = new FeeController(address(this), treasury, address(engine));
        engine.bindFeeController(address(controller));
        vm.deal(address(this), 1_000 ether);
    }

    function test_FeeSplitIsExactlyConserved() public {
        controller.recordTradingFee{value: 1 ether}(token, alice);
        assertEq(controller.protocolClaimable(), 0.15 ether);
        assertEq(controller.creatorClaimable(alice), 0.35 ether);
        assertEq(engine.totalRewardDeposited(token), 0.5 ether);
        assertTrue(controller.feeConservationHolds());
    }

    function test_ProportionalRewardsUseCommittedIndex() public {
        engine.updateCommitment(token, alice, 75 ether);
        engine.updateCommitment(token, bob, 25 ether);
        controller.recordTradingFee{value: 2 ether}(token, makeAddr("creator"));
        assertEq(engine.earned(token, alice), 0.75 ether);
        assertEq(engine.earned(token, bob), 0.25 ether);
        vm.prank(alice);
        engine.claim(token, payable(alice));
        assertEq(alice.balance, 0.75 ether);
    }

    function test_BalanceChangeSettlesPriorRewards() public {
        engine.updateCommitment(token, alice, 100 ether);
        controller.recordTradingFee{value: 2 ether}(token, makeAddr("creator"));
        engine.updateCommitment(token, bob, 100 ether);
        controller.recordTradingFee{value: 2 ether}(token, makeAddr("creator"));
        assertEq(engine.earned(token, alice), 1.5 ether);
        assertEq(engine.earned(token, bob), 0.5 ether);
    }

    function test_NoHolderRewardsStayEscrowedUntilCommittedBalanceExists() public {
        controller.recordTradingFee{value: 1 ether}(token, alice);
        assertEq(engine.undistributedRewards(token), 0.5 ether);
        engine.updateCommitment(token, alice, 10 ether);
        controller.recordTradingFee{value: 1 ether}(token, alice);
        assertEq(engine.earned(token, alice), 1 ether);
        assertEq(engine.undistributedRewards(token), 0);
    }

    function test_NonPayableCreatorCannotBlockFeeRecordingOrTrades() public {
        RejectingCreator creator = new RejectingCreator();
        controller.recordTradingFee{value: 1 ether}(token, address(creator));
        assertEq(controller.creatorClaimable(address(creator)), 0.35 ether);
        uint256 beforeBalance = payout.balance;
        creator.claimTo(address(controller), payable(payout));
        assertEq(payout.balance - beforeBalance, 0.35 ether);
    }

    function test_OnlyAuthorizedSourcesCanMutateAccounting() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        vm.expectRevert(FeeController.Unauthorized.selector);
        controller.recordTradingFee{value: 1 ether}(token, alice);
        vm.prank(alice);
        vm.expectRevert(RewardEngine.Unauthorized.selector);
        engine.updateCommitment(token, alice, 1 ether);
    }

    function testFuzz_FeeConservation(uint96 rawFee) public {
        uint256 fee = bound(rawFee, 1, 100 ether);
        controller.recordTradingFee{value: fee}(token, alice);
        assertTrue(controller.feeConservationHolds());
        assertEq(controller.totalFeesRecorded(), fee);
    }

    function test_ConstructorAndRecordingRejectInvalidInputs() public {
        vm.expectRevert(FeeController.InvalidInput.selector);
        new FeeController(address(0), treasury, address(engine));
        vm.expectRevert(FeeController.InvalidInput.selector);
        new FeeController(address(this), address(0), address(engine));

        vm.expectRevert(FeeController.InvalidInput.selector);
        controller.recordTradingFee{value: 1 ether}(address(0), alice);
        vm.expectRevert(FeeController.InvalidInput.selector);
        controller.recordTradingFee{value: 1 ether}(token, address(0));
        vm.expectRevert(FeeController.InvalidInput.selector);
        controller.recordTradingFee(token, alice);
    }

    function test_CreatorAndProtocolClaimsArePullBased() public {
        controller.recordTradingFee{value: 1 ether}(token, alice);

        vm.prank(alice);
        vm.expectRevert(FeeController.InvalidInput.selector);
        controller.claimCreatorFees(payable(address(0)));
        vm.prank(alice);
        uint256 creatorBefore = alice.balance;
        controller.claimCreatorFees(payable(alice));
        assertEq(alice.balance - creatorBefore, 0.35 ether);
        vm.prank(alice);
        vm.expectRevert(FeeController.NothingToClaim.selector);
        controller.claimCreatorFees(payable(alice));

        vm.prank(payout);
        vm.expectRevert(FeeController.Unauthorized.selector);
        controller.claimProtocolFees(payable(payout));
        vm.prank(treasury);
        vm.expectRevert(FeeController.InvalidInput.selector);
        controller.claimProtocolFees(payable(address(0)));
        vm.prank(treasury);
        uint256 protocolBefore = payout.balance;
        controller.claimProtocolFees(payable(payout));
        assertEq(payout.balance - protocolBefore, 0.15 ether);
        vm.prank(treasury);
        vm.expectRevert(FeeController.NothingToClaim.selector);
        controller.claimProtocolFees(payable(payout));
    }

    function test_RewardEngineConfigurationAndClaimsRejectInvalidInputs() public {
        RewardEngine fresh = new RewardEngine(address(this));
        vm.expectRevert(RewardEngine.InvalidInput.selector);
        fresh.bindCommitmentSource(address(0));
        vm.expectRevert(RewardEngine.InvalidInput.selector);
        fresh.bindFeeController(address(0));
        fresh.bindCommitmentSource(address(this));
        vm.expectRevert(RewardEngine.AlreadyConfigured.selector);
        fresh.bindCommitmentSource(address(this));
        fresh.bindFeeController(address(this));
        vm.expectRevert(RewardEngine.AlreadyConfigured.selector);
        fresh.bindFeeController(address(this));

        vm.expectRevert(RewardEngine.InvalidInput.selector);
        fresh.depositReward{value: 1 ether}(address(0));
        vm.expectRevert(RewardEngine.InvalidInput.selector);
        fresh.depositReward(address(this));
        vm.expectRevert(RewardEngine.InvalidInput.selector);
        fresh.updateCommitment(address(0), alice, 1);
        vm.expectRevert(RewardEngine.InvalidInput.selector);
        fresh.updateCommitment(token, address(0), 1);
        vm.prank(alice);
        vm.expectRevert(RewardEngine.NothingToClaim.selector);
        fresh.claim(token, payable(alice));
    }
}
