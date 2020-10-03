pragma solidity ^0.6.2;

import '@uniswap/lib/contracts/libraries/FixedPoint.sol';
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';

import "./UniswapV2OracleLibrary.sol";
import "./UniswapV2Library.sol";

contract OracleManager {
  using FixedPoint for *;

  address uniswapFactory;
  address USDT;
  address NEC;

  uint public constant PERIOD = 24 hours;
  mapping (address => uint256) public priceCumulativeLastUpdate;
  mapping (address => uint32) public blockTimestampLastUpdate;

  mapping (address => FixedPoint.uq112x112) public tokenToUSDTPrice;
  mapping (address => IUniswapV2Pair) public uniswapPairs;

  constructor(address _factory, address _USDT, address _NEC) public {
    uniswapFactory = _factory;
    USDT = _USDT;
    NEC = _NEC;
    registerNewOracle(NEC);
  }

  function updateExchangeRate(address token) external returns (bool) {
    IUniswapV2Pair pair = uniswapPairs[token];
    (uint priceCumulative, uint price1Cumulative, uint32 blockTimestamp) =
    UniswapV2OracleLibrary.currentCumulativePrices(address(pair));
    uint32 timeElapsed = blockTimestamp - blockTimestampLastUpdate[token]; // overflow is desired

    // ensure that at least one full period has passed since the last update
    require(timeElapsed >= PERIOD, 'ExampleOracleSimple: PERIOD_NOT_ELAPSED');

    // overflow is desired, casting never truncates
    // cumulative price is in (uq112x112 price * seconds) units so we simply wrap it after division by time elapsed
    tokenToUSDTPrice[token] = FixedPoint.uq112x112(uint224((priceCumulative - priceCumulativeLastUpdate[token]) / timeElapsed));
    priceCumulativeLastUpdate[token] = priceCumulative;
    blockTimestampLastUpdate[token] = blockTimestamp;
    return true;
  }

  // Returns the rate of NEC vs a specified token (token / nec) i.e. 0.3 usdt / nec
  function necExchangeRate(address token) internal returns (uint256) {
    // Going to need to do some Maths magic here to get it working
    return tokenToUSDTPrice[token].mul(1).decode144() * (tokenToUSDTPrice[NEC]).mul(1).decode144();
  }

  function registerNewOracle(address token) public returns (bool) {
    return true; // This function doesnt work yet without a real uniswapFactory
    IUniswapV2Pair _pair = IUniswapV2Pair(UniswapV2Library.pairFor(uniswapFactory, token, USDT));
    (uint reserve0, uint reserve1, uint blockTimestampLast) = _pair.getReserves();
    require(reserve0 != 0 && reserve1 != 0, 'ExampleOracleSimple: NO_RESERVES'); // ensure that there's liquidity in the pair
    uniswapPairs[token] = _pair;
    return true;
  }

}
