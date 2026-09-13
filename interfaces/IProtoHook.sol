// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IProtoHook {
    function core() external view returns (address);
    function graduationAdapter() external view returns (address);
    function protoV4Router() external view returns (address);
    function authorizeInitialization(bytes32 poolId) external;
}
