// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ISecuritizationManager {
    function isExistingNoteToken(address pool, address noteToken) external view returns (bool);
}
