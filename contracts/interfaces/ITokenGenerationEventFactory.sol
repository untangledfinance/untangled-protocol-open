// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ITokenGenerationEventFactory {
    function createNewSaleInstance(
        address issuerTokenController,
        address pool,
        address token,
        address currency,
        uint8 saleType,
        bool longSale
    ) external returns (address);
}
