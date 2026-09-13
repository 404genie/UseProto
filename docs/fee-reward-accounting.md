# Fee and reward accounting

Every native quote trading fee is split exactly once:

- 15% protocol claimable balance
- 35% creator claimable balance
- 50% RewardEngine deposit

The holder share receives the rounding remainder so the three allocations always equal the original fee. Creator and protocol payments are pull-based; arbitrary recipients are never called while recording a fee.

RewardEngine uses a `1e27` accumulator. Commitment changes settle a user's prior index before changing their weight, avoiding iteration over holders.

If a holder-fee deposit arrives while total committed balance is zero, it remains escrowed as `undistributedRewards`. The next deposit made while commitments exist indexes the carried amount. This policy preserves the holder allocation but must be explicitly accepted or replaced before production freeze.

The only synchronous external call during fee recording is to the trusted RewardEngine. Router integration must treat FeeController and RewardEngine as one configured protocol boundary and test failure behavior adversarially.

