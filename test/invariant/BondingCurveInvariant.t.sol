// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {BondingCurve} from "../../src/BondingCurve.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

contract CurveHandler is Test {
    MockERC20 public token;
    BondingCurve public curve;

    constructor(MockERC20 token_) {
        token = token_;
        vm.deal(address(this), 1_000_000 ether);
    }

    function setCurve(BondingCurve curve_) external {
        require(address(curve) == address(0));
        curve = curve_;
    }
    receive() external payable {}

    function buy(uint96 raw) external {
        uint256 amount = bound(raw, 1e9, 25 ether);
        try curve.buy{value: amount}(0, block.timestamp, address(this)) {
            curve.takeAccruedFees();
        } catch {}
    }

    function sell(uint96 raw) external {
        uint256 balance = token.balanceOf(address(this));
        if (balance == 0) return;
        uint256 amount = bound(raw, 1, balance);
        token.approve(address(curve), amount);
        try curve.sell(amount, 0, block.timestamp, payable(address(this))) {
            curve.takeAccruedFees();
        } catch {}
    }
}

contract BondingCurveInvariantTest is StdInvariant, Test {
    MockERC20 token;
    BondingCurve curve;

    function setUp() public {
        token = new MockERC20();
        CurveHandler handler = new CurveHandler(token);
        curve = new BondingCurve(
            address(token),
            address(handler),
            address(this),
            1_000_000_000 ether,
            10 ether,
            200_000_000 ether,
            100,
            100 ether
        );
        token.mint(address(curve), 1_000_000_000 ether);
        handler.setCurve(curve);
        targetContract(address(handler));
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = CurveHandler.buy.selector;
        selectors[1] = CurveHandler.sell.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_AssetsAlwaysReconcile() public view {
        assertTrue(curve.reservesReconcile());
    }

    function invariant_CurveNeverPromisesMoreTokensThanItOwns() public view {
        assertLe(curve.realTokenReserve(), token.balanceOf(address(curve)));
    }

    function invariant_CurveNeverPromisesMoreQuoteThanItOwns() public view {
        assertLe(curve.realQuoteReserve(), address(curve).balance);
    }
}
