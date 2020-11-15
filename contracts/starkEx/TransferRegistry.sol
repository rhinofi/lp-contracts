/*
  Copyright 2019,2020 StarkWare Industries Ltd.

  Licensed under the Apache License, Version 2.0 (the "License").
  You may not use this file except in compliance with the License.
  You may obtain a copy of the License at

  https://www.starkware.co/open-source-license/

  Unless required by applicable law or agreed to in writing,
  software distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions
  and limitations under the License.
*/
pragma solidity ^0.6.2;

import "./FactRegistry.sol";
import "./Identity.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract TransferRegistry is FactRegistry, Identity {

    event LogRegisteredTransfer(
        address recipient,
        address token,
        uint256 amount,
        uint256 salt
    );

    function identify()
        external view override
        returns(string memory)
    {
        return "StarkWare_TransferRegistry_2020_1";
    }

    /*
      Safe wrapper around ERC20/ERC721 calls.
      This is required because many deployed ERC20 contracts don't return a value.
      See https://github.com/ethereum/solidity/issues/4116.
    */
    function safeTokenContractCall(address tokenAddress, bytes memory callData) internal {
        // solium-disable-next-line security/no-low-level-calls
        // NOLINTNEXTLINE: low-level-calls.
        (bool success, bytes memory returndata) = address(tokenAddress).call(callData);
        require(success, string(returndata));

        if (returndata.length > 0) {
            require(abi.decode(returndata, (bool)), "TOKEN_OPERATION_FAILED");
        }
    }

    /*
      The actual transfer is extracted to a function, so that we can easily mock the contract.
    */
    function performEthTransfer(address payable recipient, uint256 value)
        internal {
        recipient.transfer(value);
    }

    /*
      The actual transfer is extracted to a function, so that we can easily mock the contract.
    */
    function performErc20Transfer(address recipient, address erc20, uint256 amount)
        internal {
        safeTokenContractCall(
            erc20,
            abi.encodeWithSelector(IERC20(0).transferFrom.selector, msg.sender, recipient, amount)
        );
    }

    /*
      Passes on the transaction ETH value onto the recipient address,
      and register the associated fact.
      Reverts if the fact has already been registered.
    */
    function transfer(address payable recipient, uint256 salt) // NOLINT: erc20-interface.
        payable
        external {
        bytes32 transferFact = keccak256(
            abi.encodePacked(recipient, msg.value, address(0x0), salt));
        require(!_factCheck(transferFact), "TRANSFER_ALREADY_REGISTERED");
        registerFact(transferFact);
        emit LogRegisteredTransfer(recipient, address(0x0), msg.value, salt);
        performEthTransfer(recipient, msg.value);
    }

    /*
      Transfer the specified amount of erc20 tokens from msg.sender balance to the recipient's
      balance.
      Pre-conditions to successful transfer are that the msg.sender has sufficient balance,
      and the the approval (for the transfer) was granted to this contract.
      A fact with the transfer details is registered upon success.
      Reverts if the fact has already been registered.
    */
    function transferERC20(address recipient, address erc20, uint256 amount, uint256 salt)
        external {
        bytes32 transferFact = keccak256(
            abi.encodePacked(recipient, amount, erc20, salt));
        require(!_factCheck(transferFact), "TRANSFER_ALREADY_REGISTERED");
        registerFact(transferFact);
        emit LogRegisteredTransfer(recipient, erc20, amount, salt);
        performErc20Transfer(recipient, erc20, amount);
    }

}
