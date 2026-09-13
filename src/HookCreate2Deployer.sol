// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice Deterministic deployer used to satisfy Uniswap V4 hook address flags.
contract HookCreate2Deployer {
    error DeploymentFailed();

    event Deployed(bytes32 indexed salt, bytes32 indexed initCodeHash, address indexed deployed);

    function deploy(bytes32 salt, bytes calldata creationCode) external returns (address deployed) {
        bytes32 initCodeHash = keccak256(creationCode);
        bytes memory code = creationCode;
        assembly ("memory-safe") {
            deployed := create2(0, add(code, 0x20), mload(code), salt)
        }
        if (deployed == address(0)) revert DeploymentFailed();
        emit Deployed(salt, initCodeHash, deployed);
    }

    function computeAddress(bytes32 salt, bytes32 initCodeHash) external view returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, initCodeHash)))));
    }
}
