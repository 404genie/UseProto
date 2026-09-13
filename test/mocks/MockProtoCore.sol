// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IProtoCore} from "../../interfaces/IProtoCore.sol";

contract MockProtoCore is IProtoCore {
    mapping(address token => mapping(address account => bool)) public system;
    mapping(address token => address) public curveOf;
    mapping(address token => address) public creatorOf;
    mapping(address token => bytes32) public poolOf;
    mapping(address token => bool) public graduated;

    function setSystem(address token, address account, bool allowed) external {
        system[token][account] = allowed;
    }

    function setCurve(address token, address curve) external {
        curveOf[token] = curve;
    }

    function setCreator(address token, address creator) external {
        creatorOf[token] = creator;
    }

    function setPool(address token, bytes32 pool) external {
        poolOf[token] = pool;
    }

    function setGraduated(address token, bool value) external {
        graduated[token] = value;
    }

    function isSystemAddress(address token, address account) external view returns (bool) {
        return system[token][account];
    }

    function isGraduated(address token) external view returns (bool) {
        return graduated[token];
    }
}
