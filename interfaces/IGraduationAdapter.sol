// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
interface IGraduationAdapter {
    function initializeAndMint(address token, uint256 tokenAmount, address locker)
        external payable returns (bytes32 poolId, uint256 positionId);
}
