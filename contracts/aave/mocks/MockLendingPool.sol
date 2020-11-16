pragma solidity ^0.6.2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// For simplicity have combined lending pool and AToken in tests
contract MockLendingPool is ERC20 {

  address supportedAsset;

  constructor(address _supportedAsset) public ERC20("Aave Interest Token", "ATKN") {
    supportedAsset = _supportedAsset;
  }

  function deposit(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external {
    _mint(msg.sender, amount);
    IERC20(asset).transferFrom(msg.sender, address(this), amount);
  }

  function withdraw(address asset, uint256 amount, address to) external {
    _burn(msg.sender, amount);
    IERC20(asset).transfer(msg.sender, amount);
  }

  function getReserveData(address asset) external view returns(
    uint256 configuration,
    uint128 liquidityIndex,
    uint128 variableBorrowIndex,
    uint128 currentLiquidityRate,
    uint128 currentVariableBorrowRate,
    uint128 currentStableBorrowRate,
    uint40 lastUpdateTimestamp,
    address aTokenAddress,
    address stableDebtTokenAddress,
    address variableDebtTokenAddress,
    address interestRateStrategyAddress,
    uint8 id
  ) {
    configuration = 0;
    liquidityIndex = 0;
    variableBorrowIndex = 0;
    currentLiquidityRate = 0;
    currentVariableBorrowRate = 0;
    currentStableBorrowRate = 0;
    lastUpdateTimestamp = 0;
    if (asset == supportedAsset) {
      aTokenAddress = address(this);
    } else {
      aTokenAddress = address(0);
    }
    stableDebtTokenAddress = address(0);
    variableDebtTokenAddress = address(0);
    interestRateStrategyAddress = address(0);
    id = 0;
  }
}
