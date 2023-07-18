// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import './INoteToken.sol';

contract NoteToken is INoteToken {
    constructor(
        string memory name,
        string memory symbol,
        uint8 _decimals,
        address _poolAddress,
        uint8 _noteTokenType
    ) ERC20PresetMinterPauser(name, symbol) {
        _d = _decimals;
        poolAddress = _poolAddress;
        noteTokenType = _noteTokenType;
    }

    function decimals() public view override returns (uint8) {
        return _d;
    }
}
