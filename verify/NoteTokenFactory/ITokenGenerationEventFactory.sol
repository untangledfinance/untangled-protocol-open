// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import './Registry.sol';

abstract contract ITokenGenerationEventFactory {
    Registry public registry;

    address[] public tgeAddresses;

    mapping(address => bool) public isExistingTge;

    function createNewSaleInstance(
        address issuerTokenController,
        address pool,
        address token,
        address currency,
        uint8 saleType,
        bool longSale
    ) external virtual returns (address);
}
