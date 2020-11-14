pragma solidity ^0.6.2;

// Aave LendingPool interface
interface ILendingPool {
    function deposit(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external payable;
    function withdraw(address asset, uint256 amount, address to) external;
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
    );
}
