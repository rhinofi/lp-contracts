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

  mapping (address => address) public tokenPools;
  mapping (address => bool) internal isPool;
  mapping (address => uint256) public lentSupply;

  // In future this fee can either be set via an equation related to the size of withdrawal and pool
  // Or via governance of LP token holders
  uint256 sendAfterFee;
  // Ratio of insurance fund to pool funds
  uint256 reserveRatio;

  modifier onlyPool() {
    require(isPool[msg.sender]);
    _;
  }

  function initialize(
    address _uniswapFactory,
    address _WETH,
    address _NEC
  ) public initializer {
    __OracleManager_init(_uniswapFactory, _WETH, _NEC);
    __Ownable_init();
    contractName = string(abi.encodePacked("DeversiFi_MasterTransferRegistry_v0.0.1"));
    sendAfterFee = 9990;
    reserveRatio = 2;
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

  /*
    Transfer the specified amount of erc20 tokens from msg.sender balance to the recipient's
    balance.
    Pre-conditions to successful transfer are that the msg.sender has sufficient balance,
    and the the approval (for the transfer) was granted to this contract.
    A fact with the transfer details is registered upon success.
    Reverts if the fact has already been registered.
  */
  function transferERC20(address erc20, address recipient, uint256 amount, uint256 salt)
      external onlyOwner {
      bytes32 transferFact = keccak256(
          abi.encodePacked(recipient, amount, erc20, salt));
      require(!_factCheck(transferFact), "TRANSFER_ALREADY_REGISTERED");
      registerFact(transferFact);
      emit LogRegisteredTransfer(recipient, erc20, amount, salt);
      borrowFromPool(erc20, amount);
      IERC20(erc20).safeTransferFrom(tokenPools[erc20], recipient, calculateAmountMinusFee(amount));
  }

  function calculateAmountMinusFee(uint256 amount) internal view returns (uint256) {
    return amount.mul(sendAfterFee).div(10000);
  }

  function borrowFromPool(address erc20, uint256 amount) internal returns (bool) {
    lentSupply[erc20] = lentSupply[erc20].add(amount);
    uint256 equivalentLoanValueInNEC = necExchangeRate(erc20, lentSupply[erc20]);
    require(equivalentLoanValueInNEC <= totalNEC().div(reserveRatio));
    return true;
  }

  function repay(address erc20, uint256 amount) external returns (bool) {
    lentSupply[erc20] = lentSupply[erc20].sub(amount);
    IERC20(erc20).safeTransferFrom(msg.sender, tokenPools[erc20], amount);
    return true;
  }

  function totalNEC() internal view returns (uint256) {
    return IERC20(NEC).balanceOf(address(this));
  }

  function stakeNECCollateral(uint256 amount) external onlyOwner returns (bool) {
    IERC20(NEC).safeTransferFrom(msg.sender, address(this), amount);
    return true;
  }

  function unStakeNECCollateral(uint256 amount) external onlyOwner returns (bool) {
    IERC20(NEC).safeTransfer(msg.sender, amount);
    return true;
  }

  function payFromInsuranceFund(address erc20, address recipient, uint256 amount) public onlyPool returns (bool) {
    uint256 equivalentValueInNEC = necExchangeRate(erc20, amount);
    IERC20(NEC).safeTransfer(recipient, equivalentValueInNEC.mul(reserveRatio));
    return true;
  }

  function createNewPool(address _newPoolToken) public {
    require(tokenPools[_newPoolToken] == address(0));
    registerNewOracle(_newPoolToken);
    string memory symbol = ERC20(_newPoolToken).symbol();
    WithdrawalPool newPool  = new WithdrawalPool(
      symbol,
      _newPoolToken
      );

    tokenPools[_newPoolToken] = address(newPool);
    isPool[address(newPool)] = true;
  }

}
