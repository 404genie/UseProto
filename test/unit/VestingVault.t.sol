// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {ProtoToken} from "../../src/ProtoToken.sol";
import {VestingVault} from "../../src/VestingVault.sol";
import {MockProtoCore} from "../mocks/MockProtoCore.sol";
import {MockRewardEngine} from "../mocks/MockRewardEngine.sol";

contract VestingVaultTest is Test {
    MockProtoCore core;
    ProtoToken token;
    VestingVault vault;
    address inventory = makeAddr("inventory");
    address alice = makeAddr("alice");
    uint256 constant SUPPLY = 1_000_000_000 ether;

    function setUp() public {
        core = new MockProtoCore();
        token = new ProtoToken("Proto", "PROTO", SUPPLY, address(core), inventory);
        vault = new VestingVault(address(this), address(new MockRewardEngine()));
        core.setSystem(address(token), address(vault), true);
        uint256 maximum = token.maxLiquidBalance();
        vm.prank(inventory);
        token.transfer(address(this), maximum);
        token.approve(address(vault), type(uint256).max);
    }

    function test_LinearVestingAndCapacityLimitedClaim() public {
        uint256 committed = 10_000_000 ether;
        vault.commit(address(token), alice, committed);
        vm.prank(inventory);
        token.transfer(alice, 18_000_000 ether);

        vm.warp(block.timestamp + 15 days);
        assertEq(vault.claimable(address(token), alice, 1), 2_000_000 ether);
        vm.prank(alice);
        assertEq(vault.claim(address(token), 1), 2_000_000 ether);
        assertEq(token.balanceOf(alice), token.maxLiquidBalance());
        assertEq(vault.committedBalance(address(token), alice), 8_000_000 ether);
    }

    function test_ClaimRemainderAfterMakingCapacity() public {
        vault.commit(address(token), alice, 10_000_000 ether);
        vm.prank(inventory);
        token.transfer(alice, 15_000_000 ether);
        vm.warp(block.timestamp + 30 days);
        vm.prank(alice);
        vault.claim(address(token), 1);
        vm.prank(alice);
        token.transfer(makeAddr("receiver"), 5_000_000 ether);
        assertEq(vault.claimable(address(token), alice, 1), 5_000_000 ether);
        vm.prank(alice);
        vault.claim(address(token), 1);
        assertEq(vault.committedBalance(address(token), alice), 0);
    }

    function test_CannotClaimTwiceOrBeforeVesting() public {
        vault.commit(address(token), alice, 1_000_000 ether);
        vm.prank(alice);
        vm.expectRevert(VestingVault.NothingClaimable.selector);
        vault.claim(address(token), 1);
        vm.warp(block.timestamp + 30 days);
        vm.prank(alice);
        vault.claim(address(token), 1);
        vm.prank(alice);
        vm.expectRevert(VestingVault.NothingClaimable.selector);
        vault.claim(address(token), 1);
    }

    function test_OnlyCommitterCanCreatePosition() public {
        vm.prank(alice);
        vm.expectRevert(VestingVault.Unauthorized.selector);
        vault.commit(address(token), alice, 1 ether);
    }
}
