// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import '../storage/Registry.sol';
import './ISecuritizationPool.sol';

abstract contract ISecuritizationManager {
    Registry public registry;

    mapping(address => bool) public isExistingPools;
    ISecuritizationPool[] public pools;

    mapping(address => address) public poolToSOT;
    mapping(address => address) public poolToJOT;
    mapping(address => address) public potToPool;

    mapping(address => bool) public isExistingTGEs;

    bytes32 public constant POOL_CREATOR = keccak256('POOL_CREATOR');

    /// @dev Register pot to pool instance
    /// @param pot Pool linked wallet
    function registerPot(address pot) external virtual;

    uint256[44] private __gap;
}
