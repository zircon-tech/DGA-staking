# DGA-Staking

Stake ERC-721 and get rewarded with ERC-20.

## Structure

1. Deploy DGAWallet (this is a Multisig wallet that'll get funded by the ETH deposited to the staking contracts)

2. Deploy AccessControls from DGAWallet

3. Deploy DEEP and set AccessControls

4. Deploy DKeeper

5. Deploy DKeeperGenesisStaking, DKeeperLPSTaking and DKeeperNFTStaking

6. Deploy Rewards