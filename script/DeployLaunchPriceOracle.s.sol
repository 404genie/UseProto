// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {LaunchPriceOracle} from "../src/LaunchPriceOracle.sol";

/// @notice Deploy the production launch-price reference separately from ProtoBase.
/// @dev Set PRICE_ORACLE_OWNER to a multisig before a public mainnet launch.
contract DeployLaunchPriceOracle is Script {
    function run() external returns (LaunchPriceOracle oracle) {
        uint256 key = vm.envUint("PRIVATE_KEY");
        address owner = vm.envAddress("PRICE_ORACLE_OWNER");
        uint256 initialPriceUsd8 = vm.envUint("LAUNCH_PRICE_USD8");
        if (owner == address(0) || initialPriceUsd8 == 0) revert("invalid oracle config");

        vm.startBroadcast(key);
        oracle = new LaunchPriceOracle(owner, initialPriceUsd8);
        vm.stopBroadcast();

        console2.log("LAUNCH_PRICE_ORACLE", address(oracle));
        console2.log("PRICE_ORACLE_OWNER", owner);
        console2.log("LAUNCH_PRICE_USD8", initialPriceUsd8);
    }
}
