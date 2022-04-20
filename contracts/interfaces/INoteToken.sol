// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol';

abstract contract INoteToken is ERC20PresetMinterPauser {
    address public poolAddress;
    uint8 public noteTokenType;
}
