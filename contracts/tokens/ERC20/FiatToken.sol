// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol';

contract FiatToken is ERC20PresetMinterPauser {
    uint8 internal _d;
    constructor(
        address minter,
        string memory name,
        string memory symbol,
        uint8 _decimals
    ) ERC20PresetMinterPauser(name, symbol) {
        _d = _decimals;
        _setupRole(MINTER_ROLE, minter);
        renounceRole(MINTER_ROLE, _msgSender());
    }

    function decimals() public view override returns (uint8) {
        return _d;
    }

}
