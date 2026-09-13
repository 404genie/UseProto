# Protected trade integration

ProtoRouter is the only authorized BondingCurve executor. A registered curve is bound to one token and creator.

On buy, the curve prices the entire allocation and transfers it to the system-classified Router. The Router sends only the recipient's available liquid capacity to that address and commits all excess into VestingVault. VestingVault synchronizes the resulting committed balance with RewardEngine.

On sell, the Router pulls only liquid ERC-20 tokens from the user and forwards them to the curve. Vesting positions have no sell path.

After each trade, the Router atomically withdraws the curve's accrued quote fee and records it in FeeController. Any failure rolls back the complete trade. Direct calls to curve execution methods revert.

The current registration/configuration authority is deliberately one-time or append-only. ProtoCore and ProtoFactory will replace the test registrar during the factory milestone.

