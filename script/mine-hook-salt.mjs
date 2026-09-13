import { readFileSync } from "node:fs";
import { AbiCoder, concat, getCreate2Address, keccak256 } from "ethers";

const required = ["HOOK_CREATE2_DEPLOYER", "V4_POOL_MANAGER", "PROTO_CORE", "GRADUATION_ADAPTER", "PROTO_ROUTER"];
for (const name of required) {
  if (!process.env[name]) throw new Error(`missing ${name}`);
}

const artifact = JSON.parse(readFileSync("out/ProtoHook.sol/ProtoHook.json", "utf8"));
const args = AbiCoder.defaultAbiCoder().encode(
  ["address", "address", "address", "address"],
  required.slice(1).map((name) => process.env[name]),
);
const initCode = concat([artifact.bytecode.object, args]);
const initCodeHash = keccak256(initCode);
const expectedFlags = 0x2080n; // beforeInitialize | beforeSwap
const allHookFlags = 0x3fffn;

for (let candidate = 0n; ; candidate++) {
  const salt = `0x${candidate.toString(16).padStart(64, "0")}`;
  const address = getCreate2Address(process.env.HOOK_CREATE2_DEPLOYER, salt, initCodeHash);
  if ((BigInt(address) & allHookFlags) === expectedFlags) {
    process.stdout.write(`${JSON.stringify({ salt, address, initCodeHash }, null, 2)}\n`);
    break;
  }
}
