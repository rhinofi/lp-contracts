pragma solidity ^0.6.2;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockWETH is ERC20 {

  constructor() public ERC20("Wrapped Ether", "WETH") {}

  event  Deposit(address indexed dst, uint wad);
  event  Withdrawal(address indexed src, uint wad);

  function deposit() public payable {
    _mint(msg.sender, msg.value);
    Deposit(msg.sender, msg.value);
  }

  function withdraw(uint wad) public {
    _burn(msg.sender, wad);
    msg.sender.transfer(wad);
    Withdrawal(msg.sender, wad);
  }
}
