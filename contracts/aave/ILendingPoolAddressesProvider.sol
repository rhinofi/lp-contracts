pragma solidity ^0.6.2;

/**
@title ILendingPoolAddressesProvider interface
@notice provides the interface to fetch the LendingPool address
 */

interface ILendingPoolAddressesProvider {
    function getLendingPool() external view returns (address);
}
