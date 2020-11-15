pragma solidity ^0.6.2;

contract MockLendingPoolAddressesProvider {

    address lendingPoolAddress;

    constructor(address _lendingPoolAddress) public {
      lendingPoolAddress = _lendingPoolAddress;
    }

    function getLendingPool() public view returns (address) {
      return lendingPoolAddress;
    }

}
