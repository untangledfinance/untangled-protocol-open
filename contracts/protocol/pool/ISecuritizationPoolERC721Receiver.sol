// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

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

/**
 * @title Untangled's SecuritizationPool contract
 * @notice Main entry point for senior LPs (a.k.a. capital providers)
 *  Automatically invests across borrower pools using an adjustable strategy.
 * @author Untangled Team
 */
interface ISecuritizationPoolERC721Receiver {
    struct NFTAsset {
        address tokenAddress;
        uint256 tokenId;
    }

    event InsertNFTAsset(address token, uint256 tokenId);
    event RemoveNFTAsset(address token, uint256 tokenId);
    event AddTokenAssetAddress(address token);
    event CollectAsset(address from, uint256 value);
    event UpdateFirstAssetTimestamp(uint64 newTimestamp);

    /**
     * @param index The index of the NFT
     */
    function nftAssets(uint256 index) external view returns (NFTAsset memory);

    /**
     * @notice Get the total number of NFT assets
     * @return The total number of NFT assets
     */
    function getNFTAssetsLength() external view returns (uint256);

    function acceptedInvoiceToken() external view returns (address);

    function loanAssetToken() external view returns (address);

    function valueService() external view returns (ISecuritizationPoolValueService);

    function firstAssetTimestamp() external view returns (uint64);

    // function tokenAssetAddresses(uint256 index) external view returns (address);

    function getTokenAssetAddresses(uint256 index) external view returns (address);

    function getTokenAssetAddressesLength() external view returns (uint256);
}
