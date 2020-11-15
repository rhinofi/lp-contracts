# DeversiFi Layer 1 Liquidity Provider Contracts

### DeversiFi Overview and Problem Statement

DeversiFi (https://deversifi.com) is a high-speed exchange which is non-custodial (never holds customer Ethereum or ERC20 tokens). To achieve high-speed settlement, at low-cost, without needing to take custody of customer assets, DeversiFi uses the StarkEx (https://starkware.co) scaling solution.

This system works by creating validity proofs containing thousands of transactions, and proving them periodically to a contract on the Ethereum blockchain. The system uses a specific proof technology called STARKs (a form of zero-knowledge cryptography). Thousands of deposits, withdrawal, and trade transactions can be included into a single proof, and then included on-chain as a comparatively small amount of information. You can learn more about the general functioning of the platform at https://deversifi.com or by reading the documentation for the exchange at https://docs.deversifi.com.

DeversiFi is the first exchange to launch using this proof system, and whilst it offers huge benefits in terms of scalability, one drawback is that it means delays for withdrawals and interaction with other Ethereum DeFi applications. These delays are a result of standard withdrawals needing to wait for a batch to be submitted to the blockchain before it can be completed.

Because batches can occur as infrequent as every few hours, this makes arbitrage challenging.

### Solution: Conditional Transfers

The solution to this problem is the introduction of a new transaction type in DeversiFi and StarkEx. This transaction type is know as a **Conditional Transfer**.

Conditional transfers are highly flexible, and can be used for example to facilitate fast withdrawals from DeversiFi by arbitrageurs.

An example of how this works is as follows:

- A trader (Travis) holding 100 ETH on DeversiFi wishes to withdraw to take advantage of an opportunity elsewhere (for example on a centralised exchange).
- A liquidity provider (Lucy) holding 1000 ETH on-chain wishes to earn a fee for providing short-term loans of their ETH, with a guarantee of repayment.
- Travis signs a *conditional transfer*, which allows their 100 ETH to be transferred to an account owned by Lucy on DeversiFi. This transfer of funds however will only be valid on the condition that a specific on-chain transaction can be verified to have occurred on Layer-1 of the Ethereum blockchain.
- If Lucy now transfers 100 ETH to the destination address requested by Travis, they can be credited Travis's ETH on DeversiFi, as well as a charged fee from Travis.
- Lucy can now request a normal (slower) withdrawal for the 100 ETH to replenish their on-chain supply of ETH at the time of the next batch.

This flow currently has two drawbacks:
1. Whilst this is requires no trust on behalf of Travis in either DeversiFi or Lucy, it does require that Lucy trusts DeversiFi to include the conditional transfer into a future batch. If DeversiFi instead chose to censor Lucy, Travis would keep both the 100 ETH transferred on-chain as well as the 100 ETH on DeversiFi. Whilst it would not be in DeversiFi's long-term interest to do this, it in practice means that DeversiFi is the only counter-party who can act as a liquidity-provider trustlessly. N.B. A future upgrade will allow Lucy to force DeversiFi to include conditional transfers using a guarantee mechanism.
2. Because of the previous point, the system is limited to a maximum liquidity of funds that DeversiFi, or its trusted partners owns.

### Liquidity Provider Pools

To allow conditional transfers system to scale for fast withdrawals, DeversiFi has designed the set of smart-contracts in this repository.

The contracts allow:
- Liquidity providers to deposit any of the tokens listed on DeversiFi into a pool and receive a token representing their ownership in that pool. They will then earn a passive yield from fees paid for withdrawals whilst they are part of the pool, in proportion to their ownership.
- DeversiFi to transfer the funds held in the pools out to DeversiFi traders who request fast withdawals. DeversiFi will then replenish any funds used after the subsequent batch proof is submitted. A fee will remain in the pool each time a transfer is made, meaning that the value of the pools grow over time.
- Traders on DeversiFi to receive withdrawals straight away to their destination address.

DeversiFi stakes NEC (the governance token of DeversiFi) as an insurance collateral to guarantee repayment of the funds borrowed from the pool until the time of the next batch (1-3 hours). The value of the staked NEC must be a multiple of the amount used to fulfil conditional transactions.

These pools delegate most of the funds to Aave (when enabled), which means that the pools receive a minimum level of interest that matches Aave, and can generate higher yields when the assets in the pools are actively used for withdrawals.

### Contract Overview

**NOTE: These contracts are pending audit prior to deployment.**

1. MasterTransferRegistry
- This extends the StarkEx FactRegistry contracts, allowing conditional transactions to be recorded, and therefore allowing for instant arbitrage or fast withdrawals between Layer 2 (DeversiFi) and Layer 1 (mainnet Ethereum)
- This contract is able to create new WithdrawalPools
- It also manages a pool of NEC which acts as an insurance fund for the other pools
- This contract is upgradeable, and will therefore be owned either by a multisig of the DAO which governs NEC
- Future upgrades may include governance for changing the fee mechanism, and allowing NEC to be staked by entities other than the owner, earning some rewards

2. WithdrawalPool
- There is one withdrawal pool for each token.
- Each withdrawal pool has a Liquidity Provider token to track the pool share ownership of anyone who has deposited into it
- Withdrawal pools earn fees when the funds in the pool are used by DeversiFi to satisfy fast withdrawals.

3. OracleManager
- This manages updating of prices for each token using Uniswap V2 Oracles
- Pricing is used to ensure that there is a known exchange rate between NEC and other tokens in the case of insurance claims.

4. AaveManager
- This acts as an interface to deposit, withdraw, and read balance of the pool's deposits to Aave
- Can be enabled and disabled per pool
- The percentage of funds deposited to Aave is set in the registry


### Concerns

1. There is a vulnerable point around exit of assets by liquidity providers from the pool. The issue is as follows:
  - An LP requests an exit, but does not finalise this. They wait an unlimited time period until the contract does not have enough of the relevant token to fulfil the request, and then finally call finaliseExit, allowing them to claim NEC worth more than their original share of the pool (due to the insurance fund paying out a multiple to dis-incentivise DeversiFi from not returning funds quickly).
  - There are two potential mitigations to this. A) *anyone* may call the finalise function to exit LP funds, not only the LP (meaning DeversiFi could call it on the LP's behalf). However this has a gas cost associated with it. B) DeversiFi can track funds that are in that status, and ignore them from the pool, avoiding using them to satisfy withdrawal requests.

### Testing

`yarn test`
