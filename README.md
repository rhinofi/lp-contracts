# lp-contracts
Contracts defining logic for liquidity providers for DeversiFi conditional transactions


TODO:

- Deal with specific treatment of ETH (as opposed to WETH)? (transferETH)
- Solve attack vector where someone requests exit but doesnt finalise for a long time until they know there wont be funds in the contract to satisfy it (in order to take higher value in NEC)
- Optimise transferERC20 for lower gas usage (currently 170k)
