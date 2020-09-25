pragma solidity ^0.6.2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "../starkEx/FactRegistry.sol";
import "../starkEx/Identity.sol";
import "./WithdrawalPoolToken.sol";
import "../oracles/UniswapV2OracleLibrary.sol";
import '@uniswap/lib/contracts/libraries/FixedPoint.sol';

contract WithdrawalPoolTransferRegistry is FactRegistry, Identity, WithdrawalPoolToken  {
  using SafeERC20 for IERC20;
  using SafeMath for uint256;
  using FixedPoint for *;

  uint public constant PERIOD = 24 hours;
  uint public priceCumulativeLast;
  uint32  public blockTimestampLast;

  address poolToken;
  address nectarToken;
  address uniswapPair;
  string contractName;

  uint256 public lentSupply;

  // 0.1% pool fee as basis points
  // In future this fee can either be set via an equation related to the size of withdrawal and pool
  // Or via governance of LP token holders
  uint256 poolFee = 10;
  // We must have 3x as much value in Nectar as collateral compared to what is lent out
  uint256 reserveRatio = 3;
  FixedPoint.uq112x112 public necPriceAverage;

  constructor (
    string memory _name,
    string memory _symbol,
    address _poolToken,
    address _nectarToken,
    address _uniswapNECUSDTPair
  ) public WithdrawalPoolToken(_name, _symbol) {
    contractName = string(abi.encodePacked("DeversiFi_WithdrawalPoolRegistry_v0.0.1_", _name));
    poolToken = _poolToken;
    nectarToken = _nectarToken;
    uniswapPair = _uniswapNECUSDTPair;
  }

  function identify()
      external view override
      returns(string memory)
  {
      return contractName;
  }

  event LogRegisteredTransfer(
      address recipient,
      address token,
      uint256 amount,
      uint256 salt
  );

  event LogJoinedPool(
      address joiner,
      address token,
      uint256 shares
  );

  event LogExitedPool(
      address leaver,
      address token,
      uint256 shares
  );

  /*
    Transfer the specified amount of erc20 tokens from msg.sender balance to the recipient's
    balance.
    Pre-conditions to successful transfer are that the msg.sender has sufficient balance,
    and the the approval (for the transfer) was granted to this contract.
    A fact with the transfer details is registered upon success.
    Reverts if the fact has already been registered.
  */
  function transferERC20(address recipient, uint256 amount, uint256 salt)
      external onlyOwner {
      bytes32 transferFact = keccak256(
          abi.encodePacked(recipient, amount, poolToken, salt));
      require(!_factCheck(transferFact), "TRANSFER_ALREADY_REGISTERED");
      registerFact(transferFact);
      emit LogRegisteredTransfer(recipient, poolToken, amount, salt);
      IERC20(poolToken).safeTransferFrom(address(this), recipient, calculateAmountMinusFee(amount));
      lend(amount);
  }

  function joinPool(uint256 amountUnderlying) public {
    uint256 totalPoolShares = totalSupply();
    uint256 newPoolShares = totalPoolShares.mul(amountUnderlying).div(totalPoolSize());
    emit LogJoinedPool(msg.sender, poolToken, newPoolShares);
    IERC20(poolToken).safeTransferFrom(msg.sender, address(this), amountUnderlying);
    _mint(msg.sender, newPoolShares);
  }

  function exitPool(uint256 amountUnderlying) public {
    uint256 totalPoolShares = totalSupply();
    uint256 userPoolShares = balanceOf(msg.sender);
    uint256 removedPoolShares = totalPoolShares.mul(amountUnderlying).div(totalPoolSize());
    if (removedPoolShares > userPoolShares) {
      removedPoolShares = userPoolShares;
      amountUnderlying = removedPoolShares.mul(totalPoolSize()).div(totalPoolShares);
    }
    emit LogExitedPool(msg.sender, poolToken, removedPoolShares);
    if (totalPoolSize().sub(lentSupply) >= amountUnderlying) {
      IERC20(poolToken).safeTransfer(msg.sender, amountUnderlying);
      _burn(msg.sender, removedPoolShares);
    } else {
      // We need to go into a queue of some sort or have a way to fulfil this request
    }
  }

  function calculateAmountMinusFee(uint256 amount) internal returns (uint256) {
    return amount.sub(amount.mul(poolFee).div(100));
  }

  function lend(uint256 amount) internal returns (bool) {
    lentSupply = lentSupply.add(amount);
    require(lentSupply <= IERC20(poolToken).balanceOf(address(this)));
    require(lentSupply.mul(necExchangeRate()) <= totalNectar().div(reserveRatio));
    return true;
  }

  function repay(uint256 amount) external returns (bool) {
    lentSupply.sub(amount);
    IERC20(poolToken).safeTransferFrom(msg.sender, address(this), amount);
    return true;
  }

  function updateNecExchangeRate() external returns (bool) {
    (uint priceCumulative, uint price1Cumulative, uint32 blockTimestamp) =
    UniswapV2OracleLibrary.currentCumulativePrices(uniswapPair);
    uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired

    // ensure that at least one full period has passed since the last update
    require(timeElapsed >= PERIOD, 'ExampleOracleSimple: PERIOD_NOT_ELAPSED');

    // overflow is desired, casting never truncates
    // cumulative price is in (uq112x112 price * seconds) units so we simply wrap it after division by time elapsed
    necPriceAverage = FixedPoint.uq112x112(uint224((priceCumulative - priceCumulativeLast) / timeElapsed));
    priceCumulativeLast = priceCumulative;
    blockTimestampLast = blockTimestamp;
    return true;
  }

  function necExchangeRate() internal returns (uint256) {
    return necPriceAverage.mul(1).decode144();
  }

  function totalNectar() internal returns (uint256) {
    return IERC20(nectarToken).balanceOf(address(this));
  }

  function totalPoolSize() internal returns (uint256) {
    return IERC20(poolToken).balanceOf(address(this)) + lentSupply;
  }

}
