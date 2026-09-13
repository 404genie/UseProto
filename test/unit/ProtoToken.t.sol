// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {ProtoToken} from "../../src/ProtoToken.sol";
import {MockProtoCore} from "../mocks/MockProtoCore.sol";

contract ProtoTokenTest is Test {
    MockProtoCore core;
    ProtoToken token;
    address inventory = makeAddr("inventory");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    uint256 constant SUPPLY = 1_000_000_000 ether;

    function setUp() public {
        core = new MockProtoCore();
        token = new ProtoToken("Proto", "PROTO", SUPPLY, address(core), inventory);
    }

    function test_FixedSupplyAndCap() public {
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.maxLiquidBalance(), 20_000_000 ether);
        uint256 maximum = token.maxLiquidBalance();
        vm.prank(inventory);
        token.transfer(alice, maximum);
        vm.prank(inventory);
        vm.expectRevert(abi.encodeWithSelector(ProtoToken.LiquidCapExceeded.selector, alice, maximum + 1, maximum));
        token.transfer(alice, 1);
    }

    function test_OrdinaryTransferCannotBypassCap() public {
        uint256 maximum = token.maxLiquidBalance();
        vm.prank(inventory);
        token.transfer(alice, 15_000_000 ether);
        vm.prank(inventory);
        token.transfer(bob, 10_000_000 ether);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(ProtoToken.LiquidCapExceeded.selector, alice, 21_000_000 ether, maximum));
        token.transfer(alice, 6_000_000 ether);
    }

    function test_ExplicitSystemAddressIsExempt() public {
        core.setSystem(address(token), bob, true);
        vm.prank(inventory);
        token.transfer(bob, 100_000_000 ether);
        assertEq(token.balanceOf(bob), 100_000_000 ether);
    }

    function testFuzz_NonSystemRecipientNeverExceedsCap(uint96 first, uint96 second) public {
        first = uint96(bound(first, 0, token.maxLiquidBalance()));
        second = uint96(bound(second, 0, token.maxLiquidBalance()));
        vm.startPrank(inventory);
        token.transfer(alice, first);
        if (uint256(first) + second <= token.maxLiquidBalance()) {
            token.transfer(alice, second);
        } else {
            vm.expectRevert(
                abi.encodeWithSelector(
                    ProtoToken.LiquidCapExceeded.selector, alice, uint256(first) + second, token.maxLiquidBalance()
                )
            );
            token.transfer(alice, second);
        }
        vm.stopPrank();
        assertLe(token.balanceOf(alice), token.maxLiquidBalance());
    }
}
