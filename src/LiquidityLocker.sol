// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

/// @notice Permanent custody for Proto V4 position NFTs. Intentionally has no withdrawal path.
contract LiquidityLocker is IERC721Receiver {
    address public immutable configurator;
    address public graduationManager;
    address public immutable positionManager;
    mapping(uint256 positionId => address token) public tokenOfPosition;

    error Unauthorized();
    error InvalidNFT();
    error AlreadyRegistered();
    error AlreadyConfigured();

    event PositionLocked(address indexed token, uint256 indexed positionId);

    constructor(address configurator_, address positionManager_) {
        if (configurator_ == address(0) || positionManager_ == address(0)) revert Unauthorized();
        configurator = configurator_;
        positionManager = positionManager_;
    }

    function bindGraduationManager(address manager_) external {
        if (msg.sender != configurator) revert Unauthorized();
        if (graduationManager != address(0)) revert AlreadyConfigured();
        if (manager_ == address(0)) revert Unauthorized();
        graduationManager = manager_;
    }

    function registerPosition(address token, uint256 positionId) external {
        if (msg.sender != graduationManager) revert Unauthorized();
        if (tokenOfPosition[positionId] != address(0)) revert AlreadyRegistered();
        tokenOfPosition[positionId] = token;
        emit PositionLocked(token, positionId);
    }

    function onERC721Received(address, address, uint256, bytes calldata) external view returns (bytes4) {
        if (msg.sender != positionManager) revert InvalidNFT();
        return IERC721Receiver.onERC721Received.selector;
    }

    /// @dev Accepts permanently locked native dust swept by PositionManager.
    receive() external payable {}
}
