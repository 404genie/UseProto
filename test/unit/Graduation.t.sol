// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import {Test} from "forge-std/Test.sol";
import {GraduationManager} from "../../src/GraduationManager.sol";
import {LiquidityLocker} from "../../src/LiquidityLocker.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockGraduationCore, MockGraduationCurve, MockGraduationAdapter} from "../mocks/MockGraduation.sol";

contract GraduationTest is Test {
    MockERC20 token;
    MockGraduationCurve curve;
    MockGraduationCore core;
    MockGraduationAdapter adapter;
    LiquidityLocker locker;
    GraduationManager manager;

    function setUp() public {
        token = new MockERC20();
        curve = new MockGraduationCurve(address(token), 5 ether);
        core = new MockGraduationCore(address(curve));
        adapter = new MockGraduationAdapter();
        locker = new LiquidityLocker(address(this), address(adapter));
        manager = new GraduationManager(address(core), address(this));
        locker.bindGraduationManager(address(manager));
        manager.bindModules(address(adapter), address(locker));
        core.setManager(address(manager));
        token.mint(address(curve), 100_000_000 ether);
        vm.deal(address(this), 10 ether);
        curve.configure{value: 5 ether}(address(manager));
    }

    function test_GraduationIsAtomicAndLocksPosition() public {
        (bytes32 pool, uint256 id) = manager.graduate(address(token));
        assertEq(core.state(), 3);
        assertEq(core.poolId(), pool);
        assertEq(locker.tokenOfPosition(id), address(token));
        assertEq(token.balanceOf(address(adapter)), 100_000_000 ether);
        assertEq(address(adapter).balance, 5 ether);
    }

    function test_AdapterFailureRollsBackEverything() public {
        adapter.setFail(true);
        vm.expectRevert();
        manager.graduate(address(token));
        assertEq(core.state(), 1);
        assertEq(curve.realQuoteReserve(), 5 ether);
        assertEq(token.balanceOf(address(curve)), 100_000_000 ether);
    }

    function test_LockerHasNoWithdrawalSurface() public view {
        assertEq(locker.graduationManager(), address(manager));
    }

    function test_DeploymentBindingsCannotBeReconfigured() public {
        vm.expectRevert(GraduationManager.AlreadyConfigured.selector);
        manager.bindModules(address(adapter), address(locker));

        vm.expectRevert(LiquidityLocker.AlreadyConfigured.selector);
        locker.bindGraduationManager(address(manager));
    }

    function test_OnlyConfiguratorCanBindDeploymentModules() public {
        GraduationManager freshManager = new GraduationManager(address(core), address(this));
        LiquidityLocker freshLocker = new LiquidityLocker(address(this), address(adapter));
        address stranger = makeAddr("stranger");

        vm.prank(stranger);
        vm.expectRevert(GraduationManager.Unauthorized.selector);
        freshManager.bindModules(address(adapter), address(freshLocker));

        vm.prank(stranger);
        vm.expectRevert(LiquidityLocker.Unauthorized.selector);
        freshLocker.bindGraduationManager(address(freshManager));
    }

    function test_ThresholdFailureRollsBackLifecycle() public {
        curve.configure{value: 1 ether}(address(manager));
        vm.expectRevert(GraduationManager.ThresholdNotReached.selector);
        manager.graduate(address(token));
        assertEq(core.state(), 1);
        assertEq(curve.realQuoteReserve(), 1 ether);
    }

    function test_GraduationCannotBeRepeatedOrRegisteredTwice() public {
        (, uint256 positionId) = manager.graduate(address(token));

        vm.expectRevert();
        manager.graduate(address(token));

        vm.prank(address(manager));
        vm.expectRevert(LiquidityLocker.AlreadyRegistered.selector);
        locker.registerPosition(address(token), positionId);
    }

    function test_LockerRejectsInvalidConstructionBindingAndNFTSender() public {
        vm.expectRevert(LiquidityLocker.Unauthorized.selector);
        new LiquidityLocker(address(0), address(adapter));

        LiquidityLocker fresh = new LiquidityLocker(address(this), address(adapter));
        vm.prank(makeAddr("stranger"));
        vm.expectRevert(LiquidityLocker.Unauthorized.selector);
        fresh.bindGraduationManager(address(manager));
        vm.expectRevert(LiquidityLocker.Unauthorized.selector);
        fresh.bindGraduationManager(address(0));
        fresh.bindGraduationManager(address(manager));

        vm.expectRevert(LiquidityLocker.InvalidNFT.selector);
        fresh.onERC721Received(address(this), address(0), 1, "");
        vm.prank(address(adapter));
        assertEq(fresh.onERC721Received(address(this), address(0), 1, ""), IERC721Receiver.onERC721Received.selector);
    }
}
