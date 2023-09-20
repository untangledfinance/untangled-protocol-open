// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '../storage/Registry.sol';

abstract contract ITokenGenerationEventFactory {
    Registry public registry;

    event TokenGenerationEventCreated(address indexed tgeInstance);

    address[] public tgeAddresses;

    mapping(address => bool) public isExistingTge;

    /// @notice creates a new TGE instance based on the provided parameters and the sale type
    function createNewSaleInstance(
        address issuerTokenController,
        address pool,
        address token,
        address currency,
        uint8 saleType,
        bool longSale
    ) external virtual returns (address);
}
