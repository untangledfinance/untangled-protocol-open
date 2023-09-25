// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import '../storage/Registry.sol';
import '../base/UntangledBase.sol';

abstract contract ISecuritizationPool is UntangledBase {
    Registry public registry;

    bytes32 public constant ORIGINATOR_ROLE = keccak256('ORIGINATOR_ROLE');
    uint256 public constant RATE_SCALING_FACTOR = 10**4;

    address public tgeAddress;
    address public secondTGEAddress;
    address public sotToken;
    address public jotToken;
    address public underlyingCurrency;

    //CycleState
    CycleState public state;

    uint64 public openingBlockTimestamp;
    uint64 public termLengthInSeconds;

    uint256 public reserve; // Money in pool
    uint256 public totalRedeemedCurrency; // Total $ (cUSD) has been redeemed
    // for lending operation
    uint256 public totalLockedDistributeBalance;
    // token address -> total locked
    mapping(address => uint256) public totalLockedRedeemBalances;
    // token address -> user -> locked
    mapping(address => mapping(address => uint256)) public lockedDistributeBalances;
    mapping(address => mapping(address => uint256)) public lockedRedeemBalances;

    uint256 public totalAssetRepaidCurrency; // Total $ (cUSD) paid for Asset repayment - repayInBatch

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

    /// @notice A view function that returns the length of the NFT (non-fungible token) assets array
    function getNFTAssetsLength() public view virtual returns (uint256);

    /// @notice A view function that returns an array of token asset addresses
    function getTokenAssetAddresses() public view virtual returns (address[] memory);

    /// @notice A view function that returns the length of the token asset addresses array
    function getTokenAssetAddressesLength() public view virtual returns (uint256);

    /// @notice Riks scores length
    /// @return the length of the risk scores array
    function getRiskScoresLength() public view virtual returns (uint256);

    /// @notice checks if the contract is in a closed state
    function isClosedState() public view virtual returns (bool);

    /// @notice checks if the redemption process has finished
    function hasFinishedRedemption() public view virtual returns (bool);

    /// @notice sets the pot address for the contract
    function setPot(address _pot) external virtual;

    /// @notice sets up the risk scores for the contract for pool
    function setupRiskScores(
        uint32[] calldata _daysPastDues,
        uint32[] calldata _ratesAndDefaults,
        uint32[] calldata _periodsAndWriteOffs
    ) external virtual;

    /// @notice exports NFT assets to another pool address
    function exportAssets(
        address tokenAddress,
        address toPoolAddress,
        uint256[] calldata tokenIds
    ) external virtual;

    /// @notice withdraws NFT assets from the contract and transfers them to recipients
    function withdrawAssets(
        address[] calldata tokenAddresses,
        uint256[] calldata tokenIds,
        address[] calldata recipients
    ) external virtual;

    /// @notice collects NFT assets from a specified address
    function collectAssets(
        address tokenAddress,
        address from,
        uint256[] calldata tokenIds
    ) external virtual;

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

    /// @notice transfers the remaining cash to a specified recipient wallet
    function claimCashRemain(address recipientWallet) external virtual;

    /// @notice injects the address of the Token Generation Event (TGE) and the associated token address
    function injectTGEAddress(
        address _tgeAddress,
        address _tokenAddress,
        Configuration.NOTE_TOKEN_TYPE _noteToken
    ) external virtual;

    /// @notice starts a new cycle and sets various parameters for the contract
    function startCycle(
        uint64 _termLengthInSeconds,
        uint256 _principalAmountForSOT,
        uint32 _interestRateForSOT,
        uint64 _timeStartEarningInterest
    ) external virtual;

    /// @notice sets the interest rate for the senior tranche of tokens
    function setInterestRateForSOT(uint32 _interestRateSOT) external virtual;

    /// @notice increases the locked distribution balance for a specific investor
    function increaseLockedDistributeBalance(
        address tokenAddress,
        address investor,
        uint256 currency,
        uint256 token
    ) external virtual;

    /// @dev trigger update asset value repaid
    function increaseTotalAssetRepaidCurrency(uint256 amount) external virtual;

    /// @notice decreases the locked distribution balance for a specific investor
    function decreaseLockedDistributeBalance(
        address tokenAddress,
        address investor,
        uint256 currency,
        uint256 token
    ) external virtual;

    /// @notice allows the redemption of tokens
    function redeem(
        address usr,
        address notesToken,
        uint256 currencyAmount,
        uint256 tokenAmount
    ) external virtual;

    /// @notice allows the originator to withdraw from reserve
    function withdraw(uint256 amount) public virtual;

    /// @dev trigger update reserve when buy note token action happens
    function onBuyNoteToken(uint256 currencyAmount) external virtual;

    uint256[22] private __gap;
}
