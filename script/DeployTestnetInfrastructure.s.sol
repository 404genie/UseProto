// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PositionManager} from "@uniswap/v4-periphery/src/PositionManager.sol";
import {IPositionDescriptor} from "@uniswap/v4-periphery/src/interfaces/IPositionDescriptor.sol";
import {IWETH9} from "@uniswap/v4-periphery/src/interfaces/external/IWETH9.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {WETH} from "solmate/src/tokens/WETH.sol";
import {TestnetLaunchPriceOracle} from "./testnet/TestnetLaunchPriceOracle.sol";
import {TestnetPositionDescriptor} from "./testnet/TestnetPositionDescriptor.sol";

/// @notice Deploys isolated V4 infrastructure for Robinhood testnet (chain ID 46630).
contract DeployTestnetInfrastructure is Script {
    uint256 internal constant ROBINHOOD_TESTNET_CHAIN_ID = 46_630;
    uint256 internal constant UNSUBSCRIBE_GAS_LIMIT = 100_000;

    struct Deployment {
        PoolManager poolManager;
        WETH wrappedNative;
        TestnetPositionDescriptor descriptor;
        PositionManager positionManager;
        TestnetLaunchPriceOracle oracle;
    }

    function run() external returns (Deployment memory deployment) {
        require(block.chainid == ROBINHOOD_TESTNET_CHAIN_ID, "Robinhood testnet only");
        uint256 key = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(key);
        address permit2 = vm.envAddress("PERMIT2");
        uint256 launchPriceUsd8 = vm.envUint("LAUNCH_PRICE_USD8");
        require(permit2.code.length != 0, "Permit2 not deployed");
        require(launchPriceUsd8 != 0, "invalid launch price");

        vm.startBroadcast(key);
        deployment.poolManager = new PoolManager(deployer);
        deployment.wrappedNative = new WETH();
        deployment.descriptor = new TestnetPositionDescriptor(
            IPoolManager(address(deployment.poolManager)), address(deployment.wrappedNative)
        );
        deployment.positionManager = new PositionManager(
            IPoolManager(address(deployment.poolManager)),
            IAllowanceTransfer(permit2),
            UNSUBSCRIBE_GAS_LIMIT,
            IPositionDescriptor(address(deployment.descriptor)),
            IWETH9(address(deployment.wrappedNative))
        );
        deployment.oracle = new TestnetLaunchPriceOracle(deployer, launchPriceUsd8);
        vm.stopBroadcast();

        console2.log("V4_POOL_MANAGER", address(deployment.poolManager));
        console2.log("WRAPPED_NATIVE", address(deployment.wrappedNative));
        console2.log("V4_POSITION_DESCRIPTOR", address(deployment.descriptor));
        console2.log("V4_POSITION_MANAGER", address(deployment.positionManager));
        console2.log("LAUNCH_PRICE_ORACLE", address(deployment.oracle));
        console2.log("PERMIT2", permit2);
    }
}
