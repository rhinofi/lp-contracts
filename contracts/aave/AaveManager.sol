pragma solidity ^0.6.2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "./IAToken.sol";
import "./ILendingPool.sol";
import "./ILendingPoolAddressesProvider.sol";

contract AaveManager {
    using SafeERC20 for IERC20;

    // Mainnet: 0x24a42fD28C976A61Df5D00D0599C34c4f90748c8
    // Ropsten: 0x1c8756FD2B28e9426CDBDcC7E3c4d64fa9A54728
    ILendingPoolAddressesProvider public provider;
    IERC20 token;

    uint16 public constant AAVE_REFERRAL_CODE = 148;

    // Make it so that Pool tracks total assets including those in Aave
    // Track any additional interest accruing and make sure none gets stuck / not able to be withdrawn

    constructor(address _lendingPoolRegistry, address _token) public {
      provider = ILendingPoolAddressesProvider(_lendingPoolRegistry);
      token = IERC20(_token);
    }

    function depositToAave(uint256 _amount) internal returns (bool) {
      ILendingPool lendingPool = ILendingPool(provider.getLendingPool());
      token.safeApprove(address(lendingPool), _amount);
      lendingPool.deposit(address(token), _amount, address(this), AAVE_REFERRAL_CODE);
    }

    function withdrawFromAave(uint256 _amount) internal returns (bool) {
      ILendingPool lendingPool = ILendingPool(provider.getLendingPool());
      lendingPool.withdraw(address(token), _amount, address(this));
    }

    function inAaveSupply() public view returns (uint256) {
      ILendingPool lendingPool = ILendingPool(provider.getLendingPool());

      // Initialize aToken
      ( , , , , , , address aTokenAddress, , , , ) = lendingPool.getReserveData(address(token));
      IAToken aToken = IAToken(aTokenAddress);

      return aToken.scaledBalanceOf(address(this));
    }

}
