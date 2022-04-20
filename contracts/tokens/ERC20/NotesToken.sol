// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '../../interfaces/INoteToken.sol';

contract NotesToken is INoteToken {
    function initialize(
        string memory name,
        string memory symbol,
        address _poolAddress
    ) public initializer {
        __ERC20_init(name, symbol);
        poolAddress = _poolAddress;
    }
}
