// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '../../../base/UntangledBase.sol';
import '../../../interfaces/ITokenGenerationEventFactory.sol';
import '../../../libraries/ConfigHelper.sol';
import '../../../base/Factory.sol';

contract TokenGenerationEventFactory is ITokenGenerationEventFactory, UntangledBase, Factory {
    using ConfigHelper for Registry;

    enum SaleType {
        MINTED_INCREASING_INTEREST
    }

    function initialize(Registry _registry) public initializer {
        __UntangledBase__init(_msgSender());

        registry = _registry;
    }

    modifier onlySecuritizationManager() {
        require(
            _msgSender() == address(registry.getSecuritizationManager()),
            'SecuritizationPool: Only SecuritizationManager'
        );
        _;
    }

    function createNewSaleInstance(
        address issuerTokenController,
        address pool,
        address token,
        address currency,
        uint8 saleType,
        bool longSale
    ) external override onlySecuritizationManager returns (address) {
        address _tgeInstance;

        if (saleType == uint8(SaleType.MINTED_INCREASING_INTEREST)) {
            _tgeInstance = _newMintedIncreasingInterestSale(issuerTokenController, pool, token, currency, longSale);
        } else {
            revert('Unknown sale type');
        }

        return _tgeInstance;
    }

    function _newMintedIncreasingInterestSale(
        address issuerTokenController,
        address pool,
        address token,
        address currency,
        bool longSale
    ) private returns (address) {
        MintedIncreasingInterestTGE tge = registry.getMintedIncreasingInterestTGE();
        address mintedIncreasingInterestTGEAddress = address(tge);
        address tgeAddress = deployMinimal(mintedIncreasingInterestTGEAddress);

        tge.initialize(registry, pool, token, currency, longSale);
        tge.grantRole(tge.OWNER_ROLE(), issuerTokenController);
        tge.revokeRole(tge.OWNER_ROLE(), address(this));

        tgeAddresses.push(tgeAddress);
        isExistingTge[tgeAddress] = true;

        return tgeAddress;
    }

    function pauseUnpauseTge(address tgeAdress) external whenNotPaused nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
        require(isExistingTge[tgeAdress], 'TokenGenerationEventFactory: tge does not exist');
        MintedIncreasingInterestTGE tge = MintedIncreasingInterestTGE(tgeAdress);
        if (tge.paused()) tge.unpause();
        tge.pause();
    }

    function pauseUnpauseAllTges() external whenNotPaused nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint256 i = 0; i < tgeAddresses.length; i++) {
            MintedIncreasingInterestTGE tge = MintedIncreasingInterestTGE(tgeAddresses[i]);
            if (tge.paused()) tge.unpause();
            else tge.pause();
        }
    }
}
