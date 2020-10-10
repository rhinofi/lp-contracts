# lp-contracts
Contracts defining logic for liquidity providers for DeversiFi conditional transactions


TODO:

- Deal with specific treatment of ETH (as opposed to WETH)?
- Solve attack vector where someone requests exit but doesnt finalise for a long time until they know there wont be funds in the contract to satisfy it (in order to take higher value in NEC)
- We at the moment only check that each pool is backed by the total NEC pool, but we actually need to do a sum of all of them. So we should track the global amount lent out represented as NEC?
