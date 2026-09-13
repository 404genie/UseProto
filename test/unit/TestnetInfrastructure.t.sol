// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {TestnetLaunchPriceOracle} from "../../script/testnet/TestnetLaunchPriceOracle.sol";
import {TestnetPositionDescriptor} from "../../script/testnet/TestnetPositionDescriptor.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

contract TestnetInfrastructureTest is Test {
    TestnetLaunchPriceOracle internal oracle;

    function setUp() public {
        oracle = new TestnetLaunchPriceOracle(address(this), 3_000e8);
    }

    function test_OracleReturnsPriceAndTimestamp() public view {
        (uint256 price, uint256 updatedAt) = oracle.latestPrice();
        assertEq(price, 3_000e8);
        assertEq(updatedAt, block.timestamp);
    }

    function test_OnlyOwnerCanRefreshPrice() public {
        vm.prank(makeAddr("attacker"));
        vm.expectRevert(TestnetLaunchPriceOracle.Unauthorized.selector);
        oracle.setPrice(3_100e8);

        vm.warp(block.timestamp + 1);
        oracle.setPrice(3_100e8);
        (uint256 price, uint256 updatedAt) = oracle.latestPrice();
        assertEq(price, 3_100e8);
        assertEq(updatedAt, block.timestamp);
    }

    function test_DescriptorIsDeterministic() public {
        TestnetPositionDescriptor descriptor = new TestnetPositionDescriptor(IPoolManager(address(1)), address(2));
        assertEq(descriptor.tokenURI(IPositionManager(address(0)), 42), "proto-v4-testnet-position:42");
    }
}
