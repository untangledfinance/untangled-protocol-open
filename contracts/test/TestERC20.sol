// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';

/// @title TestERC20
/// @author Untangled Team
/// @dev Used for test purpose only
contract TestERC20 is ERC20 {
    constructor(string memory name,
        string memory symbol,
        uint256 initialSupply) ERC20(name, symbol) {
        _mint(msg.sender, initialSupply);
    }
}
