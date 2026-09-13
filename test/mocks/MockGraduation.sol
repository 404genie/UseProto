// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

contract MockGraduationCore {
    address public curve;
    address public manager;
    uint8 public state = 1;
    bytes32 public poolId;
    uint256 public positionId;

    constructor(address curve_) {
        curve = curve_;
    }

    function setManager(address m) external {
        require(manager == address(0));
        manager = m;
    }

    function beginGraduation(address) external returns (address) {
        require(msg.sender == manager && state == 1);
        state = 2;
        return curve;
    }

    function finalizeGraduation(address, bytes32 p, uint256 id) external {
        require(msg.sender == manager && state == 2);
        poolId = p;
        positionId = id;
        state = 3;
    }
}

contract MockGraduationCurve {
    IERC20 public token;
    uint256 public realQuoteReserve;
    uint256 public graduationThreshold;
    address public manager;

    constructor(address token_, uint256 threshold_) {
        token = IERC20(token_);
        graduationThreshold = threshold_;
    }

    function configure(address manager_) external payable {
        manager = manager_;
        realQuoteReserve = msg.value;
    }

    function releaseForGraduation(address recipient) external returns (uint256 tokens, uint256 quote) {
        require(msg.sender == manager && realQuoteReserve >= graduationThreshold);
        tokens = token.balanceOf(address(this));
        quote = realQuoteReserve;
        realQuoteReserve = 0;
        token.transfer(recipient, tokens);
        (bool ok,) = payable(recipient).call{value: quote}("");
        require(ok);
    }
}

contract MockGraduationAdapter {
    uint256 public nextId = 1;
    bool public fail;

    function setFail(bool value) external {
        fail = value;
    }

    function initializeAndMint(address token, uint256 amount, address locker)
        external
        payable
        returns (bytes32 pool, uint256 id)
    {
        require(!fail);
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        id = nextId++;
        pool = keccak256(abi.encode(token, id));
        IERC721Receiver(locker).onERC721Received(address(this), address(0), id, "");
    }
}
