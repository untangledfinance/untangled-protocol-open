// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '@openzeppelin/contracts-upgradeable/token/ERC20/presets/ERC20PresetMinterPauserUpgradeable.sol';

abstract contract INoteToken is ERC20PresetMinterPauserUpgradeable {
    address public poolAddress;
    uint8 public noteTokenType;
}
