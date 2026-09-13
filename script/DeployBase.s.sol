// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {ProtoCore} from "../src/ProtoCore.sol";
import {ProtoFactory} from "../src/ProtoFactory.sol";
import {ProtoRouter} from "../src/ProtoRouter.sol";
import {RewardEngine} from "../src/RewardEngine.sol";
import {FeeController} from "../src/FeeController.sol";
import {VestingVault} from "../src/VestingVault.sol";
import {GraduationManager} from "../src/GraduationManager.sol";
import {V4GraduationAdapter} from "../src/V4GraduationAdapter.sol";
import {LiquidityLocker} from "../src/LiquidityLocker.sol";
import {HookCreate2Deployer} from "../src/HookCreate2Deployer.sol";

/// @notice Stage one deployment. No launch can graduate until ConfigureV4 is run.
contract DeployBase is Script {
    struct Deployment {
        ProtoCore core;
        ProtoFactory factory;
        ProtoRouter router;
        RewardEngine rewards;
        FeeController fees;
        VestingVault vault;
        GraduationManager graduationManager;
        V4GraduationAdapter adapter;
        LiquidityLocker locker;
        HookCreate2Deployer hookDeployer;
    }

    function run() external returns (Deployment memory deployment) {
        uint256 key = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(key);
        address treasury = vm.envAddress("PROTOCOL_TREASURY");
        address oracle = vm.envAddress("LAUNCH_PRICE_ORACLE");
        address positionManager = vm.envAddress("V4_POSITION_MANAGER");
        address permit2 = vm.envAddress("PERMIT2");
        require(treasury != address(0) && oracle != address(0), "invalid protocol config");
        require(positionManager != address(0) && permit2 != address(0), "invalid v4 config");

        vm.startBroadcast(key);
        deployment.core = new ProtoCore(deployer);
        deployment.router = new ProtoRouter(address(deployment.core));
        deployment.rewards = new RewardEngine(deployer);
        deployment.fees = new FeeController(address(deployment.router), treasury, address(deployment.rewards));
        deployment.vault = new VestingVault(address(deployment.router), address(deployment.rewards));
        deployment.graduationManager = new GraduationManager(address(deployment.core), deployer);
        deployment.adapter = new V4GraduationAdapter(deployer, positionManager, permit2);
        deployment.locker = new LiquidityLocker(deployer, positionManager);
        deployment.hookDeployer = new HookCreate2Deployer();
        deployment.factory = new ProtoFactory(
            address(deployment.core),
            address(deployment.router),
            oracle,
            address(deployment.vault),
            address(deployment.rewards),
            address(deployment.graduationManager)
        );

        deployment.rewards.bindCommitmentSource(address(deployment.vault));
        deployment.rewards.bindFeeController(address(deployment.fees));
        deployment.locker.bindGraduationManager(address(deployment.graduationManager));
        deployment.graduationManager.bindModules(address(deployment.adapter), address(deployment.locker));
        address[] memory systems = new address[](1);
        systems[0] = address(deployment.rewards);
        deployment.core
            .bindProtocol(
                address(deployment.factory),
                address(deployment.router),
                address(deployment.vault),
                address(deployment.fees),
                address(deployment.graduationManager),
                systems
            );
        vm.stopBroadcast();

        console2.log("ProtoCore", address(deployment.core));
        console2.log("ProtoFactory", address(deployment.factory));
        console2.log("ProtoRouter", address(deployment.router));
        console2.log("RewardEngine", address(deployment.rewards));
        console2.log("FeeController", address(deployment.fees));
        console2.log("VestingVault", address(deployment.vault));
        console2.log("GraduationManager", address(deployment.graduationManager));
        console2.log("V4GraduationAdapter", address(deployment.adapter));
        console2.log("LiquidityLocker", address(deployment.locker));
        console2.log("HookCreate2Deployer", address(deployment.hookDeployer));
    }
}
