// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {ProtoToken} from "../../src/ProtoToken.sol";
import {VestingVault} from "../../src/VestingVault.sol";
import {MockProtoCore} from "../mocks/MockProtoCore.sol";
import {MockRewardEngine} from "../mocks/MockRewardEngine.sol";

contract TokenVestingHandler is Test {
    MockProtoCore public core;
    ProtoToken public token;
    VestingVault public vault;
    address public alice = makeAddr("invariant-alice");
    address public bob = makeAddr("invariant-bob");

    constructor() {
        core = new MockProtoCore();
        token = new ProtoToken("Proto", "PROTO", 1_000_000_000 ether, address(core), address(this));
        vault = new VestingVault(address(this), address(new MockRewardEngine()));
        core.setSystem(address(token), address(vault), true);
        token.approve(address(vault), type(uint256).max);
    }

    function transferToAlice(uint96 raw) external {
        _transferWithinCapacity(alice, raw);
    }

    function transferToBob(uint96 raw) external {
        _transferWithinCapacity(bob, raw);
    }

    function commitAlice(uint96 raw) external {
        _commit(alice, raw);
    }

    function commitBob(uint96 raw) external {
        _commit(bob, raw);
    }

    function claimAlice(uint32 jump) external {
        vm.warp(block.timestamp + bound(jump, 0, 31 days));
        vm.prank(alice);
        try vault.claim(address(token), 16) {} catch {}
    }

    function claimBob(uint32 jump) external {
        vm.warp(block.timestamp + bound(jump, 0, 31 days));
        vm.prank(bob);
        try vault.claim(address(token), 16) {} catch {}
    }

    function _transferWithinCapacity(address recipient, uint96 raw) private {
        uint256 capacity = token.liquidCapacity(recipient);
        uint256 inventory = token.balanceOf(address(this));
        uint256 maximum = capacity < inventory ? capacity : inventory;
        if (maximum == 0) return;
        token.transfer(recipient, bound(raw, 1, maximum));
    }

    function _commit(address beneficiary, uint96 raw) private {
        uint256 inventory = token.balanceOf(address(this));
        if (inventory == 0) return;
        vault.commit(address(token), beneficiary, bound(raw, 1, inventory));
    }
}

contract TokenVestingInvariantTest is StdInvariant, Test {
    TokenVestingHandler handler;

    function setUp() public {
        handler = new TokenVestingHandler();
        targetContract(address(handler));
    }

    function invariant_FixedSupply() public view {
        assertEq(handler.token().totalSupply(), 1_000_000_000 ether);
    }

    function invariant_NonSystemBalancesRespectCap() public view {
        ProtoToken token = handler.token();
        assertLe(token.balanceOf(handler.alice()), token.maxLiquidBalance());
        assertLe(token.balanceOf(handler.bob()), token.maxLiquidBalance());
    }

    function invariant_VaultBacksEveryCommittedToken() public view {
        ProtoToken token = handler.token();
        VestingVault vault = handler.vault();
        assertLe(vault.totalCommitted(address(token)), token.balanceOf(address(vault)));
    }

    function invariant_TokenConservation() public view {
        ProtoToken token = handler.token();
        VestingVault vault = handler.vault();
        uint256 accounted = token.balanceOf(address(handler)) + token.balanceOf(handler.alice())
            + token.balanceOf(handler.bob()) + token.balanceOf(address(vault));
        assertEq(accounted, token.totalSupply());
    }
}
