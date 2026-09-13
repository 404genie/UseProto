// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {LaunchPriceOracle} from "../../src/LaunchPriceOracle.sol";

contract LaunchPriceOracleTest is Test {
    address internal owner = makeAddr("oracle-owner");
    address internal attacker = makeAddr("attacker");
    LaunchPriceOracle internal oracle;

    function setUp() public {
        oracle = new LaunchPriceOracle(owner, 3_000e8);
    }

    function test_InitialPriceAndTimestamp() public view {
        (uint256 price, uint256 updatedAt) = oracle.latestPrice();
        assertEq(price, 3_000e8);
        assertEq(updatedAt, block.timestamp);
        assertEq(oracle.owner(), owner);
    }

    function test_OnlyOwnerCanRefreshPrice() public {
        vm.prank(attacker);
        vm.expectRevert(LaunchPriceOracle.Unauthorized.selector);
        oracle.setPrice(3_100e8);

        vm.warp(block.timestamp + 1);
        vm.prank(owner);
        oracle.setPrice(3_100e8);
        (uint256 price, uint256 updatedAt) = oracle.latestPrice();
        assertEq(price, 3_100e8);
        assertEq(updatedAt, block.timestamp);
    }

    function test_ZeroValuesAreRejected() public {
        vm.expectRevert(LaunchPriceOracle.InvalidPrice.selector);
        new LaunchPriceOracle(address(0), 3_000e8);

        vm.expectRevert(LaunchPriceOracle.InvalidPrice.selector);
        new LaunchPriceOracle(owner, 0);

        vm.prank(owner);
        vm.expectRevert(LaunchPriceOracle.InvalidPrice.selector);
        oracle.setPrice(0);
    }
}
