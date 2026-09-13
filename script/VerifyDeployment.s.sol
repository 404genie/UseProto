// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {ProtoCore} from "../src/ProtoCore.sol";
import {ProtoRouter} from "../src/ProtoRouter.sol";
import {RewardEngine} from "../src/RewardEngine.sol";
import {FeeController} from "../src/FeeController.sol";
import {VestingVault} from "../src/VestingVault.sol";
import {GraduationManager} from "../src/GraduationManager.sol";
import {V4GraduationAdapter} from "../src/V4GraduationAdapter.sol";
import {LiquidityLocker} from "../src/LiquidityLocker.sol";

/// @notice Read-only post-deployment assertions. Reverts on any wiring mismatch.
contract VerifyDeployment is Script {
    function run() external view {
        ProtoCore core = ProtoCore(vm.envAddress("PROTO_CORE"));
        ProtoRouter router = ProtoRouter(payable(vm.envAddress("PROTO_ROUTER")));
        RewardEngine rewards = RewardEngine(payable(vm.envAddress("REWARD_ENGINE")));
        FeeController fees = FeeController(payable(vm.envAddress("FEE_CONTROLLER")));
        VestingVault vault = VestingVault(vm.envAddress("VESTING_VAULT"));
        GraduationManager graduationManager = GraduationManager(payable(vm.envAddress("GRADUATION_MANAGER")));
        V4GraduationAdapter adapter = V4GraduationAdapter(payable(vm.envAddress("GRADUATION_ADAPTER")));
        LiquidityLocker locker = LiquidityLocker(payable(vm.envAddress("LIQUIDITY_LOCKER")));

        require(core.router() == address(router), "core/router");
        require(address(router.vestingVault()) == address(vault), "router/vault");
        require(address(router.feeController()) == address(fees), "router/fees");
        require(rewards.commitmentSource() == address(vault), "rewards/vault");
        require(rewards.feeController() == address(fees), "rewards/fees");
        require(address(graduationManager.adapter()) == address(adapter), "manager/adapter");
        require(address(graduationManager.locker()) == address(locker), "manager/locker");
        require(adapter.graduationManager() == address(graduationManager), "adapter/manager");
        require(locker.graduationManager() == address(graduationManager), "locker/manager");
        require(core.v4Bound() == router.v4Bound(), "v4 binding disagreement");
        if (core.v4Bound()) {
            require(address(adapter.hook()) == address(router.v4Hook()), "hook mismatch");
            require(address(router.v4PoolManager()) != address(0), "pool manager missing");
        }
    }
}
