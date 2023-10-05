// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import '@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol';

interface INoteToken is IERC20Upgradeable, IERC20MetadataUpgradeable {
    // address public poolAddress;
    // uint8 public noteTokenType;

    // uint8 internal immutable _d;
    function poolAddress() external view returns (address);

    function noteTokenType() external view returns (uint8);

    function mint(address receiver, uint256 amount) external;

    function burn(uint256 amount) external;
}
