// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {ContextUpgradeable} from '@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol';
import {IERC20Upgradeable} from '@openzeppelin/contracts-upgradeable/interfaces/IERC20Upgradeable.sol';
import {ERC20BurnableUpgradeable} from '@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol';
import {IERC721ReceiverUpgradeable} from '@openzeppelin/contracts-upgradeable/interfaces/IERC721ReceiverUpgradeable.sol';
import {IAccessControlUpgradeable} from '@openzeppelin/contracts-upgradeable/access/IAccessControlUpgradeable.sol';

import {IUntangledERC721} from '../../interfaces/IUntangledERC721.sol';
import {INoteToken} from '../../interfaces/INoteToken.sol';
import {ICrowdSale} from '../note-sale/crowdsale/ICrowdSale.sol';

import {ISecuritizationPool} from './ISecuritizationPool.sol';
import {ISecuritizationPoolValueService} from './ISecuritizationPoolValueService.sol';

import {MintedIncreasingInterestTGE} from '../note-sale/MintedIncreasingInterestTGE.sol';
import {ConfigHelper} from '../../libraries/ConfigHelper.sol';
import {Configuration} from '../../libraries/Configuration.sol';
import {UntangledMath} from '../../libraries/UntangledMath.sol';
import {Registry} from '../../storage/Registry.sol';
import {FinalizableCrowdsale} from './../note-sale/crowdsale/FinalizableCrowdsale.sol';
import {POOL_ADMIN} from './types.sol';

import {ISecuritizationPoolERC721Receiver} from './ISecuritizationPoolERC721Receiver.sol';

/**
 * @title Untangled's SecuritizationPool contract
 * @notice Main entry point for senior LPs (a.k.a. capital providers)
 *  Automatically invests across borrower pools using an adjustable strategy.
 * @author Untangled Team
 */
abstract contract SecuritizationPoolERC721Receiver is
    ContextUpgradeable,
    ISecuritizationPoolERC721Receiver,
    IERC721ReceiverUpgradeable
{
    using ConfigHelper for Registry;

    //ERC721 Assets
    NFTAsset[] internal _nftAssets;
    address[] internal _tokenAssetAddresses;
    mapping(address => bool) internal _existsTokenAssetAddress;

    uint256 internal _amountOwedToOriginator;
    uint64 internal _firstAssetTimestamp;

    function nftAssets(uint256 index) external view returns (NFTAsset memory) {
        return _nftAssets[index];
    }

    function getNFTAssetsLength() public view override returns (uint256) {
        return _nftAssets.length;
    }

    constructor() {
        _disableInitializers();
    }

    // /** CONSTRUCTOR */
    // function initialize(
    //     Registry _registry,
    //     address _currency,
    //     uint32 _minFirstLossCushion
    // ) public override initializer {
    //     require(_minFirstLossCushion < 100 * RATE_SCALING_FACTOR, 'minFirstLossCushion is greater than 100');
    //     require(_currency != address(0), 'SecuritizationPool: Invalid currency');
    //     __UntangledBase__init(_msgSender());

    //     _setRoleAdmin(ORIGINATOR_ROLE, OWNER_ROLE);
    //     registry = _registry;

    //     state = CycleState.INITIATED;
    //     underlyingCurrency = _currency;
    //     minFirstLossCushion = _minFirstLossCushion;

    //     pot = address(this);
    //     require(
    //         IERC20Upgradeable(_currency).approve(pot, type(uint256).max),
    //         'SecuritizationPool: Currency approval failed'
    //     );
    //     registry.getLoanAssetToken().setApprovalForAll(address(registry.getLoanKernel()), true);
    // }

    function getTokenAssetAddresses(uint256 index) public view override returns (address) {
        return _tokenAssetAddresses[index];
    }

    function getTokenAssetAddressesLength() public view override returns (uint256) {
        return _tokenAssetAddresses.length;
    }

    /** UTILITY FUNCTION */
    function _removeNFTAsset(address tokenAddress, uint256 tokenId) private returns (bool) {
        uint256 nftAssetsLength = _nftAssets.length;
        for (uint256 i = 0; i < nftAssetsLength; i = UntangledMath.uncheckedInc(i)) {
            if (_nftAssets[i].tokenAddress == tokenAddress && _nftAssets[i].tokenId == tokenId) {
                // Remove i element from nftAssets
                _removeNFTAssetIndex(i);
                return true;
            }
        }

        return false;
    }

    function _removeNFTAssetIndex(uint256 indexToRemove) private {
        _nftAssets[indexToRemove] = _nftAssets[_nftAssets.length - 1];

        NFTAsset storage nft = _nftAssets[_nftAssets.length - 1];
        emit RemoveNFTAsset(nft.tokenAddress, nft.tokenId);
        _nftAssets.pop();
    }

    function _pushTokenAssetAddress(address tokenAddress) private {
        if (!_existsTokenAssetAddress[tokenAddress]) _tokenAssetAddresses.push(tokenAddress);
        _existsTokenAssetAddress[tokenAddress] = true;
        emit AddTokenAssetAddress(tokenAddress);
    }

    function _exportAssets(address tokenAddress, address toPoolAddress, uint256[] calldata tokenIds) internal {
        uint256 tokenIdsLength = tokenIds.length;
        for (uint256 i = 0; i < tokenIdsLength; i = UntangledMath.uncheckedInc(i)) {
            require(_removeNFTAsset(tokenAddress, tokenIds[i]), 'SecuritizationPool: Asset does not exist');
        }

        for (uint256 i = 0; i < tokenIdsLength; i = UntangledMath.uncheckedInc(i)) {
            IUntangledERC721(tokenAddress).safeTransferFrom(address(this), toPoolAddress, tokenIds[i]);
        }
    }

    function _withdrawAssets(
        address[] calldata tokenAddresses,
        uint256[] calldata tokenIds,
        address[] calldata recipients
    ) internal {
        uint256 tokenIdsLength = tokenIds.length;
        require(tokenAddresses.length == tokenIdsLength, 'tokenAddresses length and tokenIds length are not equal');
        require(
            tokenAddresses.length == recipients.length,
            'tokenAddresses length and recipients length are not equal'
        );

        for (uint256 i = 0; i < tokenIdsLength; i = UntangledMath.uncheckedInc(i)) {
            require(_removeNFTAsset(tokenAddresses[i], tokenIds[i]), 'SecuritizationPool: Asset does not exist');
        }
        for (uint256 i = 0; i < tokenIdsLength; i = UntangledMath.uncheckedInc(i)) {
            IUntangledERC721(tokenAddresses[i]).safeTransferFrom(address(this), recipients[i], tokenIds[i]);
        }
    }

    /**
     *
     * @param tokenAddress tokenAddress of the NFT
     * @param from owner of NFT
     * @param tokenIds list of asset
     *
     * @return uint256 expectedAssetsValue
     */
    function _collectAssets(
        address tokenAddress,
        address from,
        uint256[] calldata tokenIds
    ) internal returns (uint256) {
        uint256 tokenIdsLength = tokenIds.length;
        for (uint256 i = 0; i < tokenIdsLength; i = UntangledMath.uncheckedInc(i)) {
            IUntangledERC721(tokenAddress).safeTransferFrom(from, address(this), tokenIds[i]);
        }

        uint256 expectedAssetsValue = 0;
        ISecuritizationPoolValueService poolService = valueService();
        for (uint256 i = 0; i < tokenIdsLength; i = UntangledMath.uncheckedInc(i)) {
            expectedAssetsValue =
                expectedAssetsValue +
                poolService.getExpectedAssetValue(address(this), tokenAddress, tokenIds[i], block.timestamp);
        }

        if (_firstAssetTimestamp == 0) {
            _touchFirstAssetTimestamp();
        }

        emit CollectAsset(from, expectedAssetsValue);

        return expectedAssetsValue;
    }

    function onERC721Received(address, address, uint256 tokenId, bytes memory) external returns (bytes4) {
        address token = _msgSender();
        require(
            token == address(acceptedInvoiceToken()) || token == address(loanAssetToken()),
            'SecuritizationPool: Must be token issued by Untangled'
        );
        _nftAssets.push(NFTAsset({tokenAddress: token, tokenId: tokenId}));
        emit InsertNFTAsset(token, tokenId);

        return this.onERC721Received.selector;
    }

    function acceptedInvoiceToken() public view virtual override returns (address);

    function loanAssetToken() public view virtual override returns (address);

    function valueService() public view virtual override returns (ISecuritizationPoolValueService);

    function firstAssetTimestamp() public view virtual override returns (uint64) {
        return _firstAssetTimestamp;
    }

    function _touchFirstAssetTimestamp() internal virtual {
        _firstAssetTimestamp = uint64(block.timestamp);
        emit UpdateFirstAssetTimestamp(_firstAssetTimestamp);
    }

    uint256[50] private __gap;
}
