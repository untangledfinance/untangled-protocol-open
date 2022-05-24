// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '../storage/Registry.sol';
import '../base/UntangledBase.sol';

abstract contract ISecuritizationPool is UntangledBase {
    Registry public registry;

    bytes32 public constant ORIGINATOR_ROLE = keccak256('ORIGINATOR_ROLE');

    address public tgeAddress;
    address public secondTGEAddress;
    address public sotToken;
    address public jotToken;
    address public underlyingCurrency;

    //CycleState
    CycleState public state;

    uint64 public openingBlockTimestamp;
    uint64 public termLengthInSeconds;

    // for lending operation
    uint256 public totalLockedDistributeBalance;
    // token address -> total locked
    mapping(address => uint256) public totalLockedRedeemBalances;
    // token address -> user -> locked
    mapping(address => mapping(address => uint256)) public lockedDistributeBalances;
    mapping(address => mapping(address => uint256)) public lockedRedeemBalances;

    // user -> amount
    mapping(address => uint256) public paidInterestAmountSOT;
    mapping(address => uint256) public lastRepayTimestampSOT;

    // for base (sell-loan) operation
    uint256 public principalAmountSOT;
    uint256 public paidPrincipalAmountSOT;
    uint32 public interestRateSOT; // Annually, support 4 decimals num

    uint32 public minFirstLossCushion;

    //RiskScores
    RiskScore[] public riskScores;

    //ERC721 Assets
    NFTAsset[] public nftAssets;

    address[] public tokenAssetAddresses;
    mapping(address => bool) public existsTokenAssetAddress;

    mapping(address => uint256) public paidPrincipalAmountSOTByInvestor;

    // by default it is address(this)
    address public pot;

    /** ENUM & STRUCT */
    enum CycleState {
        INITIATED,
        CROWDSALE,
        OPEN,
        CLOSED
    }

    struct NFTAsset {
        address tokenAddress;
        uint256 tokenId;
    }

    struct RiskScore {
        uint32 daysPastDue;
        uint32 advanceRate;
        uint32 penaltyRate;
        uint32 interestRate;
        uint32 probabilityOfDefault;
        uint32 lossGivenDefault;
        uint32 gracePeriod;
        uint32 collectionPeriod;
        uint32 writeOffAfterGracePeriod;
        uint32 writeOffAfterCollectionPeriod;
    }

    function initialize(
        Registry _registry,
        address _currency,
        uint32 _minFirstLossCushion
    ) public virtual;

    /** GETTER */
    function getNFTAssetsLength() public view virtual returns (uint256);

    function getTokenAssetAddresses() public view virtual returns (address[] memory);

    function getTokenAssetAddressesLength() public view virtual returns (uint256);

    function getRiskScoresLength() public view virtual returns (uint256);

    function isClosedState() public view virtual returns (bool);

    function hasFinishedRedemption() public view virtual returns (bool);

    /** EXTERNAL */
    function setPot(address _pot) external virtual;

    function setupRiskScores(
        uint32[] calldata _daysPastDues,
        uint32[] calldata _ratesAndDefaults,
        uint32[] calldata _periodsAndWriteOffs
    ) external virtual;

    function exportAssets(
        address tokenAddress,
        address toPoolAddress,
        uint256[] calldata tokenIds
    ) external virtual;

    function withdrawAssets(
        address[] calldata tokenAddresses,
        uint256[] calldata tokenIds,
        address[] calldata recipients
    ) external virtual;

    function collectAssets(
        address tokenAddress,
        address from,
        uint256[] calldata tokenIds
    ) external virtual;

    function collectERC20Assets(
        address[] calldata tokenAddresses,
        address[] calldata senders,
        uint256[] calldata amounts
    ) external virtual;

    function withdrawERC20Assets(
        address[] calldata tokenAddresses,
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external virtual;

    function claimERC20Assets(address[] calldata tokenAddresses) external virtual;

    function claimCashRemain(address recipientWallet) external virtual;

    function injectTGEAddress(
        address _tgeAddress,
        address _tokenAddress,
        Configuration.NOTE_TOKEN_TYPE _noteToken
    ) external virtual;

    function startCycle(
        uint64 _termLengthInSeconds,
        uint256 _principalAmountForSOT,
        uint32 _interestRateForSOT,
        uint64 _timeStartEarningInterest
    ) external virtual;

    function setInterestRateForSOT(uint32 _interestRateSOT) external virtual;

    function increaseLockedDistributeBalance(
        address tokenAddress,
        address investor,
        uint256 currency,
        uint256 token
    ) external virtual;

    function decreaseLockedDistributeBalance(
        address tokenAddress,
        address investor,
        uint256 currency,
        uint256 token
    ) external virtual;

    function redeem(
        address usr,
        address notesToken,
        uint256 currencyAmount,
        uint256 tokenAmount
    ) external virtual;
}
