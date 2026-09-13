// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IFeeController} from "../../interfaces/IFeeController.sol";

contract RejectingCreator {
    receive() external payable {
        revert("reject");
    }

    function claimTo(address controller, address payable recipient) external returns (uint256) {
        return IFeeController(controller).claimCreatorFees(recipient);
    }
}
