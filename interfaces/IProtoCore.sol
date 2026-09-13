// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IProtoCore {
    function isSystemAddress(address token, address account) external view returns (bool);
    function curveOf(address token) external view returns (address);
    function creatorOf(address token) external view returns (address);
    function poolOf(address token) external view returns (bytes32);
    function isGraduated(address token) external view returns (bool);
}
