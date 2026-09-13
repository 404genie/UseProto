// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IProtoToken} from "../interfaces/IProtoToken.sol";
import {IRewardEngine} from "../interfaces/IRewardEngine.sol";

/// @notice Holds Proto-mediated excess allocations in bounded, linear vesting tranches.
contract VestingVault is ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint64 public constant VESTING_DURATION = 30 days;

    struct Position {
        uint128 amount;
        uint128 claimed;
        uint64 start;
    }

    address public immutable committer;
    IRewardEngine public immutable rewardEngine;
    mapping(address token => mapping(address beneficiary => Position[])) private _positions;
    mapping(address token => mapping(address beneficiary => uint256)) public committedBalance;
    mapping(address token => mapping(address beneficiary => uint256)) public claimCursor;
    mapping(address token => uint256) public totalCommitted;

    error Unauthorized();
    error InvalidInput();
    error AmountTooLarge();
    error NothingClaimable();
    error VaultInsolvent();

    event Committed(address indexed token, address indexed beneficiary, uint256 indexed positionId, uint256 amount);
    event Claimed(address indexed token, address indexed beneficiary, uint256 amount);

    constructor(address committer_, address rewardEngine_) {
        if (committer_ == address(0) || rewardEngine_ == address(0)) revert InvalidInput();
        committer = committer_;
        rewardEngine = IRewardEngine(rewardEngine_);
    }

    function commit(address token, address beneficiary, uint256 amount) external nonReentrant {
        if (msg.sender != committer) revert Unauthorized();
        if (token == address(0) || beneficiary == address(0) || amount == 0) revert InvalidInput();
        if (amount > type(uint128).max) revert AmountTooLarge();

        IERC20 asset = IERC20(token);
        uint256 beforeBalance = asset.balanceOf(address(this));
        asset.safeTransferFrom(msg.sender, address(this), amount);
        if (asset.balanceOf(address(this)) - beforeBalance != amount) revert InvalidInput();

        Position[] storage positions = _positions[token][beneficiary];
        positions.push(Position({amount: uint128(amount), claimed: 0, start: uint64(block.timestamp)}));
        committedBalance[token][beneficiary] += amount;
        totalCommitted[token] += amount;
        rewardEngine.updateCommitment(token, beneficiary, committedBalance[token][beneficiary]);
        _assertSolvent(token);
        emit Committed(token, beneficiary, positions.length - 1, amount);
    }

    function claim(address token, uint256 maxPositions) external nonReentrant returns (uint256 released) {
        if (maxPositions == 0) revert InvalidInput();
        IProtoToken asset = IProtoToken(token);
        uint256 capacity = asset.liquidCapacity(msg.sender);
        if (capacity == 0) revert NothingClaimable();

        Position[] storage positions = _positions[token][msg.sender];
        uint256 cursor = claimCursor[token][msg.sender];
        uint256 end = cursor + maxPositions;
        if (end > positions.length) end = positions.length;

        for (uint256 i = cursor; i < end && released < capacity; ++i) {
            Position storage tranche = positions[i];
            uint256 vested = _vested(tranche);
            uint256 available = vested - tranche.claimed;
            if (available != 0) {
                uint256 room = capacity - released;
                uint256 amount = available < room ? available : room;
                tranche.claimed += uint128(amount);
                released += amount;
            }
            if (tranche.claimed == tranche.amount) cursor = i + 1;
        }

        if (released == 0) revert NothingClaimable();
        claimCursor[token][msg.sender] = cursor;
        committedBalance[token][msg.sender] -= released;
        totalCommitted[token] -= released;
        rewardEngine.updateCommitment(token, msg.sender, committedBalance[token][msg.sender]);
        IERC20(token).safeTransfer(msg.sender, released);
        _assertSolvent(token);
        emit Claimed(token, msg.sender, released);
    }

    function claimable(address token, address beneficiary, uint256 maxPositions)
        external
        view
        returns (uint256 amount)
    {
        if (maxPositions == 0) return 0;
        Position[] storage positions = _positions[token][beneficiary];
        uint256 cursor = claimCursor[token][beneficiary];
        uint256 end = cursor + maxPositions;
        if (end > positions.length) end = positions.length;
        for (uint256 i = cursor; i < end; ++i) {
            amount += _vested(positions[i]) - positions[i].claimed;
        }
        uint256 capacity = IProtoToken(token).liquidCapacity(beneficiary);
        return amount < capacity ? amount : capacity;
    }

    function positionCount(address token, address beneficiary) external view returns (uint256) {
        return _positions[token][beneficiary].length;
    }

    function getPosition(address token, address beneficiary, uint256 index) external view returns (Position memory) {
        return _positions[token][beneficiary][index];
    }

    function _vested(Position storage tranche) private view returns (uint256) {
        uint256 elapsed = block.timestamp - tranche.start;
        if (elapsed >= VESTING_DURATION) return tranche.amount;
        return uint256(tranche.amount) * elapsed / VESTING_DURATION;
    }

    function _assertSolvent(address token) private view {
        if (IERC20(token).balanceOf(address(this)) < totalCommitted[token]) revert VaultInsolvent();
    }
}
