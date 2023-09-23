// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import '@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol';
import '../../interfaces/INoteToken.sol';

/// @title NoteToken
/// @author Untangled Team
/// @dev Template for SOT/JOT token
contract NoteToken is INoteToken, ERC20PresetMinterPauser {
    address internal immutable _poolAddress;
    uint8 internal immutable _noteTokenType;
    uint8 internal immutable _decimals;

    constructor(
        string memory name,
        string memory symbol,
        uint8 decimalsOfToken,
        address poolAddressOfToken,
        uint8 typeOfToken
    ) ERC20PresetMinterPauser(name, symbol) {
        require(poolAddressOfToken != address(0), 'NoteToken: Invalid pool address');

        _decimals = decimalsOfToken;
        _poolAddress = poolAddressOfToken;
        _noteTokenType = typeOfToken;
    }

    function poolAddress() external view returns (address) {
        return _poolAddress;
    }

    function noteTokenType() external view returns (uint8) {
        return _noteTokenType;
    }

    function decimals() public view override(ERC20, IERC20Metadata) returns (uint8) {
        return _decimals;
    }

    function burn(uint256 amount) public override(ERC20Burnable, INoteToken) {
        return ERC20Burnable.burn(amount);
    }

    function mint(address receiver, uint256 amount) public override(INoteToken, ERC20PresetMinterPauser) {
        return ERC20PresetMinterPauser.mint(receiver, amount);
    }
}
