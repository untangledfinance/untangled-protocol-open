// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import '../../storage/Registry.sol';

import {RiskScore} from './base/types.sol';

abstract contract ISecuritizationPool {
    event CollectAsset(address from, uint256 value);
    // event UpdateOpeningBlockTimestamp(uint256 newTimestamp);
    event AddTokenAssetAddress(address token);
    event InsertNFTAsset(address token, uint256 tokenId);
    event RemoveNFTAsset(address token, uint256 tokenId);

    struct NewPoolParams {
        address currency;
        uint32 minFirstLossCushion;
        bool validatorRequired;
    }

    /** ENUM & STRUCT */

    struct NFTAsset {
        address tokenAddress;
        uint256 tokenId;
    }

    /// @notice A view function that returns the length of the NFT (non-fungible token) assets array
    function getNFTAssetsLength() public view virtual returns (uint256);

    /// @notice A view function that returns an array of token asset addresses
    function getTokenAssetAddresses() public view virtual returns (address[] memory);

    /// @notice A view function that returns the length of the token asset addresses array
    function getTokenAssetAddressesLength() public view virtual returns (uint256);

    /// @notice Riks scores length
    /// @return the length of the risk scores array
    function getRiskScoresLength() public view virtual returns (uint256);

    function riskScores(uint256 index) public view virtual returns (RiskScore memory);

    /// @notice sets up the risk scores for the contract for pool
    function setupRiskScores(
        uint32[] calldata _daysPastDues,
        uint32[] calldata _ratesAndDefaults,
        uint32[] calldata _periodsAndWriteOffs
    ) external virtual;

    /// @notice exports NFT assets to another pool address
    function exportAssets(address tokenAddress, address toPoolAddress, uint256[] calldata tokenIds) external virtual;

    /// @notice withdraws NFT assets from the contract and transfers them to recipients
    function withdrawAssets(
        address[] calldata tokenAddresses,
        uint256[] calldata tokenIds,
        address[] calldata recipients
    ) external virtual;

    /// @notice collects NFT assets from a specified address
    function collectAssets(address tokenAddress, address from, uint256[] calldata tokenIds) external virtual;

    /// @notice collects ERC20 assets from specified senders
    function collectERC20Assets(
        address[] calldata tokenAddresses,
        address[] calldata senders,
        uint256[] calldata amounts
    ) external virtual;

    /// @notice withdraws ERC20 assets from the contract and transfers them to recipients\
    function withdrawERC20Assets(
        address[] calldata tokenAddresses,
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external virtual;

    function nftAssets(uint256 idx) public view virtual returns (NFTAsset memory);

    function tokenAssetAddresses(uint256 idx) public view virtual returns (address);

    function validatorRequired() external view virtual returns (bool);

    /// @dev Trigger set up opening block timestamp
    function setUpOpeningBlockTimestamp() external virtual;

    function pause() external virtual;

    function unpause() external virtual;
}
