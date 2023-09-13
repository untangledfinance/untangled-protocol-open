// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '../../../base/UntangledBase.sol';
import '../../../interfaces/ITokenGenerationEventFactory.sol';
import '../../../libraries/ConfigHelper.sol';
import '../../../base/Factory.sol';

contract TokenGenerationEventFactory is ITokenGenerationEventFactory, UntangledBase, Factory {
    using ConfigHelper for Registry;

    enum SaleType {
        MINTED_INCREASING_INTEREST,
        NORMAL_SALE
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
        } else if (saleType == uint8(SaleType.NORMAL_SALE)) {
            _tgeInstance = _newNormalSale(issuerTokenController, pool, token, currency, longSale);
        }
        else{
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
        address tgeAddress = deployMinimal(address(registry.getMintedIncreasingInterestTGE()));
        MintedIncreasingInterestTGE tge = MintedIncreasingInterestTGE(tgeAddress);

        tge.initialize(registry, pool, token, currency, longSale);
        tge.grantRole(tge.OWNER_ROLE(), issuerTokenController);
        tge.renounceRole(tge.OWNER_ROLE(), address(this));

        tgeAddresses.push(tgeAddress);
        isExistingTge[tgeAddress] = true;

        return tgeAddress;
    }

    function _newNormalSale(
        address issuerTokenController,
        address pool,
        address token,
        address currency,
        bool longSale
    ) private returns (address) {
        address tgeAddress = deployMinimal(address(registry.getMintedNormalTGE()));
        MintedNormalTGE tge = MintedNormalTGE(tgeAddress);

        tge.initialize(registry, pool, token, currency, longSale);
        tge.grantRole(tge.OWNER_ROLE(), issuerTokenController);
        tge.renounceRole(tge.OWNER_ROLE(), address(this));

        tgeAddresses.push(tgeAddress);
        isExistingTge[tgeAddress] = true;

        return tgeAddress;
    }

    function pauseUnpauseTge(address tgeAdress) external whenNotPaused nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
        require(isExistingTge[tgeAdress], 'TokenGenerationEventFactory: tge does not exist');
        MintedIncreasingInterestTGE tge = MintedIncreasingInterestTGE(tgeAdress);
        if (tge.paused()) {
            tge.unpause();
        } else {
            tge.pause();
        }
    }

    function pauseUnpauseAllTges() external whenNotPaused nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256  tgeAddressesLength =  tgeAddresses.length;
        for (uint256 i = 0; i < tgeAddressesLength; i = UntangledMath.uncheckedInc(i)) {
            MintedIncreasingInterestTGE tge = MintedIncreasingInterestTGE(tgeAddresses[i]);
            if (tge.paused()) {
                tge.unpause();
            } else {
                tge.pause();
            }
        }
    }
}
