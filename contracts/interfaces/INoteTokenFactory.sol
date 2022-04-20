// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '../libraries/ConfigHelper.sol';

interface INoteTokenFactory {
    function changeTokenController(address token, address newController) external;

    function createToken(
        address poolAddress,
        Configuration.NOTE_TOKEN_TYPE noteTokenType,
        uint8 _nDecimals
    ) external returns (address);
}
