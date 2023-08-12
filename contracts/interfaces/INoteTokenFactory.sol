// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '../storage/Registry.sol';
import '../tokens/ERC20/NoteToken.sol';

abstract contract INoteTokenFactory {
    Registry public registry;

    NoteToken[] public tokens;

    mapping(address => bool) public isExistingTokens;

    function changeMinterRole(address token, address newController) external virtual;

    function createToken(
        address poolAddress,
        Configuration.NOTE_TOKEN_TYPE noteTokenType,
        uint8 _nDecimals
    ) external virtual returns (address);
}
