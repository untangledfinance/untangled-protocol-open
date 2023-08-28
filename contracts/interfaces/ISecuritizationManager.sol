// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import '../storage/Registry.sol';
import './ISecuritizationPool.sol';

abstract contract ISecuritizationManager {
    Registry public registry;

    mapping(address => bool) public isExistingPools;
    ISecuritizationPool[] public pools;

    mapping(address => address) public poolToSOT;
    mapping(address => address) public poolToJOT;

    mapping(address => bool) public isExistingTGEs;

    bytes32 public constant POOL_CREATOR = keccak256('POOL_CREATOR');
}
