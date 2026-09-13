// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IRewardEngine} from "../interfaces/IRewardEngine.sol";

/// @notice Pull-based native quote fee accounting with an immutable 15/35/50 split.
contract FeeController is ReentrancyGuard {
    uint16 public constant PROTOCOL_SHARE_BPS = 1_500;
    uint16 public constant CREATOR_SHARE_BPS = 3_500;
    uint16 public constant HOLDER_SHARE_BPS = 5_000;
    uint16 private constant BPS = 10_000;

    address public immutable feeSource;
    address public immutable protocolTreasury;
    IRewardEngine public immutable rewardEngine;

    uint256 public protocolClaimable;
    mapping(address creator => uint256) public creatorClaimable;
    uint256 public totalFeesRecorded;
    uint256 public totalProtocolAllocated;
    uint256 public totalCreatorAllocated;
    uint256 public totalHolderAllocated;

    error Unauthorized();
    error InvalidInput();
    error NothingToClaim();
    error NativeTransferFailed();

    event TradingFeeRecorded(
        address indexed token,
        address indexed creator,
        uint256 totalFee,
        uint256 protocolFee,
        uint256 creatorFee,
        uint256 holderFee
    );
    event CreatorFeesClaimed(address indexed creator, address indexed recipient, uint256 amount);
    event ProtocolFeesClaimed(address indexed recipient, uint256 amount);

    constructor(address feeSource_, address protocolTreasury_, address rewardEngine_) {
        if (feeSource_ == address(0) || protocolTreasury_ == address(0) || rewardEngine_ == address(0)) {
            revert InvalidInput();
        }
        feeSource = feeSource_;
        protocolTreasury = protocolTreasury_;
        rewardEngine = IRewardEngine(rewardEngine_);
    }

    function recordTradingFee(address token, address creator) external payable nonReentrant {
        if (msg.sender != feeSource) revert Unauthorized();
        if (token == address(0) || creator == address(0) || msg.value == 0) revert InvalidInput();

        uint256 protocolFee = msg.value * PROTOCOL_SHARE_BPS / BPS;
        uint256 creatorFee = msg.value * CREATOR_SHARE_BPS / BPS;
        uint256 holderFee = msg.value - protocolFee - creatorFee;

        totalFeesRecorded += msg.value;
        protocolClaimable += protocolFee;
        creatorClaimable[creator] += creatorFee;
        totalProtocolAllocated += protocolFee;
        totalCreatorAllocated += creatorFee;
        totalHolderAllocated += holderFee;

        rewardEngine.depositReward{value: holderFee}(token);
        emit TradingFeeRecorded(token, creator, msg.value, protocolFee, creatorFee, holderFee);
    }

    function claimCreatorFees(address payable recipient) external nonReentrant returns (uint256 amount) {
        if (recipient == address(0)) revert InvalidInput();
        amount = creatorClaimable[msg.sender];
        if (amount == 0) revert NothingToClaim();
        creatorClaimable[msg.sender] = 0;
        _send(recipient, amount);
        emit CreatorFeesClaimed(msg.sender, recipient, amount);
    }

    function claimProtocolFees(address payable recipient) external nonReentrant returns (uint256 amount) {
        if (msg.sender != protocolTreasury) revert Unauthorized();
        if (recipient == address(0)) revert InvalidInput();
        amount = protocolClaimable;
        if (amount == 0) revert NothingToClaim();
        protocolClaimable = 0;
        _send(recipient, amount);
        emit ProtocolFeesClaimed(recipient, amount);
    }

    function feeConservationHolds() external view returns (bool) {
        return totalFeesRecorded == totalProtocolAllocated + totalCreatorAllocated + totalHolderAllocated;
    }

    function _send(address payable recipient, uint256 amount) private {
        (bool ok,) = recipient.call{value: amount}("");
        if (!ok) revert NativeTransferFailed();
    }
}

