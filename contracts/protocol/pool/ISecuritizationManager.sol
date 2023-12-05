// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import '../../storage/Registry.sol';
import './ISecuritizationPool.sol';

abstract contract ISecuritizationManager {
    Registry public registry;

    event NewTGECreated(address indexed instanceAddress);
    event NewNotesTokenCreated(address indexed instanceAddress);
    event NewPoolCreated(address indexed instanceAddress);
    event UpdatePotToPool(address indexed pot, address indexed pool);
    event SotDeployed(address indexed sotAddress, address tgeAddress, address poolAddress);
    event JotDeployed(address indexed jotAddress, address tgeAddress, address poolAddress);

    mapping(address => bool) public isExistingPools;
    ISecuritizationPool[] public pools;

    mapping(address => address) public poolToSOT;
    mapping(address => address) public poolToJOT;
    mapping(address => address) public potToPool;

    mapping(address => bool) public isExistingTGEs;

    /// @dev Register pot to pool instance
    /// @param pot Pool linked wallet
    function registerPot(address pot) external virtual;

    uint256[44] private __gap;
}