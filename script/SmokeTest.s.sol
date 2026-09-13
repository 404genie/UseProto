// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ProtoFactory} from "../src/ProtoFactory.sol";
import {ProtoRouter} from "../src/ProtoRouter.sol";

/// @notice Disposable end-to-end check for a configured Robinhood testnet deployment.
/// @dev Uses a small native amount and a uniquely named test token. Do not use on mainnet.
contract SmokeTest is Script {
    uint256 internal constant ROBINHOOD_TESTNET_CHAIN_ID = 46_630;
    uint256 internal constant BUY_AMOUNT = 0.0001 ether;

    function run() external returns (address token, address curve, uint256 bought, uint256 sold, uint256 quoteOut) {
        require(block.chainid == ROBINHOOD_TESTNET_CHAIN_ID, "Robinhood testnet only");
        uint256 key = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(key);
        ProtoFactory factory = ProtoFactory(vm.envAddress("PROTO_FACTORY"));
        ProtoRouter router = ProtoRouter(payable(vm.envAddress("PROTO_ROUTER")));
        uint256 deadline = block.timestamp + 1 hours;

        vm.startBroadcast(key);
        (token, curve) = factory.createToken("Proto Smoke Test", "PSMOKE", "testnet://proto-smoke");
        (bought,,) = router.buy{value: BUY_AMOUNT}(curve, deployer, 0, deadline);
        uint256 liquidBalance = IERC20(token).balanceOf(deployer);
        sold = liquidBalance / 2;
        require(sold != 0, "no liquid tokens received");
        IERC20(token).approve(address(router), sold);
        quoteOut = router.sell(curve, sold, 0, deadline, payable(deployer));
        vm.stopBroadcast();

        console2.log("SMOKE_TOKEN", token);
        console2.log("SMOKE_CURVE", curve);
        console2.log("BOUGHT_TOKENS", bought);
        console2.log("SOLD_LIQUID_TOKENS", sold);
        console2.log("QUOTE_RETURNED", quoteOut);
    }
}
