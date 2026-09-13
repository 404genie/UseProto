// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {ProtoCore} from "../../src/ProtoCore.sol";

contract CoreRouterMock {
    address public lastCurve;
    address public lastToken;
    address public lastCreator;
    address public vault;
    address public fees;
    address public poolManager;
    address public hook;

    function registerCurve(address curve, address token, address creator) external {
        lastCurve = curve;
        lastToken = token;
        lastCreator = creator;
    }

    function bindModules(address vault_, address fees_) external {
        vault = vault_;
        fees = fees_;
    }

    function bindV4(address poolManager_, address hook_) external {
        poolManager = poolManager_;
        hook = hook_;
    }
}

contract CoreBalanceMock {
    uint256 public balance;
    uint256 public cap;

    function set(uint256 balance_, uint256 cap_) external {
        balance = balance_;
        cap = cap_;
    }

    function balanceOf(address) external view returns (uint256) {
        return balance;
    }

    function maxLiquidBalance() external view returns (uint256) {
        return cap;
    }
}

contract ProtoCoreTest is Test {
    ProtoCore core;
    CoreRouterMock router;
    address factory = makeAddr("factory");
    address vault = makeAddr("vault");
    address fees = makeAddr("fees");
    address manager = makeAddr("manager");
    address token = makeAddr("token");
    address curve = makeAddr("curve");
    address creator = makeAddr("creator");

    function setUp() public {
        core = new ProtoCore(address(this));
        router = new CoreRouterMock();
    }

    function _bind() internal {
        address[] memory systems = new address[](1);
        systems[0] = makeAddr("extra");
        core.bindProtocol(factory, address(router), vault, fees, manager, systems);
    }

    function _register() internal {
        _bind();
        vm.prank(factory);
        core.registerLaunch(token, creator, curve, 3500e8, 1 ether, "ipfs://metadata");
    }

    function test_ConstructorRejectsZeroConfigurator() public {
        vm.expectRevert(ProtoCore.InvalidInput.selector);
        new ProtoCore(address(0));
    }

    function test_BindProtocolRejectsUnauthorizedAndBadInputs() public {
        address[] memory empty = new address[](0);
        vm.prank(makeAddr("stranger"));
        vm.expectRevert(ProtoCore.Unauthorized.selector);
        core.bindProtocol(factory, address(router), vault, fees, manager, empty);

        vm.expectRevert(ProtoCore.InvalidInput.selector);
        core.bindProtocol(address(0), address(router), vault, fees, manager, empty);
    }

    function test_BindProtocolSetsSystemsAndCannotReconfigure() public {
        _bind();
        assertEq(core.factory(), factory);
        assertEq(core.router(), address(router));
        assertTrue(core.isProtocolSystem(factory));
        assertTrue(core.isProtocolSystem(address(router)));
        assertEq(router.vault(), vault);
        assertEq(router.fees(), fees);

        address[] memory empty = new address[](0);
        vm.expectRevert(ProtoCore.AlreadyConfigured.selector);
        core.bindProtocol(factory, address(router), vault, fees, manager, empty);
    }

    function test_BindV4RejectsInvalidAndCannotReconfigure() public {
        vm.expectRevert(ProtoCore.AlreadyConfigured.selector);
        core.bindV4(address(1), address(2), address(3), address(4), address(5));

        _bind();
        vm.expectRevert(ProtoCore.InvalidInput.selector);
        core.bindV4(address(0), address(2), address(3), address(4), address(5));
        core.bindV4(address(1), address(2), address(3), address(4), address(5));
        assertTrue(core.v4Bound());
        assertTrue(core.isProtocolSystem(address(1)));
        assertEq(router.poolManager(), address(1));
        assertEq(router.hook(), address(2));

        vm.expectRevert(ProtoCore.AlreadyConfigured.selector);
        core.bindV4(address(1), address(2), address(3), address(4), address(5));
    }

    function test_RegisterLaunchRecordsMetadataAndRejectsUnauthorizedDuplicate() public {
        _register();
        (
            address registeredCreator,
            address registeredCurve,
            uint256 price,
            uint256 virtualQuote,
            uint64 launchedAt,
            ProtoCore.Lifecycle lifecycle,
            string memory metadata
        ) = core.tokenInfo(token);
        assertEq(registeredCreator, creator);
        assertEq(registeredCurve, curve);
        assertEq(price, 3500e8);
        assertEq(virtualQuote, 1 ether);
        assertGt(launchedAt, 0);
        assertEq(uint8(lifecycle), uint8(ProtoCore.Lifecycle.ACTIVE_CURVE));
        assertEq(metadata, "ipfs://metadata");
        assertEq(router.lastCurve(), curve);
        assertEq(router.lastToken(), token);
        assertEq(router.lastCreator(), creator);
        assertTrue(core.isSystemAddress(token, factory));
        assertTrue(core.isSystemAddress(token, address(router)));
        assertTrue(core.isSystemAddress(token, curve));

        vm.prank(makeAddr("stranger"));
        vm.expectRevert(ProtoCore.Unauthorized.selector);
        core.registerLaunch(makeAddr("other"), creator, curve, 1, 1, "");

        vm.prank(factory);
        vm.expectRevert(ProtoCore.Registered.selector);
        core.registerLaunch(token, creator, curve, 1, 1, "");
    }

    function test_RegisterLaunchRejectsZeroFields() public {
        _bind();
        vm.startPrank(factory);
        vm.expectRevert(ProtoCore.InvalidInput.selector);
        core.registerLaunch(address(0), creator, curve, 1, 1, "");
        vm.expectRevert(ProtoCore.InvalidInput.selector);
        core.registerLaunch(token, address(0), curve, 1, 1, "");
        vm.expectRevert(ProtoCore.InvalidInput.selector);
        core.registerLaunch(token, creator, address(0), 1, 1, "");
        vm.expectRevert(ProtoCore.InvalidInput.selector);
        core.registerLaunch(token, creator, curve, 0, 1, "");
        vm.stopPrank();
    }

    function test_GraduationLifecycleIsAuthorizedAndMonotonic() public {
        _register();
        vm.prank(makeAddr("stranger"));
        vm.expectRevert(ProtoCore.Unauthorized.selector);
        core.beginGraduation(token);

        vm.prank(manager);
        assertEq(core.beginGraduation(token), curve);
        (,,,,, ProtoCore.Lifecycle lifecycle,) = core.tokenInfo(token);
        assertEq(uint8(lifecycle), uint8(ProtoCore.Lifecycle.GRADUATING));

        vm.prank(manager);
        vm.expectRevert(ProtoCore.InvalidInput.selector);
        core.finalizeGraduation(token, bytes32(0), 1);
        bytes32 pool = keccak256("pool");
        vm.prank(manager);
        core.finalizeGraduation(token, pool, 7);
        assertTrue(core.isGraduated(token));
        assertEq(core.poolOf(token), pool);
        assertEq(core.positionOf(token), 7);

        vm.prank(manager);
        vm.expectRevert(ProtoCore.InvalidInput.selector);
        core.beginGraduation(token);
        vm.prank(manager);
        vm.expectRevert(ProtoCore.InvalidInput.selector);
        core.finalizeGraduation(token, pool, 8);
    }

    function test_SystemAddressRemovalCannotLeaveOverCapBalance() public {
        CoreBalanceMock balance = new CoreBalanceMock();
        _bind();
        vm.prank(factory);
        core.registerLaunch(address(balance), creator, curve, 3500e8, 1 ether, "");
        balance.set(101, 100);
        vm.prank(factory);
        vm.expectRevert(ProtoCore.UnsafeSystemRemoval.selector);
        core.setSystemAddress(address(balance), address(balance), false);

        balance.set(100, 100);
        vm.prank(factory);
        core.setSystemAddress(address(balance), address(balance), true);
        assertTrue(core.isSystemAddress(address(balance), address(balance)));
        vm.prank(factory);
        core.setSystemAddress(address(balance), address(balance), false);
        assertFalse(core.isSystemAddress(address(balance), address(balance)));
    }
}
