pragma solidity ^0.6.2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/access/Ownable.sol";

import "../starkEx/FactRegistry.sol";
import "../starkEx/Identity.sol";
import "./WithdrawalPool.sol";
import "../oracles/OracleManager.sol";

contract MasterTransferRegistry is Initializable, FactRegistry, Identity, OracleManager, OwnableUpgradeSafe  {
  using SafeERC20 for IERC20;
  using SafeMath for uint256;

  string contractName;
  address aaveLendingPoolRegistry;

  mapping (address => address) public tokenPools;
  mapping (address => bool) internal isPool;
  mapping (address => bool) public isAaveActive;
  mapping (address => uint256) public lentSupply;
  mapping (address => uint256) public lentSupplyEquivNEC;

  uint256 public allPoolsLentSupplyEquivNEC;

  // In future this fee can either be set via an equation related to the size of withdrawal and pool
  // Or via governance of LP token holders
  uint256 public sendAfterFee;
  // Ratio of insurance fund to pool funds
  uint8 public reserveRatio;
  // Percentage of funds that LP can instantly withdraw
  uint8 public targetAvailabilityPercentage;

  modifier onlyPool() {
    require(isPool[msg.sender]);
    _;
  }

  function initialize(
    address _uniswapFactory,
    address _WETH,
    address _NEC,
    address _aaveLendingPoolRegistry
  ) public initializer {
    __OracleManager_init(_uniswapFactory, _WETH, _NEC);
    __Ownable_init();
    contractName = string(abi.encodePacked("DeversiFi_MasterTransferRegistry_v0.0.1"));
    aaveLendingPoolRegistry = _aaveLendingPoolRegistry;
    sendAfterFee = 9990;
    reserveRatio = 2;
    targetAvailabilityPercentage = 20;
    require(sendAfterFee < 10000);
    require(targetAvailabilityPercentage <= 100);
    require(reserveRatio > 1);
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

  event LogRepaid(
      address recipient,
      address token,
      uint256 amount
  );

  event LogInsurancePayout(
      address recipient,
      uint256 amount
  );

  event LogStakedNEC(
      address staker,
      uint256 amount
  );

  event LogUnstakedNEC(
      address staker,
      uint256 amount
  );

  event LogNewPoolCreated(
      address underlyingToken,
      address newPool
  );

  /*
    Transfers funds from the pool to the withdrawer from DeversiFi
    A fact with the transfer details is registered upon success.
    Reverts if the fact has already been registered.
  */
  function transferForDeversifiWithdrawals(address erc20, address recipient, uint256 amount, uint256 salt)
      external onlyOwner {
      bytes32 transferFact = keccak256(
          abi.encodePacked(recipient, amount, erc20, salt));
      require(!_factCheck(transferFact), "TRANSFER_ALREADY_REGISTERED");
      registerFact(transferFact);
      emit LogRegisteredTransfer(recipient, erc20, amount, salt);

      if (erc20 == address(0)) {
        recordBorrowingFromPool(WETH, amount);
        WithdrawalPool(payable(tokenPools[WETH])).makeTransferETH(payable(recipient), calculateAmountMinusFee(amount));
      } else {
        recordBorrowingFromPool(erc20, amount);
        WithdrawalPool(payable(tokenPools[erc20])).makeTransfer(recipient, calculateAmountMinusFee(amount));
      }
  }

  function calculateAmountMinusFee(uint256 amount) internal view returns (uint256) {
    return amount.mul(sendAfterFee).div(10000);
  }

  function recordBorrowingFromPool(address erc20, uint256 amount) internal returns (bool) {
    allPoolsLentSupplyEquivNEC = allPoolsLentSupplyEquivNEC.sub(lentSupplyEquivNEC[erc20]);
    lentSupply[erc20] = lentSupply[erc20].add(amount);
    lentSupplyEquivNEC[erc20] = necExchangeRate(erc20, lentSupply[erc20]);
    allPoolsLentSupplyEquivNEC = allPoolsLentSupplyEquivNEC.add(lentSupplyEquivNEC[erc20]);
    require(allPoolsLentSupplyEquivNEC <= totalNEC().div(reserveRatio));
    return true;
  }

  function repayToPool(address erc20, uint256 amount) external returns (bool) {
    lentSupply[erc20] = lentSupply[erc20].sub(amount);
    // Note that to save gas we do not recalculate lentSupplyEquivNEC here since it will be calculated when the next transfer out is made, and is not needed until then
    IERC20(erc20).safeTransferFrom(msg.sender, tokenPools[erc20], amount);
    emit LogRepaid(msg.sender, erc20, amount);
    return true;
  }

  function totalNEC() internal view returns (uint256) {
    return IERC20(NEC).balanceOf(address(this));
  }

  function stakeNECCollateral(uint256 amount) external onlyOwner returns (bool) {
    IERC20(NEC).safeTransferFrom(msg.sender, address(this), amount);
    emit LogStakedNEC(msg.sender, amount);
    return true;
  }

  function unstakeNECCollateral(uint256 amount) external onlyOwner returns (bool) {
    uint256 currentBalance = IERC20(NEC).balanceOf(address(this));
    require(allPoolsLentSupplyEquivNEC.mul(reserveRatio) <= currentBalance.sub(amount));
    IERC20(NEC).safeTransfer(msg.sender, amount);
    emit LogUnstakedNEC(msg.sender, amount);
    return true;
  }

  function payFromInsuranceFund(address erc20, address recipient, uint256 amount) public onlyPool returns (bool) {
    uint256 equivalentValueInNEC = necExchangeRate(erc20, amount);
    IERC20(NEC).safeTransfer(recipient, equivalentValueInNEC.mul(reserveRatio));
    emit LogInsurancePayout(recipient, amount);
    return true;
  }

  function createNewPool(address _newPoolToken) external onlyOwner {
    require(tokenPools[_newPoolToken] == address(0));
    registerNewOracle(_newPoolToken);
    string memory symbol = ERC20(_newPoolToken).symbol();
    WithdrawalPool newPool  = new WithdrawalPool(
      string(abi.encodePacked('DVF-LP-token-', symbol)),
      _newPoolToken,
      aaveLendingPoolRegistry
      );

    tokenPools[_newPoolToken] = address(newPool);
    isPool[address(newPool)] = true;
    emit LogNewPoolCreated(_newPoolToken, address(newPool));
  }

  function setTransferFee(uint256 newFee) external onlyOwner {
    // Fee must be between 0 and 1%
    require(newFee <= 10000);
    require(newFee >= 9900);
    sendAfterFee = newFee;
  }

  function setAvailabilityPercentage(uint8 newPercentage) external onlyOwner {
    require(newPercentage <= 100);
    targetAvailabilityPercentage = newPercentage;
  }

  function setAaveIsActive(address poolAddress, bool isActive) external onlyOwner {
    isAaveActive[poolAddress] = isActive;
    if (isAaveActive[poolAddress] == false) {
      WithdrawalPool(payable(poolAddress)).withdrawAllFromAave();
    }
  }

}
