// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {ProtoCore} from "../src/ProtoCore.sol";
import {ProtoHook} from "../src/ProtoHook.sol";
import {ProtoRouter} from "../src/ProtoRouter.sol";
import {GraduationManager} from "../src/GraduationManager.sol";
import {V4GraduationAdapter} from "../src/V4GraduationAdapter.sol";
import {LiquidityLocker} from "../src/LiquidityLocker.sol";
import {HookCreate2Deployer} from "../src/HookCreate2Deployer.sol";

/// @notice Stage two deployment after mining HOOK_SALT for the exact stage-one addresses.
contract ConfigureV4 is Script {
    function run() external returns (address hook) {
        uint256 key = vm.envUint("PRIVATE_KEY");
        ProtoCore core = ProtoCore(vm.envAddress("PROTO_CORE"));
        ProtoRouter router = ProtoRouter(payable(vm.envAddress("PROTO_ROUTER")));
        GraduationManager graduationManager = GraduationManager(payable(vm.envAddress("GRADUATION_MANAGER")));
        V4GraduationAdapter adapter = V4GraduationAdapter(payable(vm.envAddress("GRADUATION_ADAPTER")));
        LiquidityLocker locker = LiquidityLocker(payable(vm.envAddress("LIQUIDITY_LOCKER")));
        HookCreate2Deployer hookDeployer = HookCreate2Deployer(vm.envAddress("HOOK_CREATE2_DEPLOYER"));
        address poolManager = vm.envAddress("V4_POOL_MANAGER");
        address positionManager = vm.envAddress("V4_POSITION_MANAGER");
        bytes32 salt = vm.envBytes32("HOOK_SALT");

        bytes memory creationCode = abi.encodePacked(
            type(ProtoHook).creationCode, abi.encode(IPoolManager(poolManager), core, address(adapter), address(router))
        );
        vm.startBroadcast(key);
        hook = hookDeployer.deploy(salt, creationCode);
        adapter.bindGraduation(address(graduationManager), hook);
        core.bindV4(poolManager, hook, positionManager, address(adapter), address(locker));
        vm.stopBroadcast();

        require(address(adapter.hook()) == hook, "adapter hook mismatch");
        require(adapter.graduationManager() == address(graduationManager), "adapter manager mismatch");
        require(locker.graduationManager() == address(graduationManager), "locker manager mismatch");
        require(core.v4Bound() && router.v4Bound(), "v4 not bound");
    }
}
