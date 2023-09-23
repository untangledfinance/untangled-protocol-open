// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';

interface INoteToken is IERC20, IERC20Metadata {
    // address public poolAddress;
    // uint8 public noteTokenType;

    // uint8 internal immutable _d;
    function poolAddress() external view  returns(address);
    function noteTokenType() external view returns(uint8);

    function mint(address receiver, uint256 amount) external;
    function burn(uint256 amount) external;
}
