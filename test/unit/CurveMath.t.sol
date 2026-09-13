// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {CurveMath} from "../../src/libraries/CurveMath.sol";

contract CurveMathTest is Test {
    function testFuzz_BuyNeverExceedsInventory(uint96 quoteIn, uint96 realQuote, uint96 realToken) public {
        quoteIn = uint96(bound(quoteIn, 1, 1_000 ether));
        realToken = uint96(bound(realToken, 1 ether, 1_000_000_000 ether));
        try new MathHarness().buy(realQuote, realToken, 10 ether, 200_000_000 ether, quoteIn, 100) returns (
            uint256 out, uint256
        ) {
            assertLe(out, realToken);
        } catch {}
    }

    function test_BuyThenSellCannotCreateValue() public {
        MathHarness h = new MathHarness();
        uint256 input = 10 ether;
        (uint256 tokens,) = h.buy(0, 1_000_000_000 ether, 10 ether, 200_000_000 ether, input, 100);
        (, uint256 buyFee) = h.fee(input, 100);
        (uint256 output,,) =
            h.sell(input - buyFee, 1_000_000_000 ether - tokens, 10 ether, 200_000_000 ether, tokens, 100);
        assertLt(output, input);
    }

    function test_FeeAndQuoteRejectInvalidInputs() public {
        MathHarness h = new MathHarness();
        vm.expectRevert(CurveMath.ZeroAmount.selector);
        h.fee(0, 100);
        vm.expectRevert(CurveMath.InvalidFee.selector);
        h.fee(1, 10_000);

        vm.expectRevert(CurveMath.InvalidReserves.selector);
        h.buy(0, 1 ether, 0, 1 ether, 1 ether, 100);
        vm.expectRevert(CurveMath.InvalidReserves.selector);
        h.sell(0, 0, 1 ether, 0, 1, 100);
    }

    function test_QuoteRejectsZeroOutputAndInsufficientLiquidity() public {
        MathHarness h = new MathHarness();
        vm.expectRevert(CurveMath.InsufficientTokenLiquidity.selector);
        h.buy(1 ether, 1, 10 ether, 1, 1, 100);

        vm.expectRevert(CurveMath.InsufficientQuoteLiquidity.selector);
        h.sell(0, 1_000_000_000 ether, 10 ether, 200_000_000 ether, 1 ether, 100);
    }

    function test_FeeRoundingKeepsNonzeroNetInput() public {
        MathHarness h = new MathHarness();
        (uint256 net, uint256 fee) = h.fee(1, 1);
        assertEq(net, 1);
        assertEq(fee, 0);
        (net, fee) = h.fee(10_000, 9_999);
        assertEq(net, 1);
        assertEq(fee, 9_999);
    }
}

contract MathHarness {
    function buy(uint256 rq, uint256 rt, uint256 vq, uint256 vt, uint256 amount, uint16 feeBps)
        external
        pure
        returns (uint256, uint256)
    {
        return CurveMath.quoteBuy(rq, rt, vq, vt, amount, feeBps);
    }

    function sell(uint256 rq, uint256 rt, uint256 vq, uint256 vt, uint256 amount, uint16 feeBps)
        external
        pure
        returns (uint256, uint256, uint256)
    {
        return CurveMath.quoteSell(rq, rt, vq, vt, amount, feeBps);
    }

    function fee(uint256 amount, uint16 feeBps) external pure returns (uint256, uint256) {
        return CurveMath.feeOnInput(amount, feeBps);
    }
}
