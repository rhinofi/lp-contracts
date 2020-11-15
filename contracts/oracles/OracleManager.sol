pragma solidity ^0.6.2;

import '@uniswap/lib/contracts/libraries/FixedPoint.sol';
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';

import "./UniswapV2OracleLibrary.sol";
import "./UniswapV2Library.sol";

import "@openzeppelin/contracts-ethereum-package/contracts/Initializable.sol";

contract OracleManager is Initializable {
  using FixedPoint for *;

  address public uniswapFactory;
  address public WETH;
  address NEC;

  uint public constant PERIOD = 24 hours;

  // token to WETH price
  mapping (address => FixedPoint.uq112x112) internal T2WPrice;
  // WETH to token price
  mapping (address => FixedPoint.uq112x112) internal W2TPrice;
  mapping (address => uint256) internal price0CumulativeLastUpdate;
  mapping (address => uint256) internal price1CumulativeLastUpdate;
  mapping (address => uint32) public blockTimestampLastUpdate;

  mapping (address => IUniswapV2Pair) public uniswapPairs;

  function __OracleManager_init(address _factory, address _WETH, address _NEC) internal initializer {
    uniswapFactory = _factory;
    WETH = _WETH;
    NEC = _NEC;
    registerNewOracle(NEC);
  }

  function updateExchangeRate(address token) external returns (bool) {
    require(token != WETH, 'OracleManager: WETH_RATE_UPDATE_NOT_REQUIRED');
    require(address(uniswapPairs[token]) != address(0), 'OracleManager: TOKEN_NOT_ON_UNISWAP');

    IUniswapV2Pair pair = uniswapPairs[token];
    (uint price0Cumulative, uint price1Cumulative, uint32 blockTimestamp) =
    UniswapV2OracleLibrary.currentCumulativePrices(address(pair));
    uint32 timeElapsed = blockTimestamp - blockTimestampLastUpdate[token]; // overflow is desired

    // ensure that at least one full period has passed since the last update
    require(timeElapsed >= PERIOD, 'OracleManager: PERIOD_NOT_ELAPSED');

    // overflow is desired, casting never truncates
    // cumulative price is in (uq112x112 price * seconds) units so we simply wrap it after division by time elapsed
    FixedPoint.uq112x112 memory p0 = FixedPoint.uq112x112(uint224((price0Cumulative - price0CumulativeLastUpdate[token]) / timeElapsed));
    price0CumulativeLastUpdate[token] = price0Cumulative;
    FixedPoint.uq112x112 memory p1 = FixedPoint.uq112x112(uint224((price1Cumulative - price1CumulativeLastUpdate[token]) / timeElapsed));
    price1CumulativeLastUpdate[token] = price1Cumulative;
    blockTimestampLastUpdate[token] = blockTimestamp;

    if (pair.token0() == WETH) {
      W2TPrice[token] = p0;
      T2WPrice[token] = p1;
    } else {
      T2WPrice[token] = p0;
      W2TPrice[token] = p1;
    }
    return true;
  }

  // For a specified token and amount
  // Returns the equivalent value as a quantity of NEC
  function necExchangeRate(address token, uint256 amountInToken) public view returns (uint256 amountInNEC) {
    if (token == NEC) {
      amountInNEC = amountInToken;
    } else if (token == WETH) {
      amountInNEC = W2TPrice[NEC].mul(amountInToken).decode144();
    } else {
      amountInNEC = T2WPrice[token].mul(amountInToken).decode144() * W2TPrice[NEC].decode();
    }
    require(amountInNEC != 0, 'OracleManager: PRICE_ZERO');
  }

  function registerNewOracle(address token) public returns (bool) {
    if (address(uniswapPairs[token]) != address(0) ||
      token == WETH
    ) {
      return true;
    }
    IUniswapV2Pair _pair = IUniswapV2Pair(UniswapV2Library.pairFor(uniswapFactory, token, WETH));
    (uint reserve0, uint reserve1, uint32 blockTimestampLast) = _pair.getReserves();
    require(reserve0 != 0 && reserve1 != 0, 'OracleManager: NO_RESERVES'); // ensure that there's liquidity in the pair
    price0CumulativeLastUpdate[token] = _pair.price0CumulativeLast();
    price1CumulativeLastUpdate[token] = _pair.price1CumulativeLast();
    blockTimestampLastUpdate[token] = blockTimestampLast;
    uniswapPairs[token] = _pair;
    return true;
  }

}
