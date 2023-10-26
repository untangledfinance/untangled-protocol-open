// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface ITokenGenerationEventFactory {
    enum SaleType {
        MINTED_INCREASING_INTEREST_SOT,
        NORMAL_SALE_JOT,
        NORMAL_SALE_SOT
    }

    event UpdateTGEImplAddress(SaleType indexed tgeType, address newImpl);

    event TokenGenerationEventCreated(address indexed tgeInstance);

    function tgeAddresses(uint256) external view returns (address);

    function isExistingTge(address) external view returns (bool);

    function TGEImplAddress(SaleType tgeType) external view returns (address);

    /// @notice creates a new TGE instance based on the provided parameters and the sale type
    function createNewSaleInstance(
        address issuerTokenController,
        address pool,
        address token,
        address currency,
        uint8 saleType,
        bool longSale
    ) external returns (address);
}
