// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {V4GraduationAdapter} from "../../src/V4GraduationAdapter.sol";

contract V4GraduationAdapterTest is Test {
    address internal constant MANAGER = address(0xA11CE);
    V4GraduationAdapter internal adapter;

    function setUp() public {
        vm.deal(MANAGER, 1 ether);
        adapter = new V4GraduationAdapter(address(this), address(0xBEEF), address(0xCAFE));
        adapter.bindGraduation(MANAGER, address(1));
    }

    function test_OnlyGraduationManagerCanMint() public {
        vm.expectRevert(V4GraduationAdapter.Unauthorized.selector);
        adapter.initializeAndMint{value: 1}(address(1), 1, address(2));
    }

    function test_RejectsAmountsThatCannotFitPositionManagerBounds() public {
        vm.expectRevert(V4GraduationAdapter.AmountTooLarge.selector);
        vm.prank(MANAGER);
        adapter.initializeAndMint{value: 1}(address(1), uint256(type(uint128).max) + 1, address(2));
    }

    function test_GraduationBindingCannotBeReconfigured() public {
        vm.expectRevert(V4GraduationAdapter.AlreadyConfigured.selector);
        adapter.bindGraduation(MANAGER, address(2));
    }

    function test_OnlyConfiguratorCanBindGraduation() public {
        V4GraduationAdapter fresh = new V4GraduationAdapter(address(this), address(0xBEEF), address(0xCAFE));
        vm.prank(address(0xBAD));
        vm.expectRevert(V4GraduationAdapter.Unauthorized.selector);
        fresh.bindGraduation(MANAGER, address(1));
    }
}
