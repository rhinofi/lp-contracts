pragma solidity ^0.6.2;

contract MockLendingPoolAddressesProvider {

    address lendingPoolAddress;

    function getLendingPool() public view returns (address) {
      return lendingPoolAddress;
    }

    function setLendingPool(address _lendingPoolAddress) public {
      lendingPoolAddress = _lendingPoolAddress;
    }
}
