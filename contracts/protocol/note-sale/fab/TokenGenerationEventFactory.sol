// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import '../../../base/UntangledBase.sol';
import '../../../interfaces/ITokenGenerationEventFactory.sol';
import '../../../libraries/ConfigHelper.sol';
import '../../../base/Factory.sol';
import '../../../libraries/UntangledMath.sol';

contract TokenGenerationEventFactory is ITokenGenerationEventFactory, UntangledBase, Factory {
    using ConfigHelper for Registry;

    bytes4 constant TGE_INIT_FUNC_SELECTOR = bytes4(keccak256('initialize(address,address,address,address,bool)'));

    enum SaleType {
        MINTED_INCREASING_INTEREST_SOT,
        NORMAL_SALE_JOT,
        NORMAL_SALE_SOT
    }

    function initialize(Registry _registry, address _factoryAdmin) public initializer {
        __UntangledBase__init(_msgSender());
        __Factory__init(_factoryAdmin);

        registry = _registry;
    }

    modifier onlySecuritizationManager() {
        require(
            _msgSender() == address(registry.getSecuritizationManager()),
            'SecuritizationPool: Only SecuritizationManager'
        );
        _;
    }

    function setFactoryAdmin(address _factoryAdmin) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _setFactoryAdmin(_factoryAdmin);
    }

    function createNewSaleInstance(
        address issuerTokenController,
        address pool,
        address token,
        address currency,
        uint8 saleType,
        bool longSale
    ) external override nonReentrant onlySecuritizationManager returns (address) {
        if (saleType == uint8(SaleType.MINTED_INCREASING_INTEREST_SOT)) {
            return _newMintedIncreasingInterestSale(issuerTokenController, pool, token, currency, longSale);
        } else if (saleType == uint8(SaleType.NORMAL_SALE_JOT)) {
            return _newNormalSale(issuerTokenController, pool, token, currency, longSale);
        } else if (saleType == uint8(SaleType.NORMAL_SALE_SOT)) {
            return _newNormalSale(issuerTokenController, pool, token, currency, longSale);
        } else {
            revert('Unknown sale type');
        }
    }

    function _newMintedIncreasingInterestSale(
        address issuerTokenController,
        address pool,
        address token,
        address currency,
        bool longSale
    ) private returns (address) {
        address mintedIncreasingInterestTGEImplAddress = address(registry.getMintedIncreasingInterestTGE());

        bytes memory _initialData = abi.encodeWithSelector(
            TGE_INIT_FUNC_SELECTOR,
            registry,
            pool,
            token,
            currency,
            longSale
        );

        address tgeAddress = _deployInstance(mintedIncreasingInterestTGEImplAddress, _initialData);
        MintedIncreasingInterestTGE tge = MintedIncreasingInterestTGE(tgeAddress);

        tge.grantRole(tge.OWNER_ROLE(), issuerTokenController);
        tge.renounceRole(tge.OWNER_ROLE(), address(this));

        tgeAddresses.push(tgeAddress);
        isExistingTge[tgeAddress] = true;

        emit TokenGenerationEventCreated(tgeAddress);

        return tgeAddress;
    }

    function _newNormalSale(
        address issuerTokenController,
        address pool,
        address token,
        address currency,
        bool longSale
    ) private returns (address) {
        address mintedNormalTGEImplAddress = address(registry.getMintedNormalTGE());

        bytes memory _initialData = abi.encodeWithSelector(
            TGE_INIT_FUNC_SELECTOR,
            registry,
            pool,
            token,
            currency,
            longSale
        );

        address tgeAddress = _deployInstance(mintedNormalTGEImplAddress, _initialData);
        MintedNormalTGE tge = MintedNormalTGE(tgeAddress);

        tge.grantRole(tge.OWNER_ROLE(), issuerTokenController);
        tge.renounceRole(tge.OWNER_ROLE(), address(this));

        tgeAddresses.push(tgeAddress);
        isExistingTge[tgeAddress] = true;

        emit TokenGenerationEventCreated(tgeAddress);

        return tgeAddress;
    }

    function pauseUnpauseTge(address tgeAdress) external whenNotPaused onlyRole(DEFAULT_ADMIN_ROLE) {
        require(isExistingTge[tgeAdress], 'TokenGenerationEventFactory: tge does not exist');
        MintedIncreasingInterestTGE tge = MintedIncreasingInterestTGE(tgeAdress);
        if (tge.paused()) {
            tge.unpause();
        } else {
            tge.pause();
        }
    }

    function pauseUnpauseAllTges() external whenNotPaused nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 tgeAddressesLength = tgeAddresses.length;
        for (uint256 i = 0; i < tgeAddressesLength; i = UntangledMath.uncheckedInc(i)) {
            MintedIncreasingInterestTGE tge = MintedIncreasingInterestTGE(tgeAddresses[i]);
            if (tge.paused()) {
                tge.unpause();
            } else {
                tge.pause();
            }
        }
    }

    uint256[50] private __gap;
}
