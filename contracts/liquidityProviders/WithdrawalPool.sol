pragma solidity ^0.6.2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "./WithdrawalPoolToken.sol";
import "./MasterTransferRegistry.sol";
import "../aave/AaveManager.sol";
import "../tokens/IWETH.sol";

contract WithdrawalPool is WithdrawalPoolToken, AaveManager {
  using SafeERC20 for IERC20;
  using SafeMath for uint256;

  address public poolToken;
  address public transferRegistry;
  uint256 constant INITIAL_SUPPLY = 100 * 10 ** 18;
  uint256 public constant MINIMUM_EXIT_PERIOD = 2 hours;
  uint256 public constant MAXIMUM_EXIT_PERIOD = 36 hours;

  // The amount of underlying tokens that are not available to withdraw instantly
  uint256 public reservedUnderlyingBalance;

  struct PendingExit {
    uint256 shares;
    uint256 requestTime;
  }

  mapping (address => PendingExit) public exitRequests;

  modifier onlyRegistry() {
    require(msg.sender == transferRegistry, "Pool: CALLER_MUST_BE_REGISTRY");
    _;
  }

  constructor (
    string memory _symbol,
    address _poolToken,
    address _aaveLendingPoolRegistry
  ) public WithdrawalPoolToken(_symbol, _symbol) AaveManager(_aaveLendingPoolRegistry, _poolToken) {
    poolToken = _poolToken;
    transferRegistry = msg.sender;
  }

  receive() external payable {}

  event LogJoinedPool(
      address joiner,
      address token,
      uint256 amountToken,
      uint256 amountShares
  );

  event LogPendingExit(
      address leaver,
      address token,
      uint256 shares
  );

  event LogExit(
      address leaver,
      address token,
      uint256 amountToken,
      uint256 amountShares
  );

  event LogInsuranceClaim(
      address leaver,
      address token,
      uint256 amountToken,
      uint256 amountShares
  );

  function joinPool(uint256 amountUnderlying) public {
    uint256 totalPoolShares = totalSupply();
    uint256 newPoolShares;
    if (totalPoolSize() == 0) {
       newPoolShares = INITIAL_SUPPLY;
    } else {
       newPoolShares = totalPoolShares.mul(amountUnderlying).div(totalPoolSize());
    }
    emit LogJoinedPool(msg.sender, poolToken, amountUnderlying, newPoolShares);
    _mint(msg.sender, newPoolShares);
    IERC20(poolToken).safeTransferFrom(msg.sender, address(this), amountUnderlying);
    increaseReservedBalance(amountUnderlying);
  }

  function exitPool(uint256 amountPoolShares) public {
    uint256 amountUnderlying = sharesToUnderlying(amountPoolShares);
    if (amountUnderlying <= amountAvailableForInstantExit()) {
      _burn(msg.sender, amountPoolShares);
      IERC20(poolToken).safeTransfer(msg.sender, amountUnderlying);
      emit LogExit(msg.sender, poolToken, amountUnderlying, amountPoolShares);
    } else {
      _transfer(msg.sender, address(this), amountPoolShares);
      emit LogPendingExit(msg.sender, poolToken, amountPoolShares);
      exitRequests[msg.sender] = PendingExit({
        shares: exitRequests[msg.sender].shares.add(amountPoolShares),
        requestTime: now
      });
    }
  }

  function finaliseExit(address exiter) public returns (bool) {
    PendingExit memory pending = exitRequests[exiter];
    if(pending.shares == 0) {
      return false;
    }

    uint256 amountUnderlying = sharesToUnderlying(pending.shares);
    if (now > pending.requestTime + MINIMUM_EXIT_PERIOD) {
      if (amountUnderlying <= amountAvailableForInstantExit()) {
        _burn(address(this), pending.shares);
        return processNormalExit(exiter, amountUnderlying, pending.shares);
      } else if (amountUnderlying <= totalPoolSize().sub(lentSupply())) {
        _burn(address(this), pending.shares);
        resetReservedBalance(amountUnderlying);
        return processNormalExit(exiter, amountUnderlying, pending.shares);
      }
    }
    if (now > pending.requestTime + MAXIMUM_EXIT_PERIOD) {
      payFromInsuranceFund(exiter, amountUnderlying, pending.shares);
      _burn(address(this), pending.shares);
      return true;
    }
    return false;
  }

  function processNormalExit(address exiter, uint256 amount, uint256 shares) internal returns (bool) {
    exitRequests[exiter] = PendingExit({ shares: 0, requestTime: 0 });
    IERC20(poolToken).safeTransfer(exiter, amount);
    emit LogExit(exiter, poolToken, amount, shares);
    return true;
  }

  function makeTemporaryLoan(address recipient, uint256 amount) public onlyRegistry {
    withdrawFromAaveIfRequired(amount);
    IERC20(poolToken).safeTransfer(recipient, amount);
  }

  function makeTemporaryLoanETH(address payable recipient, uint256 amount) public onlyRegistry {
    address WETH = MasterTransferRegistry(transferRegistry).WETH();
    assert(poolToken == WETH);
    withdrawFromAaveIfRequired(amount);
    IWETH(WETH).withdraw(amount);
    recipient.call.value(amount)("");
  }


  // INFORMATION - Pool

  function totalPoolSize() public view returns (uint256) {
    if (isAaveActive()) {
      return IERC20(poolToken).balanceOf(address(this)) + lentSupply() + inAaveSupply();
    }
    return IERC20(poolToken).balanceOf(address(this)) + lentSupply();
  }

  function underlyingTokensOwned(address owner) public view returns (uint256) {
    return sharesToUnderlying(balanceOf(owner));
  }

  function sharesToUnderlying(uint256 amount) internal view returns (uint256) {
    return amount.mul(totalPoolSize()).div(totalSupply());
  }

  function amountAvailableForInstantExit() public view returns (uint256) {
    if (reservedUnderlyingBalance > totalPoolSize().sub(lentSupply())) {
      return 0;
    }
    return totalPoolSize().sub(lentSupply()).sub(reservedUnderlyingBalance);
  }

  // MasterTransferRegistry - Functions calling to the registry

  function payFromInsuranceFund(address exiter, uint256 amount, uint256 shares) internal returns (bool) {
    exitRequests[exiter] = PendingExit({ shares: 0, requestTime: 0 });
    emit LogInsuranceClaim(exiter, poolToken, amount, shares);
    return MasterTransferRegistry(transferRegistry).payFromInsuranceFund(poolToken, exiter, amount);
  }

  function lentSupply() internal view returns (uint256) {
    return MasterTransferRegistry(transferRegistry).lentSupply(poolToken);
  }

  function targetAvailabilityPercentage() internal view returns (uint8) {
    return MasterTransferRegistry(transferRegistry).targetAvailabilityPercentage();
  }

  function targetReservedPercentage() internal view returns (uint8) {
    return 100 - targetAvailabilityPercentage();
  }

  function isAaveActive() internal view returns (bool) {
    return MasterTransferRegistry(transferRegistry).isAaveActive(address(this));
  }

  // RESERVED BALANCE - Internal functions for managing reserved balances

  function increaseReservedBalance(uint256 amount) internal {
    uint256 amountToReserve = amount.mul(targetReservedPercentage()).div(100);
    reservedUnderlyingBalance = reservedUnderlyingBalance.add(amountToReserve);
    if (isAaveActive()) {
      uint256 amountToDeposit = reservedUnderlyingBalance.sub(inAaveSupply());
      depositToAave(amountToDeposit);
    }
  }

  function resetReservedBalance(uint256 amount) internal {
    reservedUnderlyingBalance = totalPoolSize().sub(amount).mul(targetReservedPercentage()).div(100);
    if (isAaveActive()) {
      if (inAaveSupply() > reservedUnderlyingBalance) {
        uint256 amountToWithdraw = inAaveSupply().sub(reservedUnderlyingBalance);
        withdrawFromAave(amountToWithdraw);
      } else {
        uint256 amountToDeposit = reservedUnderlyingBalance.sub(inAaveSupply());
        depositToAave(amountToDeposit);
      }
    }
  }

  function withdrawFromAaveIfRequired(uint256 amount) internal {
    if (!isAaveActive()) return;
    if (IERC20(poolToken).balanceOf(address(this)) >= amount) return;

    resetReservedBalance(amount);
  }

  function withdrawAllFromAave() public onlyRegistry {
    if(inAaveSupply() > 0) {
      withdrawFromAave(uint256(-1));
    }
  }

}
