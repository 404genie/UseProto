import { JsonRpcProvider } from "ethers";

const rpcUrl = process.env.RH_RPC_URL ?? "https://rpc.testnet.chain.robinhood.com";
const provider = new JsonRpcProvider(rpcUrl);
const network = await provider.getNetwork();
if (network.chainId !== 46630n) throw new Error(`expected chain 46630, received ${network.chainId}`);

const probes = {
  PUSH0: "0x5f5ff3",
  TSTORE: "0x600160005d60006000f3",
  TLOAD: "0x60005c5060006000f3",
};
const result = { chainId: network.chainId.toString(), blockNumber: await provider.getBlockNumber(), opcodes: {} };
for (const [name, data] of Object.entries(probes)) {
  result.opcodes[name] = { supported: true, estimatedGas: (await provider.estimateGas({ data })).toString() };
}
process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
