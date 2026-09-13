// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {HookCreate2Deployer} from "../../src/HookCreate2Deployer.sol";

contract Create2Target {
    uint256 public immutable value;

    constructor(uint256 value_) {
        value = value_;
    }
}

contract HookCreate2DeployerTest is Test {
    function test_ComputedAddressMatchesDeployment() public {
        HookCreate2Deployer deployer = new HookCreate2Deployer();
        bytes32 salt = keccak256("proto-hook");
        bytes memory creationCode = abi.encodePacked(type(Create2Target).creationCode, abi.encode(uint256(42)));
        address predicted = deployer.computeAddress(salt, keccak256(creationCode));
        address deployed = deployer.deploy(salt, creationCode);

        assertEq(deployed, predicted);
        assertEq(Create2Target(deployed).value(), 42);
    }

    function test_SameSaltAndCodeCannotBeRedeployed() public {
        HookCreate2Deployer deployer = new HookCreate2Deployer();
        bytes32 salt = bytes32(uint256(1));
        bytes memory creationCode = type(Create2Target).creationCode;
        creationCode = abi.encodePacked(creationCode, abi.encode(uint256(1)));
        deployer.deploy(salt, creationCode);

        vm.expectRevert(HookCreate2Deployer.DeploymentFailed.selector);
        deployer.deploy(salt, creationCode);
    }
}
