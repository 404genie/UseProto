// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {DeployPermit2} from "permit2/test/utils/DeployPermit2.sol";
import {PositionManager} from "@uniswap/v4-periphery/src/PositionManager.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {IPositionDescriptor} from "@uniswap/v4-periphery/src/interfaces/IPositionDescriptor.sol";
import {IWETH9} from "@uniswap/v4-periphery/src/interfaces/external/IWETH9.sol";
import {BaseHook} from "@uniswap/v4-periphery/src/utils/BaseHook.sol";
import {WETH} from "solmate/src/tokens/WETH.sol";

import {ProtoToken} from "../../src/ProtoToken.sol";
import {ProtoRouter} from "../../src/ProtoRouter.sol";
import {ProtoHook} from "../../src/ProtoHook.sol";
import {V4GraduationAdapter} from "../../src/V4GraduationAdapter.sol";
import {LiquidityLocker} from "../../src/LiquidityLocker.sol";
import {RewardEngine} from "../../src/RewardEngine.sol";
import {FeeController} from "../../src/FeeController.sol";
import {VestingVault} from "../../src/VestingVault.sol";
import {MockProtoCore} from "../mocks/MockProtoCore.sol";

contract CanonicalDescriptor is IPositionDescriptor {
    IPoolManager public immutable override poolManager;
    address public immutable override wrappedNative;

    constructor(IPoolManager manager_, address wrappedNative_) {
        poolManager = manager_;
        wrappedNative = wrappedNative_;
    }

    function tokenURI(IPositionManager, uint256) external pure returns (string memory) {
        return "";
    }

    function flipRatio(address, address) external pure returns (bool) {
        return false;
    }

    function currencyRatioPriority(address) external pure returns (int256) {
        return 0;
    }

    function nativeCurrencyLabel() external pure returns (string memory) {
        return "ETH";
    }
}

contract CanonicalProtoHook is ProtoHook {
    constructor(IPoolManager manager, MockProtoCore core, address adapter, address router)
        ProtoHook(manager, core, adapter, router)
    {}

    function validateHookAddress(BaseHook) internal pure override {}
}

contract CanonicalV4IntegrationTest is Test, DeployPermit2 {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;
    uint256 internal constant TOKEN_LIQUIDITY = 500_000_000 ether;
    uint256 internal constant NATIVE_LIQUIDITY = 5 ether;
    address internal user = makeAddr("canonical-v4-user");

    PoolManager internal manager;
    IAllowanceTransfer internal permit2;
    PositionManager internal positionManager;
    MockProtoCore internal core;
    ProtoRouter internal router;
    ProtoHook internal hook;
    V4GraduationAdapter internal adapter;
    LiquidityLocker internal locker;
    ProtoToken internal token;
    RewardEngine internal rewards;
    FeeController internal fees;
    VestingVault internal vault;
    bytes32 internal poolId;
    uint256 internal positionId;

    function setUp() public {
        manager = new PoolManager(address(this));
        permit2 = IAllowanceTransfer(deployPermit2());
        WETH weth = new WETH();
        CanonicalDescriptor descriptor = new CanonicalDescriptor(manager, address(weth));
        positionManager = new PositionManager(manager, permit2, 100_000, descriptor, IWETH9(address(weth)));

        core = new MockProtoCore();
        router = new ProtoRouter(address(core));
        rewards = new RewardEngine(address(this));
        fees = new FeeController(address(router), address(this), address(rewards));
        vault = new VestingVault(address(router), address(rewards));
        rewards.bindCommitmentSource(address(vault));
        rewards.bindFeeController(address(fees));
        vm.prank(address(core));
        router.bindModules(address(vault), address(fees));

        address hookAddress = address(uint160(Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG));
        adapter = new V4GraduationAdapter(address(this), address(positionManager), address(permit2));
        CanonicalProtoHook hookImplementation = new CanonicalProtoHook(manager, core, address(adapter), address(router));
        vm.etch(hookAddress, address(hookImplementation).code);
        hook = ProtoHook(hookAddress);
        adapter.bindGraduation(address(this), hookAddress);
        vm.prank(address(core));
        router.bindV4(address(manager), hookAddress);

        locker = new LiquidityLocker(address(this), address(positionManager));
        locker.bindGraduationManager(address(this));
        token = new ProtoToken("Canonical Proto", "CPROTO", SUPPLY, address(core), address(this));
        core.setCurve(address(token), address(1));
        core.setCreator(address(token), address(this));
        core.setSystem(address(token), address(adapter), true);
        core.setSystem(address(token), address(positionManager), true);
        core.setSystem(address(token), address(manager), true);
        core.setSystem(address(token), address(locker), true);
        core.setSystem(address(token), address(router), true);
        core.setSystem(address(token), address(vault), true);
        core.setSystem(address(token), address(rewards), true);
        core.setSystem(address(token), address(fees), true);

        token.approve(address(adapter), TOKEN_LIQUIDITY);
        (poolId, positionId) =
            adapter.initializeAndMint{value: NATIVE_LIQUIDITY}(address(token), TOKEN_LIQUIDITY, address(locker));
        locker.registerPosition(address(token), positionId);
        core.setPool(address(token), poolId);
        core.setGraduated(address(token), true);
        vm.deal(user, 10 ether);
    }

    function test_GraduationMintsCanonicalPositionDirectlyToPermanentLocker() public view {
        assertEq(positionManager.ownerOf(positionId), address(locker));
        assertEq(locker.tokenOfPosition(positionId), address(token));
        assertNotEq(poolId, bytes32(0));
        assertEq(token.balanceOf(address(adapter)), 0);
    }

    function test_ProtectedBuyAndSellExecuteThroughCanonicalPoolManager() public {
        vm.prank(user);
        (uint256 totalOut, uint256 liquid, uint256 committed) =
            router.buyV4{value: 0.5 ether}(address(token), user, 0, TickMath.MIN_SQRT_PRICE + 1, block.timestamp + 1);

        assertGt(totalOut, 0);
        assertEq(liquid, token.maxLiquidBalance());
        assertEq(committed, totalOut - liquid);
        assertEq(token.balanceOf(user), liquid);
        assertEq(vault.committedBalance(address(token), user), committed);
        assertEq(fees.totalFeesRecorded(), 0.005 ether);

        uint256 tokenIn = 1_000_000 ether;
        uint256 nativeBefore = user.balance;
        vm.startPrank(user);
        token.approve(address(router), tokenIn);
        uint256 quoteOut =
            router.sellV4(address(token), tokenIn, payable(user), 0, TickMath.MAX_SQRT_PRICE - 1, block.timestamp + 1);
        vm.stopPrank();

        assertGt(quoteOut, 0);
        assertEq(user.balance, nativeBefore + quoteOut);
        assertGt(fees.totalFeesRecorded(), 0.005 ether);
        assertTrue(fees.feeConservationHolds());
    }
}
