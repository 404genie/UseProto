// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {BondingCurve} from "../../src/BondingCurve.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

contract BondingCurveTest is Test {
    MockERC20 token;
    BondingCurve curve;
    address alice = makeAddr("alice");
    uint256 constant INVENTORY = 1_000_000_000 ether;

    function setUp() public {
        token = new MockERC20();
        curve = new BondingCurve(address(token), alice, alice, INVENTORY, 10 ether, 200_000_000 ether, 100, 100 ether);
        token.mint(address(curve), INVENTORY);
        vm.deal(alice, 1_000 ether);
    }

    function test_BuyUpdatesAndReconcilesReserves() public {
        (uint256 expected, uint256 fee) = curve.quoteBuy(1 ether);
        uint256 oldPrice = curve.spotPriceWad();
        vm.startPrank(alice);
        uint256 out = curve.buy{value: 1 ether}(expected, block.timestamp, alice);
        curve.takeAccruedFees();
        vm.stopPrank();
        assertEq(out, expected);
        assertEq(curve.realQuoteReserve(), 1 ether - fee);
        assertEq(curve.realTokenReserve(), INVENTORY - out);
        assertGt(curve.spotPriceWad(), oldPrice);
        assertTrue(curve.reservesReconcile());
    }

    function test_BuyThenSellIsSolventAndPriceFalls() public {
        vm.startPrank(alice);
        uint256 tokens = curve.buy{value: 10 ether}(0, block.timestamp, alice);
        curve.takeAccruedFees();
        uint256 postBuyPrice = curve.spotPriceWad();
        token.approve(address(curve), tokens);
        curve.sell(tokens, 0, block.timestamp, payable(alice));
        curve.takeAccruedFees();
        vm.stopPrank();
        assertLt(curve.spotPriceWad(), postBuyPrice);
        assertTrue(curve.reservesReconcile());
        assertLt(alice.balance, 1_000 ether);
    }

    function testFuzz_RepeatedBuySellRemainReconciled(uint96 amount) public {
        amount = uint96(bound(amount, 1e9, 20 ether));
        vm.startPrank(alice);
        uint256 tokens = curve.buy{value: amount}(0, block.timestamp, alice);
        curve.takeAccruedFees();
        token.approve(address(curve), tokens);
        curve.sell(tokens, 0, block.timestamp, payable(alice));
        curve.takeAccruedFees();
        vm.stopPrank();
        assertTrue(curve.reservesReconcile());
        assertLe(curve.realQuoteReserve(), address(curve).balance);
        assertEq(token.balanceOf(address(curve)), curve.realTokenReserve());
    }

    function test_DeadlineAndSlippageRevert() public {
        vm.prank(alice);
        vm.expectRevert(BondingCurve.DeadlineExpired.selector);
        curve.buy{value: 1 ether}(0, block.timestamp - 1, alice);
        vm.prank(alice);
        vm.expectRevert(BondingCurve.SlippageExceeded.selector);
        curve.buy{value: 1 ether}(type(uint256).max, block.timestamp, alice);
    }
}
