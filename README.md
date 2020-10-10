# lp-contracts
Contracts defining logic for liquidity providers for DeversiFi conditional transactions

These contracts are a work in progress draft for a new feature that will be offered on DeversiFi.

Summary:

1. MasterTransferRegistry
- This extends the StarkEx FactRegistry contracts, allowing conditional transactions to be recorded, and therefore allowing for instant arbitrage or fast withdrawals between Layer 2 (DeversiFi) and Layer 1 (mainnet Ethereum)
- This contract is able to create new WithdrawalPools
- It also manages a pool of NEC which acts as an insurance fund for the other pools

2. WithdrawalPool
- There is one withdrawal pool for each token.
- Each withdrawal pool has a Liquidity Provider token to track the pool share ownership of anyone who has deposited into it
- Withdrawal pools earn fees when the funds in the pool are used by DeversiFi to satisfy fast withdrawals.

3. OracleManager
- This manages updating of prices for each token using Uniswap V2 Oracles


TODO:

- Deal with specific treatment of ETH (as opposed to WETH)? (transferETH)
- Solve attack vector where someone requests exit but doesnt finalise for a long time until they know there wont be funds in the contract to satisfy it (in order to take higher value in NEC)
- Optimise transferERC20 for lower gas usage (currently 170k)
