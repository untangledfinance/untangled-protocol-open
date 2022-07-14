// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./TokenTopup.sol";
import "../../base/UntangledBase.sol";
import "../../storage/Registry.sol";
import "../../libraries/ConfigHelper.sol";
import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";

/**
* Manage all of Topup requests from Barter Block, or other smart contract
*/
contract TokenTopupController is UntangledBase {

    enum TokenType { Unknown, Commodity, Fiat }

    // List all of topup request
    mapping(string => address) topups;
    /**
    * TODO: Need to customize this mapping when we support other organization to do withrawal for users
    */

    /** CONSTRUCTOR */
    function initialize() public initializer {
        __UntangledBase__init(_msgSender());
    }

    event NewTopupRequest(address indexed token, address from, uint amount, uint expTime);

    function newTopup(
        string memory _refID,
        address _tokenOwner,
        uint8 _tokenType,
        address _tokenAddress,
        uint _amount,
        uint _expTime
    ) public onlyRole(OWNER_ROLE) {
        require(_tokenType != uint8(TokenType.Unknown), "Unknown token type.");
        require(_tokenAddress != address(0), "Invalid token address.");
        require(_amount != 0, "Invalid withdrawal amount.");
        require(_expTime > 0, "Invalid expiration time.");

        // Create new contract instance
        TokenTopup topup = new TokenTopup(
            msg.sender,
            _refID,
            _tokenOwner,
            _tokenType,
            _tokenAddress,
            _amount,
            _expTime
        );
        topups[_refID] = address(topup);
        ERC20PresetMinterPauser(_tokenAddress).mint(address(topup), _amount);

        emit NewTopupRequest(_tokenAddress, _tokenOwner, _amount, _expTime);
    }

    function contractAddressOf(string memory _refID) public view returns (address) {
        return topups[_refID];
    }

}
