// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import '../storage/Registry.sol';
import '../tokens/ERC20/NoteToken.sol';

abstract contract INoteTokenFactory {

    event TokenCreated(
        address indexed token,
        address indexed poolAddress, 
        Configuration.NOTE_TOKEN_TYPE indexed tokenType, 
        uint8 decimals, 
        string ticker
    );

    Registry public registry;

    NoteToken[] public tokens;

    mapping(address => bool) public isExistingTokens;

    function changeMinterRole(address token, address newController) external virtual;

    /// @notice Creates a new NoteToken contract instance with the specified parameters
    /// Initializes the token with the provided parameters, including the pool address and note token type
    function createToken(
        address poolAddress,
        Configuration.NOTE_TOKEN_TYPE noteTokenType,
        uint8 _nDecimals,
        string calldata ticker
    ) external virtual returns (address);

    uint256[47] private __gap;
}
