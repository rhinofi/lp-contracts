pragma solidity ^0.6.2;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract WithdrawalPoolToken is ERC20, Ownable {

  constructor (string memory name, string memory symbol) public ERC20(name, symbol) {

  }
}
