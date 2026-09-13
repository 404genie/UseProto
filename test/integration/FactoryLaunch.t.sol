// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import {Test} from "forge-std/Test.sol";
import {ProtoCore} from "../../src/ProtoCore.sol";
import {ProtoFactory} from "../../src/ProtoFactory.sol";
import {ProtoRouter} from "../../src/ProtoRouter.sol";
import {ProtoToken} from "../../src/ProtoToken.sol";
import {BondingCurve} from "../../src/BondingCurve.sol";
import {VestingVault} from "../../src/VestingVault.sol";
import {RewardEngine} from "../../src/RewardEngine.sol";
import {FeeController} from "../../src/FeeController.sol";
import {MockLaunchPriceOracle} from "../mocks/MockLaunchPriceOracle.sol";

contract FactoryLaunchTest is Test {
    ProtoCore core;
    ProtoFactory factory;
    ProtoRouter router;
    RewardEngine rewards;
    FeeController fees;
    VestingVault vault;
    MockLaunchPriceOracle oracle;
    address creator = makeAddr("creator");

    function setUp() public {
        core = new ProtoCore(address(this));
        router = new ProtoRouter(address(core));
        rewards = new RewardEngine(address(this));
        fees = new FeeController(address(router), makeAddr("treasury"), address(rewards));
        vault = new VestingVault(address(router), address(rewards));
        rewards.bindCommitmentSource(address(vault));
        rewards.bindFeeController(address(fees));
        oracle = new MockLaunchPriceOracle();
        factory = new ProtoFactory(
            address(core), address(router), address(oracle), address(vault), address(rewards), address(this)
        );
        address[] memory v4Systems = new address[](1);
        v4Systems[0] = address(0x4444);
        core.bindProtocol(address(factory), address(router), address(vault), address(fees), address(this), v4Systems);
        core.bindV4(address(0x1111), address(0x2222), address(0x3333), address(0x5555), address(0x6666));
    }

    function test_PermissionlessLaunchSnapshotsPriceAndRegistersEverything() public {
        vm.prank(creator);
        (address tokenAddr, address curveAddr) = factory.createToken("Example", "EXP", "ipfs://meta");
        ProtoToken token = ProtoToken(tokenAddr);
        BondingCurve curve = BondingCurve(payable(curveAddr));
        assertEq(token.totalSupply(), 1_000_000_000 ether);
        assertEq(token.balanceOf(curveAddr), token.totalSupply());
        assertEq(curve.virtualQuoteReserve(), 0.683333333333333333 ether);
        assertTrue(core.isSystemAddress(tokenAddr, curveAddr));
        assertTrue(core.isSystemAddress(tokenAddr, address(router)));
        assertTrue(core.isSystemAddress(tokenAddr, address(this)));
        assertTrue(core.isSystemAddress(tokenAddr, address(0x4444)));
        assertTrue(core.isSystemAddress(tokenAddr, address(0x1111)));
        assertTrue(core.isSystemAddress(tokenAddr, address(0x5555)));
        assertTrue(core.isSystemAddress(tokenAddr, address(0x6666)));
        assertEq(core.creatorOf(tokenAddr), creator);
        assertEq(core.curveOf(tokenAddr), curveAddr);
    }

    function test_StaleOracleBlocksLaunchOnly() public {
        vm.warp(2 hours);
        vm.expectRevert(ProtoFactory.StalePrice.selector);
        factory.createToken("Example", "EXP", "");
    }

    function test_V1EconomicParametersAreFrozen() public view {
        assertEq(factory.TOTAL_SUPPLY(), 1_000_000_000 ether);
        assertEq(factory.VIRTUAL_TOKEN_RATIO_BPS(), 250);
        assertEq(factory.TRADING_FEE_BPS(), 100);
        assertEq(factory.GRADUATION_THRESHOLD(), 5 ether);
        assertEq(factory.TARGET_MARKET_CAP_USD8(), 2_000 * 1e8);
        assertEq(factory.MAX_PRICE_AGE(), 1 hours);
    }
}
