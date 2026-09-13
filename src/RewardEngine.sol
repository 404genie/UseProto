// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @notice O(1) native-asset reward accounting for committed Proto balances.
contract RewardEngine is ReentrancyGuard {
    uint256 private constant INDEX_PRECISION = 1e27;

    address public immutable configurator;
    address public commitmentSource;
    address public feeController;

    mapping(address token => uint256) public globalRewardIndex;
    mapping(address token => uint256) public totalCommitted;
    mapping(address token => uint256) public undistributedRewards;
    mapping(address token => uint256) public totalRewardDeposited;
    mapping(address token => uint256) public totalRewardClaimed;
    mapping(address token => mapping(address user => uint256)) public committedBalance;
    mapping(address token => mapping(address user => uint256)) public userRewardIndex;
    mapping(address token => mapping(address user => uint256)) public pendingRewards;

    error Unauthorized();
    error AlreadyConfigured();
    error InvalidInput();
    error NothingToClaim();
    error NativeTransferFailed();

    event FeeControllerBound(address indexed feeController);
    event CommitmentUpdated(address indexed token, address indexed user, uint256 oldBalance, uint256 newBalance);
    event RewardDeposited(address indexed token, uint256 received, uint256 indexedAmount, uint256 carried);
    event RewardClaimed(address indexed token, address indexed user, address indexed recipient, uint256 amount);

    constructor(address configurator_) {
        if (configurator_ == address(0)) revert InvalidInput();
        configurator = configurator_;
    }

    function bindCommitmentSource(address source) external {
        if (msg.sender != configurator) revert Unauthorized();
        if (commitmentSource != address(0)) revert AlreadyConfigured();
        if (source == address(0)) revert InvalidInput();
        commitmentSource = source;
    }

    function bindFeeController(address feeController_) external {
        if (msg.sender != configurator) revert Unauthorized();
        if (feeController != address(0)) revert AlreadyConfigured();
        if (feeController_ == address(0)) revert InvalidInput();
        feeController = feeController_;
        emit FeeControllerBound(feeController_);
    }

    function depositReward(address token) external payable {
        if (msg.sender != feeController) revert Unauthorized();
        if (token == address(0) || msg.value == 0) revert InvalidInput();
        totalRewardDeposited[token] += msg.value;

        uint256 distributable = msg.value + undistributedRewards[token];
        uint256 committed = totalCommitted[token];
        if (committed == 0) {
            undistributedRewards[token] = distributable;
            emit RewardDeposited(token, msg.value, 0, distributable);
            return;
        }

        uint256 indexDelta = distributable * INDEX_PRECISION / committed;
        uint256 indexedAmount = indexDelta * committed / INDEX_PRECISION;
        globalRewardIndex[token] += indexDelta;
        undistributedRewards[token] = distributable - indexedAmount;
        emit RewardDeposited(token, msg.value, indexedAmount, undistributedRewards[token]);
    }

    function updateCommitment(address token, address user, uint256 newBalance) external {
        if (msg.sender != commitmentSource) revert Unauthorized();
        if (token == address(0) || user == address(0)) revert InvalidInput();
        _settle(token, user);
        uint256 oldBalance = committedBalance[token][user];
        totalCommitted[token] = totalCommitted[token] - oldBalance + newBalance;
        committedBalance[token][user] = newBalance;
        emit CommitmentUpdated(token, user, oldBalance, newBalance);
    }

    function earned(address token, address user) external view returns (uint256) {
        uint256 delta = globalRewardIndex[token] - userRewardIndex[token][user];
        return pendingRewards[token][user] + committedBalance[token][user] * delta / INDEX_PRECISION;
    }

    function claim(address token, address payable recipient) external nonReentrant returns (uint256 amount) {
        if (recipient == address(0)) revert InvalidInput();
        _settle(token, msg.sender);
        amount = pendingRewards[token][msg.sender];
        if (amount == 0) revert NothingToClaim();
        pendingRewards[token][msg.sender] = 0;
        totalRewardClaimed[token] += amount;
        (bool ok,) = recipient.call{value: amount}("");
        if (!ok) revert NativeTransferFailed();
        emit RewardClaimed(token, msg.sender, recipient, amount);
    }

    function accountedLiabilities(address token) external view returns (uint256) {
        return totalRewardDeposited[token] - totalRewardClaimed[token];
    }

    function _settle(address token, address user) private {
        uint256 index = globalRewardIndex[token];
        uint256 delta = index - userRewardIndex[token][user];
        if (delta != 0) pendingRewards[token][user] += committedBalance[token][user] * delta / INDEX_PRECISION;
        userRewardIndex[token][user] = index;
    }
}
