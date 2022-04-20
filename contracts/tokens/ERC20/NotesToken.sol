// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '../../interfaces/INoteToken.sol';

contract NotesToken is INoteToken {
    uint8 private _d;

    function initialize(
        string memory name,
        string memory symbol,
        uint8 _decimals,
        address _poolAddress,
        uint8 _noteTokenType
    ) public initializer {
        __ERC20_init_unchained(name, symbol);
        _d = _decimals;
        poolAddress = _poolAddress;
        noteTokenType = _noteTokenType;
    }

    function decimals() public view override returns (uint8) {
        return _d;
    }
}
