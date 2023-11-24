// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {ReentrancyGuardUpgradeable} from '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';
import {PausableUpgradeable} from '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import {ERC20BurnableUpgradeable} from '@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol';
import {IERC20Upgradeable} from '@openzeppelin/contracts-upgradeable/interfaces/IERC20Upgradeable.sol';
import {Registry} from '../../storage/Registry.sol';
import {ConfigHelper} from '../../libraries/ConfigHelper.sol';
import {ISecuritizationTGE} from './ISecuritizationTGE.sol';
import {Configuration} from '../../libraries/Configuration.sol';
import {ISecuritizationPoolValueService} from './ISecuritizationPoolValueService.sol';
import {RegistryInjection} from './RegistryInjection.sol';
import {SecuritizationAccessControl} from './SecuritizationAccessControl.sol';
import {IMintedTGE} from '../note-sale/IMintedTGE.sol';
import {IFinalizableCrowdsale} from '../note-sale/crowdsale/IFinalizableCrowdsale.sol';

import {ORIGINATOR_ROLE} from './types.sol';
import {IPoolNAV} from "./IPoolNAV.sol";
import {IPoolNAVFactory} from "./IPoolNAVFactory.sol";

abstract contract SecuritizationTGE is
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    RegistryInjection,
    SecuritizationAccessControl,
    ISecuritizationTGE
{
    using ConfigHelper for Registry;

    // keccak256(abi.encode(uint256(keccak256("untangled.storage.SecuritizationTGE")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant SecuritizationTGEStorageLocation =
        0x9aa74cbf2d9c11188ce95836d253f2de04aa615fe1ef8a4e5a1baf80987ca300;

    /// @custom:storage-location erc7201:untangled.storage.SecuritizationTGE
    struct SecuritizationTGEStorage {
        CycleState state;
        address tgeAddress;
        address secondTGEAddress;
        address sotToken;
        address jotToken;
        address underlyingCurrency;
        address poolNAV;
        uint256 reserve; // Money in pool
        uint32 minFirstLossCushion;
        uint64 openingBlockTimestamp;
        uint64 termLengthInSeconds;
        // by default it is address(this)
        address pot;
        // for base (sell-loan) operation
        uint256 principalAmountSOT;
        uint256 paidPrincipalAmountSOT;
        uint32 interestRateSOT; // Annually, support 4 decimals num
        uint256 totalAssetRepaidCurrency;
        mapping(address => uint256) paidPrincipalAmountSOTByInvestor;
        uint256 amountOwedToOriginator;
    }

    function _getSecuritizationTGEStorage() private pure returns (SecuritizationTGEStorage storage $) {
        assembly {
            $.slot := SecuritizationTGEStorageLocation
        }
    }

    function __SecuritizationTGE_init_unchained(
        address pot_,
        CycleState state_,
        address underlyingCurrency_,
        uint32 minFirstLossCushion_
    ) internal onlyInitializing {
        SecuritizationTGEStorage storage $ = _getSecuritizationTGEStorage();
        $.pot = pot_;
        $.state = state_;
        $.underlyingCurrency = underlyingCurrency_;
        $.minFirstLossCushion = minFirstLossCushion_;
    }

    function state() public view override returns (CycleState) {
        return _getSecuritizationTGEStorage().state;
    }

    function tgeAddress() public view override returns (address) {
        return _getSecuritizationTGEStorage().tgeAddress;
    }

    function secondTGEAddress() public view override returns (address) {
        return _getSecuritizationTGEStorage().secondTGEAddress;
    }

    function sotToken() public view override returns (address) {
        return _getSecuritizationTGEStorage().sotToken;
    }

    function jotToken() public view override returns (address) {
        return _getSecuritizationTGEStorage().jotToken;
    }

    function underlyingCurrency() public view override returns (address) {
        return _getSecuritizationTGEStorage().underlyingCurrency;
    }

    function reserve() public view override returns (uint256) {
        return _getSecuritizationTGEStorage().reserve;
    }

    function minFirstLossCushion() public view override returns (uint32) {
        return _getSecuritizationTGEStorage().minFirstLossCushion;
    }

    function openingBlockTimestamp() public view override returns (uint64) {
        return _getSecuritizationTGEStorage().openingBlockTimestamp;
    }

    function termLengthInSeconds() public view override returns (uint64) {
        return _getSecuritizationTGEStorage().termLengthInSeconds;
    }

    function pot() public view override returns (address) {
        return _getSecuritizationTGEStorage().pot;
    }

    function poolNAV() public view override returns (address) {
        return _getSecuritizationTGEStorage().poolNAV;
    }

    function paidPrincipalAmountSOT() public view override returns (uint256) {
        return _getSecuritizationTGEStorage().paidPrincipalAmountSOT;
    }

    function principalAmountSOT() public view override returns (uint256) {
        return _getSecuritizationTGEStorage().principalAmountSOT;
    }

    function interestRateSOT() public view override returns (uint32) {
        return _getSecuritizationTGEStorage().interestRateSOT;
    }

    function paidPrincipalAmountSOTByInvestor(address user) public view override returns (uint256) {
        return _getSecuritizationTGEStorage().paidPrincipalAmountSOTByInvestor[user];
    }

    function totalAssetRepaidCurrency() public view override returns (uint256) {
        return _getSecuritizationTGEStorage().totalAssetRepaidCurrency;
    }

    function amountOwedToOriginator() public view override returns (uint256) {
        return _getSecuritizationTGEStorage().amountOwedToOriginator;
    }

    // address public override tgeAddress;
    // address public override secondTGEAddress;
    // address public override sotToken;
    // address public override jotToken;
    // address public override underlyingCurrency;
    // uint256 public override reserve; // Money in pool
    // uint32 public override minFirstLossCushion;

    // uint64 public override openingBlockTimestamp;
    // uint64 public override termLengthInSeconds;

    // // by default it is address(this)
    // address public override pot;

    // // for base (sell-loan) operation
    // uint256 public override principalAmountSOT;
    // uint256 public override paidPrincipalAmountSOT;
    // uint32 public override interestRateSOT; // Annually, support 4 decimals num

    // uint256 public override totalAssetRepaidCurrency;

    // mapping(address => uint256) public override paidPrincipalAmountSOTByInvestor;

    modifier onlyIssuingTokenStage() {
        CycleState _state = state();
        require(_state != CycleState.OPEN && _state != CycleState.CLOSED, 'Not in issuing token stage');
        _;
    }

    modifier finishRedemptionValidator() {
        require(hasFinishedRedemption(), 'SecuritizationPool: Redemption has not finished');
        _;
    }

    modifier notClosingStage() {
        require(!isClosedState(), 'SecuritizationPool: Pool in closed state');
        _;
    }

    function isClosedState() public view override returns (bool) {
        return state() == CycleState.CLOSED;
    }

    /// @inheritdoc ISecuritizationTGE
    function injectTGEAddress(
        address _tgeAddress,
        address _tokenAddress,
        Configuration.NOTE_TOKEN_TYPE _noteType
    ) external override whenNotPaused onlyIssuingTokenStage {
        registry().requireSecuritizationManager(_msgSender());
        require(_tgeAddress != address(0x0) && _tokenAddress != address(0x0), 'SecuritizationPool: Address zero');

        SecuritizationTGEStorage storage $ = _getSecuritizationTGEStorage();

        if (_noteType == Configuration.NOTE_TOKEN_TYPE.SENIOR) {
            $.tgeAddress = _tgeAddress;
            $.sotToken = _tokenAddress;
        } else {
            $.secondTGEAddress = _tgeAddress;
            $.jotToken = _tokenAddress;
        }

        $.state = CycleState.CROWDSALE;

        emit UpdateTGEAddress(_tgeAddress, _tokenAddress, _noteType);
    }

    /// @notice allows the redemption of tokens
    function redeem(
        address usr,
        address notesToken,
        uint256 currencyAmount,
        uint256 tokenAmount
    ) external virtual override {
        require(
            _msgSender() == address(registry().getDistributionTranche()),
            'SecuritizationPool: Caller must be DistributionTranche'
        );

        SecuritizationTGEStorage storage $ = _getSecuritizationTGEStorage();

        if ($.sotToken == notesToken) {
            $.paidPrincipalAmountSOTByInvestor[usr] += currencyAmount;
            emit UpdatePaidPrincipalAmountSOTByInvestor(usr, currencyAmount);
        }

        $.reserve = $.reserve - currencyAmount;

        if (tokenAmount > 0) {
            ERC20BurnableUpgradeable(notesToken).burn(tokenAmount);
        }

        require(checkMinFirstLost(), 'MinFirstLoss is not satisfied');
        require(
            IERC20Upgradeable($.underlyingCurrency).transferFrom($.pot, usr, currencyAmount),
            'SecuritizationPool: currency-transfer-failed'
        );

        emit UpdateReserve($.reserve);
    }

    function checkMinFirstLost() public view virtual returns (bool) {
        ISecuritizationPoolValueService poolService = registry().getSecuritizationPoolValueService();
        return _getSecuritizationTGEStorage().minFirstLossCushion <= poolService.getJuniorRatio(address(this));
    }

    // Increase by value
    function increaseTotalAssetRepaidCurrency(uint256 amount) external virtual override whenNotPaused {
        registry().requireLoanRepaymentRouter(_msgSender());

        SecuritizationTGEStorage storage $ = _getSecuritizationTGEStorage();

        $.reserve = $.reserve + amount;
        $.totalAssetRepaidCurrency = $.totalAssetRepaidCurrency + amount;

        emit UpdateReserve($.reserve);
    }

    function hasFinishedRedemption() public view override returns (bool) {
        SecuritizationTGEStorage storage $ = _getSecuritizationTGEStorage();

        if ($.sotToken != address(0)) {
            require(IERC20Upgradeable($.sotToken).totalSupply() == 0, 'SecuritizationPool: SOT still remain');
        }
        if ($.jotToken != address(0)) {
            require(IERC20Upgradeable($.jotToken).totalSupply() == 0, 'SecuritizationPool: JOT still remain');
        }

        return true;
    }

    function setPot(address _pot) external override whenNotPaused nonReentrant notClosingStage {
        registry().requirePoolAdminOrOwner(address(this), _msgSender());

        SecuritizationTGEStorage storage $ = _getSecuritizationTGEStorage();

        require($.pot != _pot, 'SecuritizationPool: Same address with current pot');
        $.pot = _pot;
        if (_pot == address(this)) {
            require(
                IERC20Upgradeable($.underlyingCurrency).approve($.pot, type(uint256).max),
                'SecuritizationPool: Pot not approved'
            );
        }
        registry().getSecuritizationManager().registerPot($.pot);
    }

    function setUpPoolNAV() public override {
        require(poolNAV() == address(0), 'SecuritizationPool: PoolNAV already set');
        IPoolNAVFactory poolNAVFactory = registry().getPoolNAVFactory();
        require(address(poolNAVFactory) != address(0), 'Pool NAV Factory was not registered');
        address poolNAVAddress = poolNAVFactory.createPoolNAV();
        SecuritizationTGEStorage storage $ = _getSecuritizationTGEStorage();
        $.poolNAV = poolNAVAddress;
    }

    function increaseReserve(uint256 currencyAmount) external override whenNotPaused {
        require(
            _msgSender() == address(registry().getSecuritizationManager()) ||
                _msgSender() == address(registry().getDistributionOperator()),
            'SecuritizationPool: Caller must be SecuritizationManager or DistributionOperator'
        );

        SecuritizationTGEStorage storage $ = _getSecuritizationTGEStorage();

        $.reserve = $.reserve + currencyAmount;
        require(checkMinFirstLost(), 'MinFirstLoss is not satisfied');

        emit UpdateReserve($.reserve);
    }

    function decreaseReserve(uint256 currencyAmount) external override whenNotPaused {
        require(
            _msgSender() == address(registry().getSecuritizationManager()) ||
                _msgSender() == address(registry().getDistributionOperator()),
            'SecuritizationPool: Caller must be SecuritizationManager or DistributionOperator'
        );

        SecuritizationTGEStorage storage $ = _getSecuritizationTGEStorage();
        $.reserve = $.reserve - currencyAmount;
        require(checkMinFirstLost(), 'MinFirstLoss is not satisfied');

        emit UpdateReserve($.reserve);
    }

    function setInterestRateForSOT(uint32 _interestRateSOT) external override whenNotPaused {
        SecuritizationTGEStorage storage $ = _getSecuritizationTGEStorage();
        require(_msgSender() == $.tgeAddress, 'SecuritizationPool: Only tge can update interest');

        $.interestRateSOT = _interestRateSOT;
        emit UpdateInterestRateSOT(_interestRateSOT);
    }

    // After closed pool and redeem all not -> get remain cash to recipient wallet
    function claimCashRemain(
        address recipientWallet
    ) external override whenNotPaused onlyOwner finishRedemptionValidator {
        SecuritizationTGEStorage storage $ = _getSecuritizationTGEStorage();

        IERC20Upgradeable currency = IERC20Upgradeable($.underlyingCurrency);
        require(
            currency.transferFrom($.pot, recipientWallet, currency.balanceOf($.pot)),
            'SecuritizationPool: Transfer failed'
        );
    }

    function startCycle(
        uint64 _termLengthInSeconds,
        uint256 _principalAmountForSOT,
        uint32 _interestRateForSOT,
        uint64 _timeStartEarningInterest
    ) external override whenNotPaused nonReentrant onlyOwner onlyIssuingTokenStage {
        require(_termLengthInSeconds > 0, 'SecuritizationPool: Term length is 0');

        SecuritizationTGEStorage storage $ = _getSecuritizationTGEStorage();

        $.termLengthInSeconds = _termLengthInSeconds;

        $.principalAmountSOT = _principalAmountForSOT;

        $.state = CycleState.OPEN;

        if ($.tgeAddress != address(0)) {
            IMintedTGE mintedTokenGenerationEvent = IMintedTGE($.tgeAddress);
            mintedTokenGenerationEvent.setupLongSale(
                _interestRateForSOT,
                _termLengthInSeconds,
                _timeStartEarningInterest
            );
            if (!IFinalizableCrowdsale($.tgeAddress).finalized()) {
                IFinalizableCrowdsale($.tgeAddress).finalize(false, $.pot);
            }
            $.interestRateSOT = mintedTokenGenerationEvent.pickedInterest();
        }
        if ($.secondTGEAddress != address(0)) {
            IFinalizableCrowdsale($.secondTGEAddress).finalize(false, $.pot);
            require(
                IFinalizableCrowdsale($.secondTGEAddress).finalized(),
                'SecuritizationPool: second sale is still on going'
            );
        }
    }

    function _setOpeningBlockTimestamp(uint64 _openingBlockTimestamp) internal {
        SecuritizationTGEStorage storage $ = _getSecuritizationTGEStorage();
        $.openingBlockTimestamp = _openingBlockTimestamp;
        emit UpdateOpeningBlockTimestamp(_openingBlockTimestamp);
    }

    function withdraw(uint256 amount) public override whenNotPaused onlyRole(ORIGINATOR_ROLE) {
        SecuritizationTGEStorage storage $ = _getSecuritizationTGEStorage();
        uint256 _amountOwedToOriginator = $.amountOwedToOriginator;
        if (amount <= _amountOwedToOriginator) {
            $.amountOwedToOriginator = _amountOwedToOriginator - amount;
        } else {
            $.amountOwedToOriginator = 0;
        }
        $.reserve = $.reserve - amount;

        require(checkMinFirstLost(), 'MinFirstLoss is not satisfied');
        require(
            IERC20Upgradeable(underlyingCurrency()).transferFrom(pot(), _msgSender(), amount),
            'SecuritizationPool: Transfer failed'
        );
        emit Withdraw(_msgSender(), amount);
    }

    function _setAmountOwedToOriginator(uint256 _amountOwedToOriginator) internal {
        SecuritizationTGEStorage storage $ = _getSecuritizationTGEStorage();
        $.amountOwedToOriginator = _amountOwedToOriginator;
    }

    function _setPot(address _pot) internal {
        SecuritizationTGEStorage storage $ = _getSecuritizationTGEStorage();
        $.pot = _pot;
    }
}
