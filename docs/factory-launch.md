# Factory launch flow

ProtoFactory exposes permissionless token creation with only name, symbol, and metadata URI controlled by the creator. Supply, liquid cap, vesting, fee, curve shape, and graduation threshold are protocol-defined.

At launch, Factory reads a freshness-checked native/USD reference once and derives the immutable virtual quote reserve for the approximately $2,000 target. ProtoCore records the snapshot and derived reserve. No trading function reads the oracle.

ProtoCore registers the token, creator, curve, lifecycle, and system addresses before Factory transfers the full fixed supply into the curve. Router registration is performed canonically by ProtoCore.

The Foundry EVM target is `paris`, avoiding PUSH0/EIP-3855 bytecode that Robinhood Chain testnet does not support.
