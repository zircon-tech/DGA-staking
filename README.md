# DGA-Staking

Stake ERC-721 and get rewarded with ERC-20.

## Structure

1. Deploy DGAWallet (this is a Multisig wallet that'll get funded by the ETH deposited to the staking contracts)

2. Deploy AccessControls (RBA) from DGAWallet

3. Deploy DEEP (ERC-20) and set AccessControls Contract

4. Deploy DKeeper Contract (ERC-721)

5. Deploy DKeeperGenesisStaking Contract (Staking)

6. Deploy Rewards Contract

7. Call `DKeeperGenesisStaking.setContributions` after the 200 NFTs were bought (copy-paste the mapping `contribution`)