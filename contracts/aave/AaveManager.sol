pragma solidity ^0.6.2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "./ILendingPool.sol";
import "./ILendingPoolAddressesProvider.sol";

contract AaveManager {
    using SafeERC20 for IERC20;

    ILendingPoolAddressesProvider public provider;
    IERC20 token;

    uint16 constant AAVE_REFERRAL_CODE = 148;

    constructor(address _lendingPoolRegistry, address _token) public {
      provider = ILendingPoolAddressesProvider(_lendingPoolRegistry);
      token = IERC20(_token);
    }

    function depositToAave(uint256 _amount) internal {
      if (_amount == 0) return;
      ILendingPool lendingPool = ILendingPool(provider.getLendingPool());
      token.safeIncreaseAllowance(address(lendingPool), _amount);
      lendingPool.deposit(address(token), _amount, address(this), AAVE_REFERRAL_CODE);
    }

    function withdrawFromAave(uint256 _amount) internal {
      if (_amount == 0) return;
      ILendingPool lendingPool = ILendingPool(provider.getLendingPool());
      lendingPool.withdraw(address(token), _amount, address(this));
    }

    function inAaveSupply() public view returns (uint256) {
      ILendingPool lendingPool = ILendingPool(provider.getLendingPool());

      // Initialize aToken
      ( , , , , , , , address aTokenAddress, , , , ) = lendingPool.getReserveData(address(token));

      return IERC20(aTokenAddress).balanceOf(address(this));
    }

}
