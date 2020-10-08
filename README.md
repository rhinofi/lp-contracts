# lp-contracts
Contracts defining logic for liquidity providers for DeversiFi conditional transactions


TODO:

- Use initialize pattern and version of open-zeppelin supporting upgrades and use upgrades plugin for tests
- Deal with specific treatment of ETH (as opposed to WETH)
- Add claiming of NEC insurance if DeversiFi defaults
- Check for attack vector where someone requests exit but doesnt finalise for a long time until they know there wont be funds in the contract to satisfy it (in order to take higher value in NEC)
- More checks / tests around oracles if price is not defined
