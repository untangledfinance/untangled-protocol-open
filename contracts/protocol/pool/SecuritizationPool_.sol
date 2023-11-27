// // SPDX-License-Identifier: MIT
// pragma solidity 0.8.19;

// import {AccessControlEnumerableUpgradeable} from '@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol';
// import {ERC165Upgradeable} from '@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol';
// import {IERC20Upgradeable} from '@openzeppelin/contracts-upgradeable/interfaces/IERC20Upgradeable.sol';
// import {ERC20BurnableUpgradeable} from '@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol';
// import {IERC721ReceiverUpgradeable} from '@openzeppelin/contracts-upgradeable/interfaces/IERC721ReceiverUpgradeable.sol';
// import {IAccessControlUpgradeable} from '@openzeppelin/contracts-upgradeable/access/IAccessControlUpgradeable.sol';
// import {PausableUpgradeable} from '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';

// import {IUntangledERC721} from '../../interfaces/IUntangledERC721.sol';
// import {INoteToken} from '../../interfaces/INoteToken.sol';
// import {ICrowdSale} from '../note-sale/crowdsale/ICrowdSale.sol';

// import {ISecuritizationPool} from './ISecuritizationPool.sol';
// import {IPoolNAV} from './IPoolNAV.sol';
// import {ISecuritizationPoolValueService} from './ISecuritizationPoolValueService.sol';

// import {MintedIncreasingInterestTGE} from '../note-sale/MintedIncreasingInterestTGE.sol';
// import {ConfigHelper} from '../../libraries/ConfigHelper.sol';
// import {Configuration} from '../../libraries/Configuration.sol';
// import {UntangledMath} from '../../libraries/UntangledMath.sol';
// import {Registry} from '../../storage/Registry.sol';
// import {IPoolNAVFactory} from "./IPoolNAVFactory.sol";
// import {FinalizableCrowdsale} from './../note-sale/crowdsale/FinalizableCrowdsale.sol';
// import {POOL_ADMIN, ORIGINATOR_ROLE, RATE_SCALING_FACTOR} from './types.sol';

// import {ISecuritizationLockDistribution} from './ISecuritizationLockDistribution.sol';
// import {SecuritizationLockDistribution} from './SecuritizationLockDistribution.sol';
// import {SecuritizationTGE} from './SecuritizationTGE.sol';
// import {ISecuritizationTGE} from './ISecuritizationTGE.sol';
// import {RegistryInjection} from './RegistryInjection.sol';

// import {SecuritizationAccessControl} from './SecuritizationAccessControl.sol';
// import {ISecuritizationAccessControl} from './ISecuritizationAccessControl.sol';

// import {RiskScore} from './base/types.sol';

// // TODO A @KhanhPham Upgrade this
// /**
//  * @title Untangled's SecuritizationPool contract
//  * @notice Main entry point for senior LPs (a.k.a. capital providers)
//  *  Automatically invests across borrower pools using an adjustable strategy.
//  * @author Untangled Team
//  */
// contract SecuritizationPool is
//     RegistryInjection,
//     ERC165Upgradeable,
//     SecuritizationAccessControl,
//     ISecuritizationPool,
//     SecuritizationLockDistribution,
//     SecuritizationTGE,
//     IERC721ReceiverUpgradeable
// {
//     using ConfigHelper for Registry;

//     // keccak256(abi.encode(uint256(keccak256("untangled.storage.SecuritizationPool")) - 1)) & ~bytes32(uint256(0xff))
//     bytes32 private constant SecuritizationPoolStorageLocation =
//         0x7b312f85bcf71b947c1556b37514c7da9b615474a5e6d949d429b3b529966500;

//     /// @custom:storage-location erc7201:untangled.storage.SecuritizationPool
//     struct SecuritizationPoolStorage {
//         uint64 firstAssetTimestamp;
//         RiskScore[] riskScores;
//         NFTAsset[] nftAssets;
//         address[] tokenAssetAddresses;
//         mapping(address => bool) existsTokenAssetAddress;
//         bool validatorRequired;
//     }

//     function _getSecuritizationPoolStorage() private pure returns (SecuritizationPoolStorage storage $) {
//         assembly {
//             $.slot := SecuritizationPoolStorageLocation
//         }
//     }

//     constructor() {
//         _disableInitializers();
//     }

//     /** CONSTRUCTOR */
//     function initialize(
//         Registry registry_,
//         bytes memory params
//     )
//         public
//         // address _currency,
//         // uint32 _minFirstLossCushion
//         initializer
//     {
//         ISecuritizationPool.NewPoolParams memory newPoolParams = abi.decode(
//             params,
//             (ISecuritizationPool.NewPoolParams)
//         );

//         require(
//             newPoolParams.minFirstLossCushion < 100 * RATE_SCALING_FACTOR,
//             'minFirstLossCushion is greater than 100'
//         );
//         require(newPoolParams.currency != address(0), 'SecuritizationPool: Invalid currency');

//         __SecuritizationAccessControl_init_unchained(_msgSender());
//         // __UntangledBase__init(_msgSender());

//         // _setRoleAdmin(ORIGINATOR_ROLE, OWNER_ROLE);
//         _setRegistry(registry_);

//         __SecuritizationTGE_init_unchained(
//             address(this),
//             ISecuritizationTGE.CycleState.INITIATED,
//             newPoolParams.currency,
//             newPoolParams.minFirstLossCushion
//         );

//         _getSecuritizationPoolStorage().validatorRequired = newPoolParams.validatorRequired;

//         require(
//             IERC20Upgradeable(newPoolParams.currency).approve(pot(), type(uint256).max),
//             'SecuritizationPool: Currency approval failed'
//         );
//         registry().getLoanAssetToken().setApprovalForAll(address(registry().getLoanKernel()), true);
//     }

//     /** GETTER */
//     function getNFTAssetsLength() public view override returns (uint256) {
//         return _getSecuritizationPoolStorage().nftAssets.length;
//     }

//     function getTokenAssetAddresses() public view override returns (address[] memory) {
//         return _getSecuritizationPoolStorage().tokenAssetAddresses;
//     }

//     function getTokenAssetAddressesLength() public view override returns (uint256) {
//         return _getSecuritizationPoolStorage().tokenAssetAddresses.length;
//     }

//     function getRiskScoresLength() public view override returns (uint256) {
//         return _getSecuritizationPoolStorage().riskScores.length;
//     }

//     // function hasFinishedRedemption() public view override returns (bool) {
//     //     if (sotToken != address(0)) {
//     //         require(IERC20Upgradeable(sotToken).totalSupply() == 0, 'SecuritizationPool: SOT still remain');
//     //     }
//     //     if (jotToken != address(0)) {
//     //         require(IERC20Upgradeable(jotToken).totalSupply() == 0, 'SecuritizationPool: JOT still remain');
//     //     }

//     //     return true;
//     // }

//     /** UTILITY FUNCTION */
//     function _removeNFTAsset(address tokenAddress, uint256 tokenId) private returns (bool) {
//         NFTAsset[] storage _nftAssets = _getSecuritizationPoolStorage().nftAssets;
//         uint256 nftAssetsLength = _nftAssets.length;
//         for (uint256 i = 0; i < nftAssetsLength; i = UntangledMath.uncheckedInc(i)) {
//             if (_nftAssets[i].tokenAddress == tokenAddress && _nftAssets[i].tokenId == tokenId) {
//                 // Remove i element from nftAssets
//                 _removeNFTAssetIndex(i);
//                 return true;
//             }
//         }

//         return false;
//     }

//     function _removeNFTAssetIndex(uint256 indexToRemove) private {
//         NFTAsset[] storage _nftAssets = _getSecuritizationPoolStorage().nftAssets;

//         _nftAssets[indexToRemove] = _nftAssets[_nftAssets.length - 1];

//         NFTAsset storage nft = _nftAssets[_nftAssets.length - 1];
//         emit RemoveNFTAsset(nft.tokenAddress, nft.tokenId);
//         _nftAssets.pop();
//     }

//     function _pushTokenAssetAddress(address tokenAddress) private {
//         SecuritizationPoolStorage storage $ = _getSecuritizationPoolStorage();

//         if (!$.existsTokenAssetAddress[tokenAddress]) $.tokenAssetAddresses.push(tokenAddress);
//         $.existsTokenAssetAddress[tokenAddress] = true;
//         emit AddTokenAssetAddress(tokenAddress);
//     }

//     function onERC721Received(address, address, uint256 tokenId, bytes memory) external returns (bytes4) {
//         address token = _msgSender();
//         require(
//             token == address(registry().getLoanAssetToken()),
//             'SecuritizationPool: Must be token issued by Untangled'
//         );
//         NFTAsset[] storage _nftAssets = _getSecuritizationPoolStorage().nftAssets;
//         _nftAssets.push(NFTAsset({tokenAddress: token, tokenId: tokenId}));
//         emit InsertNFTAsset(token, tokenId);

//         return this.onERC721Received.selector;
//     }

//     /// @inheritdoc ISecuritizationPool
//     function setupRiskScores(
//         uint32[] calldata _daysPastDues,
//         uint32[] calldata _ratesAndDefaults,
//         uint32[] calldata _periodsAndWriteOffs
//     ) external override whenNotPaused notClosingStage {
//         registry().requirePoolAdmin(_msgSender());

//         uint256 _daysPastDuesLength = _daysPastDues.length;
//         require(
//             _daysPastDuesLength * 6 == _ratesAndDefaults.length &&
//                 _daysPastDuesLength * 4 == _periodsAndWriteOffs.length,
//             'SecuritizationPool: Riskscore params length is not equal'
//         );

//         SecuritizationPoolStorage storage $ = _getSecuritizationPoolStorage();
//         delete $.riskScores;

//         for (uint256 i = 0; i < _daysPastDuesLength; i = UntangledMath.uncheckedInc(i)) {
//             require(
//                 i == 0 || _daysPastDues[i] > _daysPastDues[i - 1],
//                 'SecuritizationPool: Risk scores must be sorted'
//             );
//             uint32 _interestRate = _ratesAndDefaults[i + _daysPastDuesLength * 2];
//             uint32 _writeOffAfterGracePeriod = _periodsAndWriteOffs[i + _daysPastDuesLength * 2];
//             uint32 _writeOffAfterCollectionPeriod = _periodsAndWriteOffs[i + _daysPastDuesLength * 3];
//             $.riskScores.push(
//                 RiskScore({
//                     daysPastDue: _daysPastDues[i],
//                     advanceRate: _ratesAndDefaults[i],
//                     penaltyRate: _ratesAndDefaults[i + _daysPastDuesLength],
//                     interestRate: _interestRate,
//                     probabilityOfDefault: _ratesAndDefaults[i + _daysPastDuesLength * 3],
//                     lossGivenDefault: _ratesAndDefaults[i + _daysPastDuesLength * 4],
//                     discountRate: _ratesAndDefaults[i + _daysPastDuesLength * 5],
//                     gracePeriod: _periodsAndWriteOffs[i],
//                     collectionPeriod: _periodsAndWriteOffs[i + _daysPastDuesLength],
//                     writeOffAfterGracePeriod: _writeOffAfterGracePeriod,
//                     writeOffAfterCollectionPeriod: _periodsAndWriteOffs[i + _daysPastDuesLength * 3]
//                 })
//             );
//             IPoolNAV(poolNAV()).file("writeOffGroup", _interestRate, _writeOffAfterGracePeriod, _periodsAndWriteOffs[i], _ratesAndDefaults[i + _daysPastDuesLength], i);
//             IPoolNAV(poolNAV()).file("writeOffGroup", _interestRate, _writeOffAfterCollectionPeriod, _periodsAndWriteOffs[i + _daysPastDuesLength], _ratesAndDefaults[i + _daysPastDuesLength], i);
//         }

//         // Set discount rate
//         IPoolNAV(poolNAV()).file("discountRate", $.riskScores[0].discountRate);
//     }

//     /// @inheritdoc ISecuritizationPool
//     function exportAssets(
//         address tokenAddress,
//         address toPoolAddress,
//         uint256[] calldata tokenIds
//     ) external override whenNotPaused nonReentrant notClosingStage {
//         registry().requirePoolAdminOrOwner(address(this), _msgSender());

//         uint256 tokenIdsLength = tokenIds.length;
//         for (uint256 i = 0; i < tokenIdsLength; i = UntangledMath.uncheckedInc(i)) {
//             require(_removeNFTAsset(tokenAddress, tokenIds[i]), 'SecuritizationPool: Asset does not exist');
//         }

//         for (uint256 i = 0; i < tokenIdsLength; i = UntangledMath.uncheckedInc(i)) {
//             IUntangledERC721(tokenAddress).safeTransferFrom(address(this), toPoolAddress, tokenIds[i]);
//         }
//     }

//     /// @inheritdoc ISecuritizationPool
//     function withdrawAssets(
//         address[] calldata tokenAddresses,
//         uint256[] calldata tokenIds,
//         address[] calldata recipients
//     ) external override whenNotPaused nonReentrant onlyOwner {
//         uint256 tokenIdsLength = tokenIds.length;
//         require(tokenAddresses.length == tokenIdsLength, 'tokenAddresses length and tokenIds length are not equal');
//         require(
//             tokenAddresses.length == recipients.length,
//             'tokenAddresses length and recipients length are not equal'
//         );

//         for (uint256 i = 0; i < tokenIdsLength; i = UntangledMath.uncheckedInc(i)) {
//             require(_removeNFTAsset(tokenAddresses[i], tokenIds[i]), 'SecuritizationPool: Asset does not exist');
//         }
//         for (uint256 i = 0; i < tokenIdsLength; i = UntangledMath.uncheckedInc(i)) {
//             IUntangledERC721(tokenAddresses[i]).safeTransferFrom(address(this), recipients[i], tokenIds[i]);
//         }
//     }

//     /// @inheritdoc ISecuritizationPool
//     function collectAssets(
//         uint256[] calldata tokenIds
//     ) external override whenNotPaused {
//         registry().requireLoanKernel(_msgSender());
//         uint256 tokenIdsLength = tokenIds.length;
//         uint256 expectedAssetsValue = 0;
//         for (uint256 i = 0; i < tokenIdsLength; i = UntangledMath.uncheckedInc(i)) {
//             IPoolNAV(poolNAV()).addLoan(tokenIds[i]);
//             expectedAssetsValue =
//                 expectedAssetsValue + IPoolNAV(poolNAV()).debt(tokenIds[i]);
//         }
//         _setAmountOwedToOriginator(amountOwedToOriginator() + expectedAssetsValue);

//         SecuritizationPoolStorage storage $ = _getSecuritizationPoolStorage();
//         if (firstAssetTimestamp() == 0) {
//             $.firstAssetTimestamp = uint64(block.timestamp);
//             _setUpOpeningBlockTimestamp();
//         }
//         if (openingBlockTimestamp() == 0) {
//             // If openingBlockTimestamp is not set
//             _setOpeningBlockTimestamp(openingBlockTimestamp());
//         }

//         emit CollectAsset(expectedAssetsValue);
//     }

//     // /// @inheritdoc ISecuritizationPool
//     // function withdraw(uint256 amount) public override whenNotPaused onlyRole(ORIGINATOR_ROLE) {
//     //     uint256 _amountOwedToOriginator = amountOwedToOriginator;
//     //     if (amount <= _amountOwedToOriginator) {
//     //         amountOwedToOriginator = _amountOwedToOriginator - amount;
//     //     } else {
//     //         amountOwedToOriginator = 0;
//     //     }
//     //     reserve = reserve - amount;

//     //     require(checkMinFirstLost(), 'MinFirstLoss is not satisfied');
//     //     require(
//     //         IERC20Upgradeable(underlyingCurrency).transferFrom(pot, _msgSender(), amount),
//     //         'SecuritizationPool: Transfer failed'
//     //     );
//     //     emit Withdraw(_msgSender(), amount);
//     // }

//     // function checkMinFirstLost() public view returns (bool) {
//     //     ISecuritizationPoolValueService poolService = registry().getSecuritizationPoolValueService();
//     //     return minFirstLossCushion <= poolService.getJuniorRatio(address(this));
//     // }

//     /// @inheritdoc ISecuritizationPool
//     function collectERC20Assets(
//         address[] calldata tokenAddresses,
//         address[] calldata senders,
//         uint256[] calldata amounts
//     ) external override whenNotPaused notClosingStage onlyRole(ORIGINATOR_ROLE) {
//         uint256 tokenAddressesLength = tokenAddresses.length;
//         require(
//             tokenAddressesLength == senders.length && senders.length == amounts.length,
//             'SecuritizationPool: Params length are not equal'
//         );

//         // check
//         for (uint256 i = 0; i < tokenAddressesLength; i = UntangledMath.uncheckedInc(i)) {
//             require(
//                 registry().getNoteTokenFactory().isExistingTokens(tokenAddresses[i]),
//                 'SecuritizationPool: unknown-token-address'
//             );
//         }

//         for (uint256 i = 0; i < tokenAddressesLength; i = UntangledMath.uncheckedInc(i)) {
//             _pushTokenAssetAddress(tokenAddresses[i]);
//         }

//         for (uint256 i = 0; i < tokenAddressesLength; i = UntangledMath.uncheckedInc(i)) {
//             require(
//                 IERC20Upgradeable(tokenAddresses[i]).transferFrom(senders[i], address(this), amounts[i]),
//                 'SecuritizationPool: Transfer failed'
//             );
//         }

//         if (openingBlockTimestamp() == 0) {
//             // If openingBlockTimestamp is not set
//             _setOpeningBlockTimestamp(uint64(block.timestamp));
//         }
//     }

//     /// @inheritdoc ISecuritizationPool
//     function withdrawERC20Assets(
//         address[] calldata tokenAddresses,
//         address[] calldata recipients,
//         uint256[] calldata amounts
//     ) external override whenNotPaused nonReentrant {
//         registry().requirePoolAdminOrOwner(address(this), _msgSender());

//         uint256 tokenAddressesLength = tokenAddresses.length;
//         require(tokenAddressesLength == recipients.length, 'tokenAddresses length and tokenIds length are not equal');
//         require(tokenAddressesLength == amounts.length, 'tokenAddresses length and recipients length are not equal');

//         mapping(address => bool) storage existsTokenAssetAddress = _getSecuritizationPoolStorage()
//             .existsTokenAssetAddress;
//         for (uint256 i = 0; i < tokenAddressesLength; i = UntangledMath.uncheckedInc(i)) {
//             require(existsTokenAssetAddress[tokenAddresses[i]], 'SecuritizationPool: note token asset does not exist');
//             require(
//                 IERC20Upgradeable(tokenAddresses[i]).transfer(recipients[i], amounts[i]),
//                 'SecuritizationPool: Transfer failed'
//             );
//         }
//     }

//     function firstAssetTimestamp() public view returns (uint64) {
//         return _getSecuritizationPoolStorage().firstAssetTimestamp;
//     }

//     // /// @inheritdoc ISecuritizationPool
//     // function startCycle(
//     //     uint64 _termLengthInSeconds,
//     //     uint256 _principalAmountForSOT,
//     //     uint32 _interestRateForSOT,
//     //     uint64 _timeStartEarningInterest
//     // ) external override whenNotPaused nonReentrant onlyOwner onlyIssuingTokenStage {
//     //     require(_termLengthInSeconds > 0, 'SecuritizationPool: Term length is 0');

//     //     termLengthInSeconds = _termLengthInSeconds;

//     //     principalAmountSOT = _principalAmountForSOT;

//     //     state = CycleState.OPEN;

//     //     if (tgeAddress != address(0)) {
//     //         MintedIncreasingInterestTGE mintedTokenGenrationEvent = MintedIncreasingInterestTGE(tgeAddress);
//     //         mintedTokenGenrationEvent.setupLongSale(
//     //             _interestRateForSOT,
//     //             _termLengthInSeconds,
//     //             _timeStartEarningInterest
//     //         );
//     //         if (!mintedTokenGenrationEvent.finalized()) {
//     //             mintedTokenGenrationEvent.finalize(false, pot);
//     //         }
//     //         interestRateSOT = mintedTokenGenrationEvent.pickedInterest();
//     //     }
//     //     if (secondTGEAddress != address(0)) {
//     //         FinalizableCrowdsale(secondTGEAddress).finalize(false, pot);
//     //         require(
//     //             MintedIncreasingInterestTGE(secondTGEAddress).finalized(),
//     //             'SecuritizationPool: second sale is still on going'
//     //         );
//     //     }
//     // }

//     /// @inheritdoc ISecuritizationPool
//     function setUpOpeningBlockTimestamp() public override whenNotPaused {
//         require(_msgSender() == tgeAddress(), 'SecuritizationPool: Only tge address');
//         _setUpOpeningBlockTimestamp();
//     }


//     /// @dev Set the opening block timestamp
//     function _setUpOpeningBlockTimestamp() private {
//         if (tgeAddress() == address(0)) return;
//         uint64 _firstNoteTokenMintedTimestamp = ICrowdSale(tgeAddress()).firstNoteTokenMintedTimestamp();
//         uint64 _firstAssetTimestamp = firstAssetTimestamp();
//         if (_firstNoteTokenMintedTimestamp > 0 && _firstAssetTimestamp > 0) {
//             // Pick the later
//             if (_firstAssetTimestamp > _firstNoteTokenMintedTimestamp) {
//                 _setOpeningBlockTimestamp(_firstAssetTimestamp);
//             } else {
//                 _setOpeningBlockTimestamp(_firstNoteTokenMintedTimestamp);
//             }
//         }

//         emit UpdateOpeningBlockTimestamp(openingBlockTimestamp());
//     }

//     function pause() public virtual override {
//         registry().requirePoolAdminOrOwner(address(this), _msgSender());
//         _pause();
//     }

//     function unpause() public virtual override {
//         registry().requirePoolAdminOrOwner(address(this), _msgSender());
//         _unpause();
//     }

//     function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
//         return
//             ERC165Upgradeable.supportsInterface(interfaceId) ||
//             interfaceId == type(ISecuritizationPool).interfaceId ||
//             interfaceId == type(ISecuritizationTGE).interfaceId ||
//             interfaceId == type(ISecuritizationLockDistribution).interfaceId ||
//             interfaceId == type(ISecuritizationAccessControl).interfaceId;
//     }

//     function riskScores(uint256 idx) public view virtual override returns (RiskScore memory) {
//         return _getSecuritizationPoolStorage().riskScores[idx];
//     }

//     function nftAssets(uint256 idx) public view virtual override returns (NFTAsset memory) {
//         return _getSecuritizationPoolStorage().nftAssets[idx];
//     }

//     function tokenAssetAddresses(uint256 idx) public view virtual override returns (address) {
//         return _getSecuritizationPoolStorage().tokenAssetAddresses[idx];
//     }

//     function validatorRequired() public view virtual override returns (bool) {
//         return _getSecuritizationPoolStorage().validatorRequired;
//     }

//     uint256[50] private __gap;
// }
